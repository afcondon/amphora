-- | What can be checked without a server: the scenario is well made, and
-- | covers the description.
module Test.Main (main, failures, summary) where

import Prelude

import Amphora.Api as Api
import Data.Array as Array
import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Console (log)
import Effect.Exception (throw)
import Test.Scenario (Step, steps)

failures :: Array String
failures =
  Array.concatMap unmade steps
    <> duplicated
    <> Array.concatMap accepted steps
    <> Array.concatMap covered Api.operations
  where
  unmade :: Step -> Array String
  unmade step = if step.unmade == "" then [] else [ step.name <> ": the description refuses to make this request (" <> step.unmade <> ")" ]

  duplicated =
    let
      names = map _.name steps
    in
      if Array.length (Array.nub names) == Array.length names then [] else [ "two steps share a name" ]

  -- A step that expects success must be a request its operation accepts;
  -- one that expects 400 must be one it does not.
  accepted :: Step -> Array String
  accepted step = case Array.find (\operation -> operation.name == step.operation) Api.operations of
    Nothing -> if step.operation == "" then [] else [ step.name <> ": no operation is called " <> step.operation ]
    Just operation ->
      if step.status == 400 && operation.accepts step.wire then [ step.name <> ": expects 400, but the description accepts the request" ]
      else if step.status /= 400 && not (operation.accepts step.wire) then [ step.name <> ": the description does not accept the request" ]
      else []

  -- Every operation succeeds in some step, and every failure it declares
  -- is met in some step.
  covered operation =
    let
      mine = Array.filter (\step -> step.operation == operation.name) steps
      met status = Array.any (\step -> step.status == status) mine
      -- A failure of the store itself cannot be asked for.
      wanted = Array.filter (_ /= 500) (Array.nub (map _.status operation.failures))
    in
      (if met 200 then [] else [ operation.name <> ": no step in which it succeeds" ])
        <> (Array.filter (not <<< met) wanted <#> \status -> operation.name <> ": no step that meets its " <> show status)

summary :: String
summary = show (Array.length Api.operations) <> " operations, " <> show (Array.length steps) <> " steps; " <> show (Array.length failures) <> " failures"

main :: Effect Unit
main = do
  for_ failures log
  log summary
  case failures of
    [] -> pure unit
    _ -> throw "the scenario does not hold"
