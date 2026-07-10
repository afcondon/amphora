-- | Amphora HTTP API — the content-addressed artefact store on :3024.
-- |
-- | Endpoints (all JSON, permissive CORS):
-- |   GET  /health                         → "ok"
-- |   POST /content   {kind, payload}       → {hash, deduped}   (save→hash→dedup)
-- |   GET  /content?kind=…                  → [{hash, kind, createdAt}]
-- |   GET  /content/:hash                   → {hash, kind, payload, createdAt}
-- |   POST /labels    {contentHash, name, …} → {id}
-- |   GET  /labels?hash=…                   → [label]
-- |   POST /morphisms {from, to, kind, …}   → {ok}
-- |   GET  /morphisms?from=…&to=…           → [morphism]
-- |   POST /favorites {contentHash, collection} → {ok}
-- |   GET  /favorites?collection=…          → [favorite]
-- |   DELETE /favorites?hash=…&collection=… → {ok}   (unpublish; content stays)
-- |
-- | The BEAM rig never touches this — it's an editor-side store.
module Amphora.Main where

import Prelude

import Amphora.DuckDB as DB
import Amphora.Store as Store
import Data.Argonaut.Core as AJ
import Data.Argonaut.Parser (jsonParser)
import Data.Either (Either(..), note)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Traversable (traverse)
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Foreign.Object (Object)
import Foreign.Object as Object
import HTTPurple
  ( Method(..)
  , Request
  , ResponseM
  , badRequest'
  , ok'
  , response'
  , serve
  , toString
  )
import HTTPurple.Headers (ResponseHeaders, headers)
import HTTPurple.Lookup ((!!))
import HTTPurple.Status as Status
import Node.Encoding (Encoding(UTF8))
import Node.FS.Sync (readTextFile)
import Node.Process as Process
import Routing.Duplex (RouteDuplex', root, segment)
import Routing.Duplex.Generic (noArgs, sum)
import Routing.Duplex.Generic.Syntax ((/))
import Data.Generic.Rep (class Generic)

-- ============================================================
-- Routes — plain path segments; filters ride the query string
-- ============================================================

data Route
  = Health
  | ContentColl
  | ContentOne String
  | LabelsRoute
  | MorphismsRoute
  | FavoritesRoute

derive instance Generic Route _

route :: RouteDuplex' Route
route = root $ sum
  { "Health": "health" / noArgs
  , "ContentColl": "content" / noArgs
  , "ContentOne": "content" / segment
  , "LabelsRoute": "labels" / noArgs
  , "MorphismsRoute": "morphisms" / noArgs
  , "FavoritesRoute": "favorites" / noArgs
  }

-- ============================================================
-- JSON building
-- ============================================================

jStr :: String -> AJ.Json
jStr = AJ.fromString

jMaybe :: Maybe String -> AJ.Json
jMaybe = maybe AJ.jsonNull AJ.fromString

obj :: Array (Tuple String AJ.Json) -> AJ.Json
obj = AJ.fromObject <<< Object.fromFoldable

encPut :: Store.PutResult -> AJ.Json
encPut r = obj [ Tuple "hash" (jStr r.hash), Tuple "deduped" (AJ.fromBoolean r.deduped) ]

encMeta :: Store.ContentMeta -> AJ.Json
encMeta m = obj
  [ Tuple "hash" (jStr m.hash)
  , Tuple "kind" (jStr m.kind)
  , Tuple "createdAt" (jMaybe m.createdAt)
  ]

encContent :: Store.Content -> AJ.Json
encContent c = obj
  [ Tuple "hash" (jStr c.hash)
  , Tuple "kind" (jStr c.kind)
  , Tuple "payload" (jStr c.payload)
  , Tuple "createdAt" (jMaybe c.createdAt)
  ]

encLabel :: Store.Label -> AJ.Json
encLabel l = obj
  [ Tuple "id" (jStr l.id)
  , Tuple "contentHash" (jStr l.contentHash)
  , Tuple "name" (jStr l.name)
  , Tuple "source" (jMaybe l.source)
  , Tuple "harmonicRoot" (jMaybe l.harmonicRoot)
  , Tuple "harmonicScale" (jMaybe l.harmonicScale)
  , Tuple "harmonicChord" (jMaybe l.harmonicChord)
  , Tuple "tags" (AJ.fromArray (map jStr l.tags))
  , Tuple "createdAt" (jMaybe l.createdAt)
  ]

encMorphism :: Store.Morphism -> AJ.Json
encMorphism m = obj
  [ Tuple "from" (jStr m.fromHash)
  , Tuple "to" (jStr m.toHash)
  , Tuple "kind" (jStr m.kind)
  , Tuple "params" (jMaybe m.params)
  ]

encFavorite :: Store.Favorite -> AJ.Json
encFavorite f = obj
  [ Tuple "contentHash" (jStr f.contentHash)
  , Tuple "collection" (jStr f.collection)
  ]

errJson :: String -> String
errJson msg = AJ.stringify (obj [ Tuple "error" (jStr msg) ])

okJson :: String
okJson = AJ.stringify (obj [ Tuple "ok" (AJ.fromBoolean true) ])

-- ============================================================
-- Body parsing
-- ============================================================

asObject :: String -> Either String (Object AJ.Json)
asObject raw = case jsonParser raw of
  Left e -> Left ("bad JSON: " <> e)
  Right j -> note "expected a JSON object" (AJ.toObject j)

getStr :: String -> Object AJ.Json -> Maybe String
getStr key o = Object.lookup key o >>= AJ.toString

getStrArray :: String -> Object AJ.Json -> Array String
getStrArray key o =
  fromMaybe [] (Object.lookup key o >>= AJ.toArray >>= traverse AJ.toString)

parseContent :: String -> Either String { kind :: String, payload :: String }
parseContent raw = do
  o <- asObject raw
  kind <- note "missing field: kind" (getStr "kind" o)
  payload <- note "missing field: payload" (getStr "payload" o)
  pure { kind, payload }

parseLabel :: String -> Either String Store.LabelInput
parseLabel raw = do
  o <- asObject raw
  contentHash <- note "missing field: contentHash" (getStr "contentHash" o)
  name <- note "missing field: name" (getStr "name" o)
  pure
    { contentHash
    , name
    , source: getStr "source" o
    , harmonicRoot: getStr "harmonicRoot" o
    , harmonicScale: getStr "harmonicScale" o
    , harmonicChord: getStr "harmonicChord" o
    , tags: getStrArray "tags" o
    }

parseMorphism :: String -> Either String Store.MorphismInput
parseMorphism raw = do
  o <- asObject raw
  fromHash <- note "missing field: from" (getStr "from" o)
  toHash <- note "missing field: to" (getStr "to" o)
  kind <- note "missing field: kind" (getStr "kind" o)
  -- params: any JSON value, stored as its canonical string form.
  pure { fromHash, toHash, kind, params: AJ.stringify <$> Object.lookup "params" o }

parseFavorite :: String -> Either String Store.Favorite
parseFavorite raw = do
  o <- asObject raw
  contentHash <- note "missing field: contentHash" (getStr "contentHash" o)
  collection <- note "missing field: collection" (getStr "collection" o)
  pure { contentHash, collection }

-- ============================================================
-- CORS
-- ============================================================

corsHeaders :: ResponseHeaders
corsHeaders = headers
  { "Access-Control-Allow-Origin": "*"
  , "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS"
  , "Access-Control-Allow-Headers": "Content-Type"
  }

jsonCors :: ResponseHeaders
jsonCors = headers
  { "Content-Type": "application/json"
  , "Access-Control-Allow-Origin": "*"
  , "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS"
  , "Access-Control-Allow-Headers": "Content-Type"
  }

-- | Query param, treating an absent value and an empty value alike.
qparam :: Object String -> String -> Maybe String
qparam q key = case q !! key of
  Just s | s /= "" -> Just s
  _ -> Nothing

-- ============================================================
-- Router
-- ============================================================

mkRouter :: DB.Database -> Request Route -> ResponseM
mkRouter db { route: r, method, body, query } = case method of
  Options -> ok' corsHeaders ""
  _ -> case r of
    Health -> ok' corsHeaders "ok"

    ContentColl -> case method of
      Post -> do
        raw <- toString body
        case parseContent raw of
          Left e -> badRequest' jsonCors (errJson e)
          Right c -> do
            res <- Store.putContent db c
            sendJson (encPut res)
      Get -> do
        metas <- Store.listContent db (qparam query "kind")
        sendJson (AJ.fromArray (map encMeta metas))
      _ -> notAllowed

    ContentOne hash -> case method of
      Get -> do
        mc <- Store.getContent db hash
        case mc of
          Nothing -> response' Status.notFound jsonCors (errJson "no such content")
          Just c -> sendJson (encContent c)
      _ -> notAllowed

    LabelsRoute -> case method of
      Get -> do
        ls <- Store.listLabels db (qparam query "hash")
        sendJson (AJ.fromArray (map encLabel ls))
      Post -> do
        raw <- toString body
        case parseLabel raw of
          Left e -> badRequest' jsonCors (errJson e)
          Right inp -> do
            mId <- Store.addLabel db inp
            case mId of
              Just idS -> sendJson (obj [ Tuple "id" (jStr idS) ])
              Nothing -> response' Status.internalServerError jsonCors (errJson "label insert failed")
      _ -> notAllowed

    MorphismsRoute -> case method of
      Get -> do
        ms <- Store.listMorphisms db (qparam query "from") (qparam query "to")
        sendJson (AJ.fromArray (map encMorphism ms))
      Post -> do
        raw <- toString body
        case parseMorphism raw of
          Left e -> badRequest' jsonCors (errJson e)
          Right m -> do
            Store.addMorphism db m
            ok' jsonCors okJson
      _ -> notAllowed

    FavoritesRoute -> case method of
      Get -> do
        fs <- Store.listFavorites db (qparam query "collection")
        sendJson (AJ.fromArray (map encFavorite fs))
      Post -> do
        raw <- toString body
        case parseFavorite raw of
          Left e -> badRequest' jsonCors (errJson e)
          Right f -> do
            Store.addFavorite db f
            ok' jsonCors okJson
      -- unpublish: DELETE /favorites?hash=<h>&collection=<c> removes the content
      -- from that collection (content + labels stay addressable).
      Delete -> case qparam query "hash", qparam query "collection" of
        Just h, Just c -> do
          Store.removeFavorite db { contentHash: h, collection: c }
          ok' jsonCors okJson
        _, _ -> badRequest' jsonCors (errJson "DELETE /favorites needs ?hash= and ?collection=")
      _ -> notAllowed
  where
  sendJson j = ok' jsonCors (AJ.stringify j)
  notAllowed = response' Status.methodNotAllowed jsonCors (errJson "method not allowed")

-- ============================================================
-- Boot
-- ============================================================

resolvePort :: Effect Int
resolvePort = do
  a <- Process.lookupEnv "AMPHORA_PORT"
  b <- Process.lookupEnv "BACKEND_PORT"
  let raw = case a of
        Just _ -> a
        Nothing -> b
  pure (fromMaybe 3024 (raw >>= Int.fromString))

resolveDbPath :: Effect String
resolveDbPath = fromMaybe "db/amphora.duckdb" <$> Process.lookupEnv "AMPHORA_DB"

main :: Effect Unit
main = do
  port <- resolvePort
  dbPath <- resolveDbPath
  ddl <- readTextFile UTF8 "schema/init.sql"
  launchAff_ do
    db <- DB.openDB dbPath
    Store.initSchema db ddl
    liftEffect do
      Console.log ("Amphora ⚱  listening on :" <> show port <> "  ·  db=" <> dbPath)
      void $ serve { port, hostname: "0.0.0.0" } { route, router: mkRouter db }
