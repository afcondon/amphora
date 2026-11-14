-- | Amphora's HTTP server — the content-addressed artefact store on :3024.
-- |
-- | What it answers is declared once, in `Amphora.Api` (api/), and said for
-- | people in `conformance/AMPHORA-API.md`. This module has no paths, no
-- | field names and no JSON of its own: each operation of the description is
-- | paired here with the work in `Amphora.Store` that carries it out, and
-- | `Hawser.Http` does the reading of the request and the writing of the
-- | answer. A request the description does not accept is refused (400) and
-- | never reaches the store.
-- |
-- | `make conformance` holds this to the description, against a database of
-- | its own.
-- |
-- | The BEAM rig never touches this — it's an editor-side store.
module Amphora.Main where

import Prelude

import Amphora.Api as Api
import Amphora.DuckDB as DB
import Amphora.Store as Store
import Data.Argonaut.Core as AJ
import Data.Either (Either(..))
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Foreign.Object as Object
import HTTPurple (Method(..), Request, ResponseM, ok', response', serve, toString)
import HTTPurple.Headers (ResponseHeaders, headers)
import Hawser.Http (Answer, Endpoint, Handler, Routed(..), dispatch, handle)
import Hawser.Value (toText)
import Node.Encoding (Encoding(UTF8))
import Node.FS.Sync (readTextFile)
import Node.Process as Process
import Routing.Duplex (RouteDuplex', rest, root)

-- ============================================================
-- The operations, each with its work
-- ============================================================

-- | An answer that is not success: a status the operation declares, and a
-- | sentence for a person.
problem :: Int -> String -> Answer
problem status sentence = { status, contentType: "application/json", body: toText Api.problem { error: sentence } }

-- | Work that cannot fail.
always :: forall request reply. Endpoint request reply -> (request -> Aff reply) -> Handler Aff
always described work = handle described (map Right <<< work)

done :: Aff Unit -> Aff Api.Done
done work = work $> { ok: true }

operations :: DB.Database -> Array (Handler Aff)
operations db =
  [ always Api.health \_ -> pure unit

  , always Api.putContent (Store.putContent db)
  , always Api.listContent \{ kind } -> Store.listContent db kind
  , handle Api.getContent \{ hash } -> Store.getContent db hash <#> case _ of
      Just content -> Right content
      Nothing -> Left (problem 404 "no such content")

  , handle Api.addLabel \label ->
      Store.addLabel db
        { contentHash: label.contentHash
        , name: label.name
        , source: label.source
        , harmonicRoot: label.harmonicRoot
        , harmonicScale: label.harmonicScale
        , harmonicChord: label.harmonicChord
        , tags: fromMaybe [] label.tags
        } <#> case _ of
        Just id -> Right { id }
        Nothing -> Left (problem 500 "label insert failed")
  , always Api.listLabels \{ hash } -> Store.listLabels db hash

  -- params: any JSON value, stored as its canonical string form.
  , always Api.addMorphism \{ from, to, kind, params } ->
      done (Store.addMorphism db { fromHash: from, toHash: to, kind, params: AJ.stringify <$> params })
  , always Api.listMorphisms \{ from, to } ->
      Store.listMorphisms db from to <#> map \found -> { from: found.fromHash, to: found.toHash, kind: found.kind, params: found.params }

  , always Api.addFavorite (done <<< Store.addFavorite db)
  , always Api.listFavorites \{ collection } -> Store.listFavorites db collection
  -- unpublish: the content and its labels stay addressable.
  , always Api.removeFavorite \{ hash, collection } -> done (Store.removeFavorite db { contentHash: hash, collection })

  , always Api.listRefs \{ prefix } -> Store.listRefs db (fromMaybe "" prefix)
  , handle Api.getRef \{ name } -> Store.getRef db name <#> case _ of
      Just ref -> Right ref
      Nothing -> Left (problem 404 "no such ref")
  , handle Api.moveRef \move -> Store.moveRef db move <#> case _ of
      Store.Moved ref -> Right ref
      Store.NoSuchContent -> Left (problem 404 "no such content")
      Store.Stale current -> Left
        { status: 409
        , contentType: "application/json"
        , body: toText Api.stale { error: "the ref has moved", current }
        }
  , always Api.listMoves \{ ref } -> Store.listRefMoves db ref
  ]

-- ============================================================
-- The server
-- ============================================================

-- | Open to any page: the editors are served from other ports.
cors :: String -> ResponseHeaders
cors contentType = headers
  { "Content-Type": contentType
  , "Access-Control-Allow-Origin": "*"
  , "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS"
  , "Access-Control-Allow-Headers": "Content-Type"
  }

-- | Every path, as its segments: which operation a request is for is the
-- | description's business, not the router's.
route :: RouteDuplex' (Array String)
route = root rest

methodName :: Method -> String
methodName = case _ of
  Get -> "GET"
  Post -> "POST"
  Put -> "PUT"
  Delete -> "DELETE"
  Head -> "HEAD"
  Connect -> "CONNECT"
  Options -> "OPTIONS"
  Trace -> "TRACE"
  Patch -> "PATCH"

mkRouter :: DB.Database -> Request (Array String) -> ResponseM
mkRouter db = \{ method, path, query, body } -> case method of
  Options -> ok' (cors "text/plain") ""
  _ -> do
    raw <- toString body
    let
      wire =
        { method: methodName method
        , path
        , query: Object.toUnfoldable query
        , body: raw
        }
    case dispatch handlers wire of
      Run work -> work >>= send
      Unusable400 sentence -> send (problem 400 sentence)
      NoSuchMethod -> send (problem 405 "method not allowed")
      Nowhere -> send (problem 404 "no such path")
  where
  handlers = operations db
  send answer = response' answer.status (cors answer.contentType) answer.body

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
