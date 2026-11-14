-- | Amphora's HTTP API, described once: fifteen operations on :3024.
-- |
-- | This is the declaration. The server, the PureScript clients, the
-- | document (`conformance/AMPHORA-API.md`), the OpenAPI file
-- | (`conformance/openapi.json`) and the vectors that hold the clients in
-- | other languages (`conformance/vectors/amphora-api.json`) all come from
-- | the values below, or are held to them.
-- |
-- | A request is a record. Its fields may travel in the path, the query or
-- | the body; the description says which.
module Amphora.Api
  ( Content
  , ContentInput
  , ContentMeta
  , Saved
  , Label
  , LabelInput
  , Morphism
  , MorphismInput
  , Favorite
  , Ref
  , Move
  , RefMove
  , Problem
  , Stale
  , Done
  , health
  , putContent
  , listContent
  , getContent
  , addLabel
  , listLabels
  , addMorphism
  , listMorphisms
  , addFavorite
  , listFavorites
  , removeFavorite
  , listRefs
  , getRef
  , moveRef
  , listMoves
  , operations
  , problem
  , stale
  ) where

import Prelude

import Data.Argonaut.Core (Json)
import Data.Maybe (Maybe)
import Hawser.Http (Endpoint, Method(..), Operation, body, capture, endpoint, failure, json, literal, operation, optionalParam, param, rest, text)
import Hawser.Message (field, optional, recordOf)
import Hawser.Value (Value, anyJson, arrayOf, boolean, named, nullable, string)

-- ── What the fields hold ───────────────────────────────────────────────────

-- | The SHA-256 of a payload, as 64 hex digits. It is the content's name.
hash :: Value String
hash = named "hash" string

-- | A time as the database gives it, or null where it has none.
moment :: Value (Maybe String)
moment = named "time or null" (nullable string)

-- ── Content ────────────────────────────────────────────────────────────────

type ContentInput = { kind :: String, payload :: String }

contentInput :: Value ContentInput
contentInput = recordOf "content to save" $
  { kind: _, payload: _ }
    <$> field "kind" _.kind string "what sort of thing the payload is, such as `odonus-scene`"
    <*> field "payload" _.payload string "the thing itself, as text; its hash is its name"

type Saved = { hash :: String, deduped :: Boolean }

saved :: Value Saved
saved = recordOf "saved" $
  { hash: _, deduped: _ }
    <$> field "hash" _.hash hash "the content's hash"
    <*> field "deduped" _.deduped boolean "true if that content was already there, so nothing was written"

type Content = { hash :: String, kind :: String, payload :: String, createdAt :: Maybe String }

content :: Value Content
content = recordOf "content" $
  { hash: _, kind: _, payload: _, createdAt: _ }
    <$> field "hash" _.hash hash "its hash"
    <*> field "kind" _.kind string "what sort of thing it is"
    <*> field "payload" _.payload string "the thing itself"
    <*> field "createdAt" _.createdAt moment "when it was first saved"

type ContentMeta = { hash :: String, kind :: String, createdAt :: Maybe String }

contentMeta :: Value ContentMeta
contentMeta = recordOf "content without its payload" $
  { hash: _, kind: _, createdAt: _ }
    <$> field "hash" _.hash hash "its hash"
    <*> field "kind" _.kind string "what sort of thing it is"
    <*> field "createdAt" _.createdAt moment "when it was first saved"

-- ── Labels ─────────────────────────────────────────────────────────────────

type LabelInput =
  { contentHash :: String
  , name :: String
  , source :: Maybe String
  , harmonicRoot :: Maybe String
  , harmonicScale :: Maybe String
  , harmonicChord :: Maybe String
  , tags :: Maybe (Array String)
  }

labelInput :: Value LabelInput
labelInput = recordOf "label to add" $
  { contentHash: _, name: _, source: _, harmonicRoot: _, harmonicScale: _, harmonicChord: _, tags: _ }
    <$> field "contentHash" _.contentHash hash "the content it names"
    <*> field "name" _.name string "the name"
    <*> optional "source" _.source string "where the name came from, such as `user` or `convention`"
    <*> optional "harmonicRoot" _.harmonicRoot string "a root, where the content has one"
    <*> optional "harmonicScale" _.harmonicScale string "a scale"
    <*> optional "harmonicChord" _.harmonicChord string "a chord"
    <*> optional "tags" _.tags (arrayOf string) "tags; none if left out"

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

label :: Value Label
label = recordOf "label" $
  { id: _, contentHash: _, name: _, source: _, harmonicRoot: _, harmonicScale: _, harmonicChord: _, tags: _, createdAt: _ }
    <$> field "id" _.id string "the label's own identifier"
    <*> field "contentHash" _.contentHash hash "the content it names"
    <*> field "name" _.name string "the name"
    <*> field "source" _.source (nullable string) "where the name came from"
    <*> field "harmonicRoot" _.harmonicRoot (nullable string) "a root"
    <*> field "harmonicScale" _.harmonicScale (nullable string) "a scale"
    <*> field "harmonicChord" _.harmonicChord (nullable string) "a chord"
    <*> field "tags" _.tags (arrayOf string) "tags"
    <*> field "createdAt" _.createdAt moment "when it was added"

type Identified = { id :: String }

identified :: Value Identified
identified = recordOf "the new label's identifier" $
  { id: _ } <$> field "id" _.id string "the label's identifier"

-- ── Morphisms ──────────────────────────────────────────────────────────────

type MorphismInput = { from :: String, to :: String, kind :: String, params :: Maybe Json }

morphismInput :: Value MorphismInput
morphismInput = recordOf "morphism to add" $
  { from: _, to: _, kind: _, params: _ }
    <$> field "from" _.from hash "the content it starts from"
    <*> field "to" _.to hash "the content it arrives at"
    <*> field "kind" _.kind string "what sort of step it is"
    <*> optional "params" _.params anyJson "the step's parameters, as any JSON; kept as text"

type Morphism = { from :: String, to :: String, kind :: String, params :: Maybe String }

morphism :: Value Morphism
morphism = recordOf "morphism" $
  { from: _, to: _, kind: _, params: _ }
    <$> field "from" _.from hash "the content it starts from"
    <*> field "to" _.to hash "the content it arrives at"
    <*> field "kind" _.kind string "what sort of step it is"
    <*> field "params" _.params (nullable string) "its parameters, as the text of the JSON given"

-- ── Favourites ─────────────────────────────────────────────────────────────

type Favorite = { contentHash :: String, collection :: String }

favorite :: Value Favorite
favorite = recordOf "favourite" $
  { contentHash: _, collection: _ }
    <$> field "contentHash" _.contentHash hash "the content"
    <*> field "collection" _.collection string "the collection it is published in, such as `odonus-scenes`"

-- ── Refs ───────────────────────────────────────────────────────────────────

type Ref = { name :: String, hash :: String, movedAt :: Maybe String }

ref :: Value Ref
ref = recordOf "ref" $
  { name: _, hash: _, movedAt: _ }
    <$> field "name" _.name string "the ref's name, which may contain `/`"
    <*> field "hash" _.hash hash "the content it points at"
    <*> field "movedAt" _.movedAt moment "when it last moved"

type Move = { name :: String, to :: String, expected :: Maybe String }

type MoveBody = { to :: String, expected :: Maybe String }

moveBody :: Value MoveBody
moveBody = recordOf "where to move the ref" $
  { to: _, expected: _ }
    <$> field "to" _.to hash "the content it should point at"
    <*> optional "expected" _.expected hash "the content the writer believes it points at now; left out to create it"

type RefMove = { name :: String, from :: Maybe String, to :: String, movedAt :: Maybe String }

refMove :: Value RefMove
refMove = recordOf "one move of a ref" $
  { name: _, from: _, to: _, movedAt: _ }
    <$> field "name" _.name string "the ref"
    <*> field "from" _.from (nullable hash) "where it pointed before; null when it was created"
    <*> field "to" _.to hash "where it pointed after"
    <*> field "movedAt" _.movedAt moment "when"

-- ── Answers that carry no data, and answers that are not success ───────────

type Done = { ok :: Boolean }

done :: Value Done
done = recordOf "`{\"ok\": true}`" $
  { ok: _ } <$> field "ok" _.ok boolean "true"

type Problem = { error :: String }

-- | What every failure carries: a sentence for a person.
problem :: Value Problem
problem = recordOf "a problem" $
  { error: _ } <$> field "error" _.error string "what was wrong, for a person"

type Stale = { error :: String, current :: Maybe Ref }

-- | A ref that had moved: the sentence, and the ref as it now is.
stale :: Value Stale
stale = recordOf "a stale move" $
  { error: _, current: _ }
    <$> field "error" _.error string "what was wrong, for a person"
    <*> field "current" _.current (nullable ref) "the ref as it is now; null if it does not exist"

-- ── The operations ─────────────────────────────────────────────────────────

health :: Endpoint {} Unit
health = endpoint "health" "Whether the store is up." Get
  ({} <$ literal "health")
  (text "ok")
  []

putContent :: Endpoint ContentInput Saved
putContent = endpoint "putContent" "Save content. The same payload twice is saved once." Post
  (literal "content" *> body identity contentInput)
  (json saved)
  [ failure 400 "the body is not content to save" problem ]

listContent :: Endpoint { kind :: Maybe String } (Array ContentMeta)
listContent = endpoint "listContent" "Every piece of content, or every one of a kind, without payloads." Get
  ({ kind: _ } <$> (literal "content" *> optionalParam "kind" _.kind "only content of this kind"))
  (json (arrayOf contentMeta))
  []

getContent :: Endpoint { hash :: String } Content
getContent = endpoint "getContent" "One piece of content, by its hash." Get
  ({ hash: _ } <$> (literal "content" *> capture "hash" _.hash "the content's hash"))
  (json content)
  [ failure 404 "no content has that hash" problem ]

addLabel :: Endpoint LabelInput Identified
addLabel = endpoint "addLabel" "Give content a name. Content may have many." Post
  (literal "labels" *> body identity labelInput)
  (json identified)
  [ failure 400 "the body is not a label to add" problem
  , failure 500 "the label could not be written" problem
  ]

listLabels :: Endpoint { hash :: Maybe String } (Array Label)
listLabels = endpoint "listLabels" "Every label, or every label of one piece of content." Get
  ({ hash: _ } <$> (literal "labels" *> optionalParam "hash" _.hash "only labels of this content"))
  (json (arrayOf label))
  []

addMorphism :: Endpoint MorphismInput Done
addMorphism = endpoint "addMorphism" "Record that one piece of content was made from another." Post
  (literal "morphisms" *> body identity morphismInput)
  (json done)
  [ failure 400 "the body is not a morphism to add" problem ]

listMorphisms :: Endpoint { from :: Maybe String, to :: Maybe String } (Array Morphism)
listMorphisms = endpoint "listMorphisms" "Morphisms, all or those from or to given content." Get
  ( { from: _, to: _ }
      <$> (literal "morphisms" *> optionalParam "from" _.from "only those starting here")
      <*> optionalParam "to" _.to "only those arriving here"
  )
  (json (arrayOf morphism))
  []

addFavorite :: Endpoint Favorite Done
addFavorite = endpoint "addFavorite" "Publish content in a collection." Post
  (literal "favorites" *> body identity favorite)
  (json done)
  [ failure 400 "the body is not a favourite" problem ]

listFavorites :: Endpoint { collection :: Maybe String } (Array Favorite)
listFavorites = endpoint "listFavorites" "What is published, in every collection or in one." Get
  ({ collection: _ } <$> (literal "favorites" *> optionalParam "collection" _.collection "only this collection"))
  (json (arrayOf favorite))
  []

removeFavorite :: Endpoint { hash :: String, collection :: String } Done
removeFavorite = endpoint "removeFavorite" "Take content out of a collection. The content and its labels stay." Delete
  ( { hash: _, collection: _ }
      <$> (literal "favorites" *> param "hash" _.hash "the content")
      <*> param "collection" _.collection "the collection"
  )
  (json done)
  [ failure 400 "the hash or the collection was not given" problem ]

listRefs :: Endpoint { prefix :: Maybe String } (Array Ref)
listRefs = endpoint "listRefs" "Every ref, or every ref whose name starts with a prefix." Get
  ({ prefix: _ } <$> (literal "refs" *> optionalParam "prefix" _.prefix "only refs whose names start so"))
  (json (arrayOf ref))
  []

getRef :: Endpoint { name :: String } Ref
getRef = endpoint "getRef" "Where a ref points." Get
  ({ name: _ } <$> (literal "refs" *> rest "name" _.name "the ref's name"))
  (json ref)
  [ failure 404 "there is no such ref" problem ]

moveRef :: Endpoint Move Ref
moveRef = endpoint "moveRef" "Point a ref at content, if it still points where the writer expects." Post
  ( (\name moved -> { name, to: moved.to, expected: moved.expected })
      <$> (literal "refs" *> rest "name" _.name "the ref's name")
      <*> body (\move -> { to: move.to, expected: move.expected }) moveBody
  )
  (json ref)
  [ failure 400 "the body does not say where to move the ref" problem
  , failure 404 "no content has the hash to move to" problem
  , failure 409 "the ref did not point where the writer expected" stale
  ]

listMoves :: Endpoint { ref :: String } (Array RefMove)
listMoves = endpoint "listMoves" "Everywhere a ref has pointed, oldest first." Get
  ({ ref: _ } <$> (literal "moves" *> param "ref" _.ref "the ref's name"))
  (json (arrayOf refMove))
  [ failure 400 "the ref was not given" problem ]

-- | Every operation, as plain data, in the order of the document.
operations :: Array Operation
operations =
  [ operation health
  , operation putContent
  , operation listContent
  , operation getContent
  , operation addLabel
  , operation listLabels
  , operation addMorphism
  , operation listMorphisms
  , operation addFavorite
  , operation listFavorites
  , operation removeFavorite
  , operation listRefs
  , operation getRef
  , operation moveRef
  , operation listMoves
  ]
