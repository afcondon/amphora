-- | The Amphora store — content-addressed reads and writes over DuckDB.
-- |
-- | `putContent` is the keystone: it hashes the canonical payload, and if
-- | that hash is already present it does nothing and reports `deduped`.
-- | Content is never updated in place — an "edit" is new content plus a
-- | re-pointed label (see `addLabel`). Labels, morphisms and favourites are
-- | the mutable, human-facing layer on top of the immutable content table.
module Amphora.Store
  ( Content
  , ContentMeta
  , PutResult
  , Label
  , LabelInput
  , Morphism
  , MorphismInput
  , Favorite
  , initSchema
  , putContent
  , getContent
  , listContent
  , addLabel
  , listLabels
  , addMorphism
  , listMorphisms
  , addFavorite
  , listFavorites
  ) where

import Prelude

import Amphora.DuckDB (Database, Row)
import Amphora.DuckDB as DB
import Amphora.Hash (sha256Hex)
import Data.Array (catMaybes, mapMaybe, null)
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.String (joinWith)
import Data.Traversable (traverse)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Foreign (Foreign, unsafeToForeign)

-- ============================================================
-- Row shapes
-- ============================================================

-- | Full content record (payload included).
type Content =
  { hash :: String
  , kind :: String
  , payload :: String
  , createdAt :: Maybe String
  }

-- | Content without the payload — for browse listings.
type ContentMeta =
  { hash :: String
  , kind :: String
  , createdAt :: Maybe String
  }

-- | Result of a content-addressed save.
type PutResult =
  { hash :: String
  , deduped :: Boolean
  }

type Label =
  { id :: String
  , contentHash :: String
  , name :: String
  , source :: Maybe String
  , harmonicRoot :: Maybe String
  , harmonicScale :: Maybe String
  , harmonicChord :: Maybe String
  , tags :: Array String
  , createdAt :: Maybe String
  }

type LabelInput =
  { contentHash :: String
  , name :: String
  , source :: Maybe String
  , harmonicRoot :: Maybe String
  , harmonicScale :: Maybe String
  , harmonicChord :: Maybe String
  , tags :: Array String
  }

type Morphism =
  { fromHash :: String
  , toHash :: String
  , kind :: String
  , params :: Maybe String
  }

type MorphismInput = Morphism

type Favorite =
  { contentHash :: String
  , collection :: String
  }

-- ============================================================
-- Schema
-- ============================================================

-- | Apply the schema DDL (idempotent — run on every start).
initSchema :: Database -> String -> Aff Unit
initSchema db ddl = DB.exec db ddl

-- ============================================================
-- Content — the immutable, content-addressed table
-- ============================================================

-- | Hash the canonical payload; insert only if new. `deduped = true`
-- | means the hash was already present, so nothing was written.
putContent :: Database -> { kind :: String, payload :: String } -> Aff PutResult
putContent db { kind, payload } = do
  hash <- liftEffect (sha256Hex payload)
  existing <- DB.queryAllParams db "SELECT 1 AS x FROM content WHERE hash = ?" [ DB.param hash ]
  let deduped = not (DB.isEmpty existing)
  when (not deduped) $
    DB.run db "INSERT INTO content (hash, kind, payload) VALUES (?, ?, ?)"
      [ DB.param hash, DB.param kind, DB.param payload ]
  pure { hash, deduped }

getContent :: Database -> String -> Aff (Maybe Content)
getContent db hash = do
  rows <- DB.queryAllParams db
    "SELECT hash, kind, payload, created_at FROM content WHERE hash = ?"
    [ DB.param hash ]
  pure (DB.firstRow rows >>= decodeContent)

decodeContent :: Row -> Maybe Content
decodeContent row = do
  hash <- DB.readField "hash" row
  kind <- DB.readField "kind" row
  payload <- DB.readField "payload" row
  pure { hash, kind, payload, createdAt: DB.readField "created_at" row }

listContent :: Database -> Maybe String -> Aff (Array ContentMeta)
listContent db mKind = do
  rows <- case mKind of
    Just k -> DB.queryAllParams db
      (metaBase <> " WHERE kind = ? ORDER BY created_at DESC") [ DB.param k ]
    Nothing -> DB.queryAll db (metaBase <> " ORDER BY created_at DESC")
  pure (mapMaybe decodeMeta rows)
  where
  metaBase = "SELECT hash, kind, created_at FROM content"
  decodeMeta row = do
    hash <- DB.readField "hash" row
    kind <- DB.readField "kind" row
    pure { hash, kind, createdAt: DB.readField "created_at" row }

-- ============================================================
-- Labels — mutable metadata; one content, many labels
-- ============================================================

-- | Insert a label and its tags. Returns the new label id (from
-- | `RETURNING id`) so tags can be attached and the client can refer back.
addLabel :: Database -> LabelInput -> Aff (Maybe String)
addLabel db inp = do
  rows <- DB.queryAllParams db
    ( "INSERT INTO label "
        <> "(content_hash, name, source, harmonic_root, harmonic_scale, harmonic_chord) "
        <> "VALUES (?, ?, ?, ?, ?, ?) RETURNING id"
    )
    [ DB.param inp.contentHash
    , DB.param inp.name
    , DB.paramN inp.source
    , DB.paramN inp.harmonicRoot
    , DB.paramN inp.harmonicScale
    , DB.paramN inp.harmonicChord
    ]
  case DB.firstRow rows >>= DB.readField "id" of
    Nothing -> pure Nothing
    Just idS -> do
      case Int.fromString idS of
        Just i -> for_ inp.tags \t ->
          DB.run db "INSERT INTO label_tag (label_id, tag) VALUES (?, ?)"
            [ paramInt i, DB.param t ]
        Nothing -> pure unit
      pure (Just idS)

listLabels :: Database -> Maybe String -> Aff (Array Label)
listLabels db mHash = do
  rows <- case mHash of
    Just h -> DB.queryAllParams db
      (labelBase <> " WHERE content_hash = ? ORDER BY id") [ DB.param h ]
    Nothing -> DB.queryAll db (labelBase <> " ORDER BY id")
  ls <- traverse loadOne rows
  pure (catMaybes ls)
  where
  labelBase =
    "SELECT id, content_hash, name, source, harmonic_root, harmonic_scale, "
      <> "harmonic_chord, created_at FROM label"
  loadOne row = case DB.readField "id" row of
    Nothing -> pure Nothing
    Just idS -> do
      tags <- case Int.fromString idS of
        Just i -> do
          tagRows <- DB.queryAllParams db
            "SELECT tag FROM label_tag WHERE label_id = ?" [ paramInt i ]
          pure (mapMaybe (DB.readField "tag") tagRows)
        Nothing -> pure []
      pure (decodeLabel idS tags row)
  decodeLabel idS tags row = do
    contentHash <- DB.readField "content_hash" row
    name <- DB.readField "name" row
    pure
      { id: idS
      , contentHash
      , name
      , source: DB.readField "source" row
      , harmonicRoot: DB.readField "harmonic_root" row
      , harmonicScale: DB.readField "harmonic_scale" row
      , harmonicChord: DB.readField "harmonic_chord" row
      , tags
      , createdAt: DB.readField "created_at" row
      }

-- ============================================================
-- Morphisms — the derivation graph
-- ============================================================

addMorphism :: Database -> MorphismInput -> Aff Unit
addMorphism db m =
  DB.run db "INSERT INTO morphism (from_hash, to_hash, kind, params) VALUES (?, ?, ?, ?)"
    [ DB.param m.fromHash, DB.param m.toHash, DB.param m.kind, DB.paramN m.params ]

listMorphisms :: Database -> Maybe String -> Maybe String -> Aff (Array Morphism)
listMorphisms db mFrom mTo = do
  let
    whereParts = catMaybes
      [ mFrom $> "from_hash = ?"
      , mTo $> "to_hash = ?"
      ]
    prms = catMaybes
      [ DB.param <$> mFrom
      , DB.param <$> mTo
      ]
    sql = morphBase <>
      (if null whereParts then "" else " WHERE " <> joinWith " AND " whereParts)
  rows <- DB.queryAllParams db sql prms
  pure (mapMaybe decodeMorphism rows)
  where
  morphBase = "SELECT from_hash, to_hash, kind, params FROM morphism"
  decodeMorphism row = do
    fromHash <- DB.readField "from_hash" row
    toHash <- DB.readField "to_hash" row
    kind <- DB.readField "kind" row
    pure { fromHash, toHash, kind, params: DB.readField "params" row }

-- ============================================================
-- Favourites — curation
-- ============================================================

addFavorite :: Database -> Favorite -> Aff Unit
addFavorite db fav =
  DB.run db "INSERT INTO favorite (content_hash, collection) VALUES (?, ?)"
    [ DB.param fav.contentHash, DB.param fav.collection ]

listFavorites :: Database -> Maybe String -> Aff (Array Favorite)
listFavorites db mColl = do
  rows <- case mColl of
    Just c -> DB.queryAllParams db (favBase <> " WHERE collection = ?") [ DB.param c ]
    Nothing -> DB.queryAll db favBase
  pure (mapMaybe decodeFav rows)
  where
  favBase = "SELECT content_hash, collection FROM favorite"
  decodeFav row = do
    contentHash <- DB.readField "content_hash" row
    collection <- DB.readField "collection" row
    pure { contentHash, collection }

-- ============================================================
-- Helpers
-- ============================================================

paramInt :: Int -> Foreign
paramInt = unsafeToForeign
