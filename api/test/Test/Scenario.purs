-- | One scenario, written by hand: every operation of Amphora's API against
-- | a store that starts empty, in order, with what each must answer.
-- |
-- | A step is a request and an expectation. The expectation is a status,
-- | and optionally a `body` the answer must CONTAIN (every key given must be
-- | there with that value; for an array, each element given must be
-- | contained in some element of the answer) and a `count` of elements. An
-- | identifier or a time the store makes up is never asserted.
-- |
-- | Most requests are made with `call`, from the description. A few are
-- | written out, to send what `call` would never produce.
-- |
-- | The two hashes were computed apart from any of this:
-- | `printf '%s' alpha | shasum -a 256`.
module Test.Scenario
  ( Step
  , steps
  , alpha
  , beta
  ) where

import Prelude

import Amphora.Api as Api
import Data.Argonaut.Core (Json)
import Data.Argonaut.Core as Json
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Foreign.Object as Object
import Hawser.Http (Endpoint(..), Wire, call)

type Step =
  { name :: String
  -- | The operation, by name; empty for a request that is nobody's.
  , operation :: String
  , wire :: Wire
  -- | Why `call` refused to make the request, if it did. Always empty in
  -- | a scenario that is right.
  , unmade :: String
  , status :: Int
  , body :: Maybe Json
  , count :: Maybe Int
  , why :: String
  }

alpha :: String
alpha = "8ed3f6ad685b959ead7022518e1af76cd816f8e8ec7ccdda1ed4018e8f2223f8"

beta :: String
beta = "f44e64e75f3948e9f73f8dfa94721c4ce8cbb4f265c4790c702b2d41cfbf2753"

-- | A step made from the description.
sent :: forall request reply. String -> Endpoint request reply -> request -> Int -> String -> Step
sent name described@(Endpoint { name: operation }) request status why = case call described request of
  Right wire -> { name, operation, wire, unmade: "", status, body: Nothing, count: Nothing, why }
  Left tag -> { name, operation, wire: { method: "", path: [], query: [], body: "" }, unmade: tag, status, body: Nothing, count: Nothing, why }

-- | A step written out.
raw :: String -> String -> String -> Array String -> Array (Tuple String String) -> String -> Int -> String -> Step
raw name operation method path query body status why =
  { name, operation, wire: { method, path, query, body }, unmade: "", status, body: Nothing, count: Nothing, why }

containing :: Json -> Step -> Step
containing body step = step { body = Just body }

counting :: Int -> Step -> Step
counting count step = step { count = Just count }

object :: Array (Tuple String Json) -> Json
object = Object.fromFoldable >>> Json.fromObject

text :: String -> Json
text = Json.fromString

list :: Array Json -> Json
list = Json.fromArray

collection :: String
collection = "conformance-collection"

kind :: String
kind = "conformance-kind"

refName :: String
refName = "conformance/library"

steps :: Array Step
steps =
  [ sent "health" Api.health {} 200 "the store is up"

  -- Content
  , sent "put-alpha" Api.putContent { kind, payload: "alpha" } 200 "new content is saved under the hash of its payload"
      # containing (object [ Tuple "hash" (text alpha), Tuple "deduped" (Json.fromBoolean false) ])
  , sent "put-alpha-again" Api.putContent { kind, payload: "alpha" } 200 "the same payload is not saved twice"
      # containing (object [ Tuple "hash" (text alpha), Tuple "deduped" (Json.fromBoolean true) ])
  , sent "put-beta" Api.putContent { kind, payload: "beta" } 200 "other content"
      # containing (object [ Tuple "hash" (text beta) ])
  , raw "put-without-payload" "putContent" "POST" [ "content" ] [] "{\"kind\":\"x\"}" 400 "a payload is required"
  , raw "put-not-json" "putContent" "POST" [ "content" ] [] "kind=x" 400 "the body is JSON"
  , raw "put-an-array" "putContent" "POST" [ "content" ] [] "[]" 400 "the body is an object"
  , sent "get-alpha" Api.getContent { hash: alpha } 200 "content comes back as saved"
      # containing (object [ Tuple "hash" (text alpha), Tuple "kind" (text kind), Tuple "payload" (text "alpha") ])
  , sent "get-unknown" Api.getContent { hash: "0000" } 404 "no content has that hash"
  , sent "list-of-kind" Api.listContent { kind: Just kind } 200 "both, without payloads"
      # containing (list [ object [ Tuple "hash" (text alpha), Tuple "kind" (text kind) ], object [ Tuple "hash" (text beta) ] ])
      # counting 2
  , sent "list-of-no-kind" Api.listContent { kind: Just "conformance-absent" } 200 "nothing of that kind"
      # counting 0
  , sent "list-all" Api.listContent { kind: Nothing } 200 "everything"
      # counting 2

  -- Labels
  , sent "label-full" Api.addLabel
      { contentHash: alpha, name: "first", source: Just "user", harmonicRoot: Just "D", harmonicScale: Just "dorian", harmonicChord: Nothing, tags: Just [ "a", "b" ] }
      200
      "a label with most of what a label may carry"
  , sent "label-bare" Api.addLabel
      { contentHash: alpha, name: "plain", source: Nothing, harmonicRoot: Nothing, harmonicScale: Nothing, harmonicChord: Nothing, tags: Nothing }
      200
      "a label with a name alone"
  , raw "label-without-name" "addLabel" "POST" [ "labels" ] [] ("{\"contentHash\":\"" <> alpha <> "\"}") 400 "a name is required"
  , sent "labels-of-alpha" Api.listLabels { hash: Just alpha } 200 "both labels, with what was left out as null and no tags as none"
      # containing
          ( list
              [ object
                  [ Tuple "contentHash" (text alpha)
                  , Tuple "name" (text "first")
                  , Tuple "source" (text "user")
                  , Tuple "harmonicRoot" (text "D")
                  , Tuple "harmonicScale" (text "dorian")
                  , Tuple "harmonicChord" Json.jsonNull
                  , Tuple "tags" (list [ text "a", text "b" ])
                  ]
              , object [ Tuple "name" (text "plain"), Tuple "source" Json.jsonNull, Tuple "tags" (list []) ]
              ]
          )
      # counting 2
  , sent "labels-of-beta" Api.listLabels { hash: Just beta } 200 "beta has none"
      # counting 0

  -- Favourites
  , sent "favourite-alpha" Api.addFavorite { contentHash: alpha, collection } 200 "published"
      # containing (object [ Tuple "ok" (Json.fromBoolean true) ])
  , sent "favourite-beta" Api.addFavorite { contentHash: beta, collection } 200 "published"
  , raw "favourite-without-collection" "addFavorite" "POST" [ "favorites" ] [] ("{\"contentHash\":\"" <> alpha <> "\"}") 400 "a collection is required"
  , sent "favourites-both" Api.listFavorites { collection: Just collection } 200 "both"
      # containing (list [ object [ Tuple "contentHash" (text alpha), Tuple "collection" (text collection) ] ])
      # counting 2
  , sent "unfavourite-beta" Api.removeFavorite { hash: beta, collection } 200 "taken out of the collection"
  , sent "favourites-one" Api.listFavorites { collection: Just collection } 200 "alpha alone"
      # counting 1
  , sent "beta-still-there" Api.getContent { hash: beta } 200 "taking it out of a collection does not delete it"
  , raw "unfavourite-without-collection" "removeFavorite" "DELETE" [ "favorites" ] [ Tuple "hash" beta ] "" 400 "both are required"

  -- Morphisms
  , sent "morphism-with-params" Api.addMorphism
      { from: alpha, to: beta, kind: "edit", params: Just (object [ Tuple "n" (Json.fromNumber 1.0) ]) }
      200
      "a step with parameters"
  , sent "morphism-bare" Api.addMorphism { from: beta, to: alpha, kind: "undo", params: Nothing } 200 "a step without"
  , raw "morphism-without-kind" "addMorphism" "POST" [ "morphisms" ] [] ("{\"from\":\"" <> alpha <> "\",\"to\":\"" <> beta <> "\"}") 400 "a kind is required"
  , sent "morphisms-from-alpha" Api.listMorphisms { from: Just alpha, to: Nothing } 200 "the parameters come back as the text of the JSON given"
      # containing (list [ object [ Tuple "from" (text alpha), Tuple "to" (text beta), Tuple "kind" (text "edit"), Tuple "params" (text "{\"n\":1}") ] ])
      # counting 1
  , sent "morphisms-to-alpha" Api.listMorphisms { from: Nothing, to: Just alpha } 200 "without parameters, null"
      # containing (list [ object [ Tuple "kind" (text "undo"), Tuple "params" Json.jsonNull ] ])
      # counting 1

  -- Refs
  , sent "ref-absent" Api.getRef { name: refName } 404 "there is no such ref yet"
  , sent "ref-create" Api.moveRef { name: refName, to: alpha, expected: Nothing } 200 "expecting nothing creates it; its name has a `/` in it"
      # containing (object [ Tuple "name" (text refName), Tuple "hash" (text alpha) ])
  , sent "ref-create-again" Api.moveRef { name: refName, to: beta, expected: Nothing } 409 "expecting nothing, when it exists, is stale"
      # containing (object [ Tuple "current" (object [ Tuple "name" (text refName), Tuple "hash" (text alpha) ]) ])
  , sent "ref-move" Api.moveRef { name: refName, to: beta, expected: Just alpha } 200 "it pointed where expected, so it moves"
      # containing (object [ Tuple "hash" (text beta) ])
  , sent "ref-move-stale" Api.moveRef { name: refName, to: alpha, expected: Just alpha } 409 "it no longer points there; the answer says where it does"
      # containing (object [ Tuple "current" (object [ Tuple "hash" (text beta) ]) ])
  , sent "ref-move-nowhere" Api.moveRef { name: refName, to: "0000", expected: Just beta } 404 "no content has the hash to move to"
  , raw "ref-move-without-to" "moveRef" "POST" [ "refs", "conformance", "library" ] [] "{}" 400 "where to is required"
  , sent "ref-get" Api.getRef { name: refName } 200 "where it points now"
      # containing (object [ Tuple "name" (text refName), Tuple "hash" (text beta) ])
  , sent "refs-by-prefix" Api.listRefs { prefix: Just "conformance/" } 200 "the one ref under the prefix"
      # containing (list [ object [ Tuple "name" (text refName) ] ])
      # counting 1
  , sent "refs-by-other-prefix" Api.listRefs { prefix: Just "conformance-absent/" } 200 "none"
      # counting 0
  , sent "moves" Api.listMoves { ref: refName } 200 "both moves, oldest first; the first came from nowhere"
      # containing (list [ object [ Tuple "from" Json.jsonNull, Tuple "to" (text alpha) ], object [ Tuple "from" (text alpha), Tuple "to" (text beta) ] ])
      # counting 2
  , raw "moves-without-ref" "listMoves" "GET" [ "moves" ] [] "" 400 "which ref is required"
  , sent "ref-move-is-a-morphism" Api.listMorphisms { from: Just alpha, to: Just beta } 200 "a ref moving from one content to another is recorded as a morphism"
      # containing (list [ object [ Tuple "kind" (text ("ref:" <> refName)) ] ])
      # counting 2

  -- Nobody's
  , raw "wrong-method" "" "DELETE" [ "content" ] [] "" 405 "an operation's path under a method it does not have"
  , raw "unknown-path" "" "GET" [ "conformance-nowhere" ] [] "" 404 "a path that is no operation's"
  ]
