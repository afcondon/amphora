-- | What is generated from the description: the vector file, the OpenAPI
-- | file and the document's table. `make vectors` writes them; `make
-- | check-vectors` fails if any is out of date.
module Test.Generate (vectors, openapi, table) where

import Prelude

import Amphora.Api as Api
import Data.Argonaut.Core (Json)
import Data.Argonaut.Core as Json
import Data.Argonaut.Parser (jsonParser)
import Data.Either (Either(..))
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Console (log)
import Foreign.Object as Object
import Hawser.Document as Document
import Hawser.Http (row, target)
import Hawser.OpenApi as OpenApi
import Test.Scenario (steps)

object :: Array (Tuple String Json) -> Json
object = Object.fromFoldable >>> Json.fromObject

text :: String -> Json
text = Json.fromString

vectorsJson :: Json
vectorsJson = object
  [ Tuple "amphora-api-vectors" (Json.fromNumber 1.0)
  , Tuple "declaration" (text "conformance/AMPHORA-API.md")
  , Tuple "generatedBy" (text "Test.Generate in amphora/api; do not edit by hand, run `make vectors`")
  , Tuple "operations" $ Json.fromArray
      ( Api.operations <#> \operation -> object
          [ Tuple "name" (text operation.name), Tuple "method" (text operation.method), Tuple "template" (text operation.template) ]
      )
  , Tuple "scenario" $ Json.fromArray
      ( steps <#> \step -> object
          ( [ Tuple "name" (text step.name)
            , Tuple "why" (text step.why)
            , Tuple "operation" (text step.operation)
            , Tuple "method" (text step.wire.method)
            , Tuple "path" (Json.fromArray (map text step.wire.path))
            , Tuple "query" (Json.fromArray (step.wire.query <#> \(Tuple key value) -> Json.fromArray [ text key, text value ]))
            -- The body as JSON where it is JSON, so that a client is
            -- compared on what it says and not on how it spaces it.
            , Tuple "body" case jsonParser step.wire.body of
                Right parsed | step.wire.body /= "" -> parsed
                _ -> Json.jsonNull
            , Tuple "bodyText" (text step.wire.body)
            , Tuple "target" (text (target step.wire))
            , Tuple "status" (Json.fromNumber (Int.toNumber step.status))
            ]
              <> case step.body of
                Just contained -> [ Tuple "contains" contained ]
                Nothing -> []
              <> case step.count of
                Just count -> [ Tuple "count" (Json.fromNumber (Int.toNumber count)) ]
                Nothing -> []
          )
      )
  ]

vectors :: Effect Unit
vectors = log (Json.stringifyWithIndent 2 vectorsJson)

openapi :: Effect Unit
openapi = log $ Json.stringifyWithIndent 2 $ OpenApi.document
  { title: "Amphora"
  , version: "1"
  , description: "The Atlantis artefact store: immutable content named by the hash of its payload, with labels, favourites, morphisms and refs. Generated from Amphora.Api; see conformance/AMPHORA-API.md."
  , server: "http://localhost:3024"
  }
  Api.operations

table :: String
table = (Document.tableWith [ "Operation", "Request", "Body", "Answer", "Failures", "Meaning" ] (map row Api.operations))
