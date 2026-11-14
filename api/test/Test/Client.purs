-- | The PureScript client (`Hawser.Fetch.ask` with the operations of
-- | `Amphora.Api`) against a real server: typed requests in, typed answers
-- | out. `conformance/client.mjs` starts the server and runs this.
-- |
-- | The scenario (`Test.Scenario`) holds the server to the description, as
-- | plain requests. This holds the path a PureScript client actually takes:
-- | the record, the call, `fetch`, the strict reading of the answer.
module Test.Client (run) where

import Prelude

import Amphora.Api as Api
import Control.Promise (Promise, fromAff)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff)
import Hawser.Fetch (Store, Trouble(..), ask, troubleText)
import Test.Scenario (alpha, beta)

-- | Every expectation that did not hold. Empty when the client is right.
run :: String -> Effect (Promise (Array String))
run base = fromAff (checks { base, timeoutMs: 5000 })

checks :: Store -> Aff (Array String)
checks store = do
  up <- ask store Api.health {}
  first <- ask store Api.putContent { kind, payload: "alpha" }
  again <- ask store Api.putContent { kind, payload: "alpha" }
  second <- ask store Api.putContent { kind, payload: "beta" }
  got <- ask store Api.getContent { hash: alpha }
  missing <- ask store Api.getContent { hash: "0000" }
  unsent <- ask store Api.getContent { hash: "" }
  _ <- ask store Api.addLabel { contentHash: alpha, name: "né / first", source: Just "user", harmonicRoot: Nothing, harmonicScale: Nothing, harmonicChord: Nothing, tags: Just [ "a" ] }
  labels <- ask store Api.listLabels { hash: Just alpha }
  _ <- ask store Api.addFavorite { contentHash: alpha, collection }
  favourites <- ask store Api.listFavorites { collection: Just collection }
  _ <- ask store Api.removeFavorite { hash: alpha, collection }
  none <- ask store Api.listFavorites { collection: Just collection }
  _ <- ask store Api.addMorphism { from: alpha, to: beta, kind: "edit", params: Nothing }
  morphisms <- ask store Api.listMorphisms { from: Just alpha, to: Nothing }
  absent <- ask store Api.getRef { name: refName }
  created <- ask store Api.moveRef { name: refName, to: alpha, expected: Nothing }
  moved <- ask store Api.moveRef { name: refName, to: beta, expected: Just alpha }
  stale <- ask store Api.moveRef { name: refName, to: alpha, expected: Just alpha }
  refs <- ask store Api.listRefs { prefix: Just "client/" }
  moves <- ask store Api.listMoves { ref: refName }
  nowhere <- ask (store { base = "http://127.0.0.1:9" }) Api.health {}
  pure $ Array.catMaybes
    [ expect "health" (up == Right unit) (said up)
    , expect "a first save is not deduped" ((first <#> \saved -> saved.hash == alpha && not saved.deduped) == Right true) (said first)
    , expect "a second save is" ((again <#> _.deduped) == Right true) (said again)
    , expect "other content" ((second <#> _.hash) == Right beta) (said second)
    , expect "content comes back" ((got <#> \content -> content.payload == "alpha" && content.kind == kind) == Right true) (said got)
    , expect "unknown content is its declared failure" (isFailed 404 missing) (said missing)
    , expect "an empty hash is never sent" (unsent == Left (NotSent "empty-hash") # eq true) (said unsent)
    , expect "a label, with a name that needs escaping in JSON and not in a path"
        ((labels <#> map (\label -> { name: label.name, source: label.source, tags: label.tags, root: label.harmonicRoot })) == Right [ { name: "né / first", source: Just "user", tags: [ "a" ], root: Nothing } ])
        (said labels)
    , expect "published" ((favourites <#> map _.contentHash) == Right [ alpha ]) (said favourites)
    , expect "unpublished" ((none <#> Array.length) == Right 0) (said none)
    , expect "a morphism without parameters" ((morphisms <#> map (\morphism -> { to: morphism.to, params: morphism.params })) == Right [ { to: beta, params: Nothing } ]) (said morphisms)
    , expect "no ref yet" (isFailed 404 absent) (said absent)
    , expect "a ref whose name has a `/`" ((created <#> \ref -> ref.name == refName && ref.hash == alpha) == Right true) (said created)
    , expect "it moves" ((moved <#> _.hash) == Right beta) (said moved)
    , expect "a stale move is its declared failure" (isFailed 409 stale) (said stale)
    , expect "refs by prefix" ((refs <#> map _.name) == Right [ refName ]) (said refs)
    , expect "its moves, oldest first" ((moves <#> map (\move -> { from: move.from, to: move.to })) == Right [ { from: Nothing, to: alpha }, { from: Just alpha, to: beta } ]) (said moves)
    , expect "no server is no answer" (isUnreachable nowhere) (said nowhere)
    ]
  where
  kind = "client-kind"
  collection = "client-collection"
  refName = "client/library"

  expect :: String -> Boolean -> String -> Maybe String
  expect label holds answered = if holds then Nothing else Just (label <> " (" <> answered <> ")")

  said :: forall a. Either Trouble a -> String
  said = case _ of
    Left trouble -> troubleText trouble
    Right _ -> "answered, but not with that"

  isFailed :: forall a. Int -> Either Trouble a -> Boolean
  isFailed status = case _ of
    Left (Failed answered _) -> answered == status
    _ -> false

  isUnreachable :: forall a. Either Trouble a -> Boolean
  isUnreachable = case _ of
    Left (Unreachable _) -> true
    _ -> false
