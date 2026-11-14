# Amphora's HTTP API

Amphora is the Atlantis artefact store, on `:3024`. This is the declaration
of what it answers. The reference is `api/src/Amphora/Api.purs`: each
operation described once, with Hawser.

## The operations

<!-- generated:operations -->
| Operation | Request | Body | Answer | Failures | Meaning |
|---|---|---|---|---|---|
| `health` | `GET /health` |  | the text `ok` |  | Whether the store is up. |
| `putContent` | `POST /content` | content to save | saved | 400 the body is not content to save | Save content. The same payload twice is saved once. |
| `listContent` | `GET /content?kind=[…]` |  | array of content without its payload |  | Every piece of content, or every one of a kind, without payloads. |
| `getContent` | `GET /content/{hash}` |  | content | 404 no content has that hash | One piece of content, by its hash. |
| `addLabel` | `POST /labels` | label to add | the new label's identifier | 400 the body is not a label to add; 500 the label could not be written | Give content a name. Content may have many. |
| `listLabels` | `GET /labels?hash=[…]` |  | array of label |  | Every label, or every label of one piece of content. |
| `addMorphism` | `POST /morphisms` | morphism to add | `{"ok": true}` | 400 the body is not a morphism to add | Record that one piece of content was made from another. |
| `listMorphisms` | `GET /morphisms?from=[…]&to=[…]` |  | array of morphism |  | Morphisms, all or those from or to given content. |
| `addFavorite` | `POST /favorites` | favourite | `{"ok": true}` | 400 the body is not a favourite | Publish content in a collection. |
| `listFavorites` | `GET /favorites?collection=[…]` |  | array of favourite |  | What is published, in every collection or in one. |
| `removeFavorite` | `DELETE /favorites?hash=…&collection=…` |  | `{"ok": true}` | 400 the hash or the collection was not given | Take content out of a collection. The content and its labels stay. |
| `listRefs` | `GET /refs?prefix=[…]` |  | array of ref |  | Every ref, or every ref whose name starts with a prefix. |
| `getRef` | `GET /refs/{name}` |  | ref | 404 there is no such ref | Where a ref points. |
| `moveRef` | `POST /refs/{name}` | where to move the ref | ref | 400 the body does not say where to move the ref; 404 no content has the hash to move to; 409 the ref did not point where the writer expected | Point a ref at content, if it still points where the writer expects. |
| `listMoves` | `GET /moves?ref=…` |  | array of one move of a ref | 400 the ref was not given | Everywhere a ref has pointed, oldest first. |
<!-- /generated:operations -->

The table is generated from the description by `make vectors`. Do not edit
it here. `openapi.json` beside this file is generated from the same values,
for clients in other languages and for the standard tools.

## Rules that hold for every operation

- **Bodies and answers are JSON,** except `health`, which answers the text
  `ok`. A request with a body says `Content-Type: application/json`.
- **A query parameter given empty is a parameter not given.**
- **A failure answers `{"error": "…"}`,** a sentence for a person. One
  failure carries more: a stale `moveRef` also carries `current`, the ref
  as it now is, or null.
- **A path that is no operation's answers 404; an operation's path under a
  method it does not have answers 405.**
- **A ref's name may contain `/`.** It is the whole of the path after
  `/refs/`, and its `/` are written as they are, not percent-encoded.
  OpenAPI cannot say this; `openapi.json` says it in the parameter's
  description.
- **Content is immutable.** Its hash is the SHA-256 of its payload's text,
  as 64 hex digits. Saving the same payload twice saves it once.
- **CORS is open,** and `OPTIONS` on any path answers 200.

## What the description says that the server does not yet enforce

The server is older than the description and reads more loosely:

- it ignores fields in a body that the description does not declare, where
  the description refuses them;
- it reads `tags` that is not an array of strings as no tags.

The scenario sends nothing of that kind, so it holds against the server as
it is. Moving the server onto the description closes the gap.

## The vectors

`vectors/amphora-api.json` carries one **scenario**: every operation, in
order, against a store that starts empty. Each step is a request and what
it must answer:

| Field | Meaning |
|---|---|
| `operation` | The operation's name; empty for a request that is nobody's |
| `method`, `path`, `query` | The request. `path` is its segments and `query` its pairs, with nothing percent-encoded |
| `body` | The body as JSON, or null. `bodyText` is the same as text, for the few steps whose body is not JSON |
| `target` | The path and query as one percent-encoded string, for information |
| `status` | The status the answer must have |
| `contains` | What the answer's body must contain: every key given, with that value; for an array, each element given must be contained in some element of the answer |
| `count` | How many elements the answer's array must have |

An identifier or a time that the store makes up is never asserted.

## Who is held, and by what

| Program | Held by |
|---|---|
| The server (`src/Amphora/Main.purs`) | `make conformance`: `replay.mjs` starts the real server on a database of its own, sends every step, and checks each answer's status, that the operation declares it, and what it contains |
| The description itself | `make test`: every operation succeeds in some step, every declared failure is met in some step, and each step's request is one the description accepts or refuses as the step expects |

Clients are not yet held. See `docs/kb/plans/wire-declarations.md`, step 4.

## Conforming

A **client** in another language replays the steps that name the operations
it uses: given the values evident in a step, what it sends must have that
`method`, those `path` segments once decoded, those `query` pairs and that
`body` as JSON; and it must read an answer of the shape `openapi.json`
gives for that operation.

The file carries `"amphora-api-vectors": 1`. A replayer asserts the number
it understands. Not finding the file is a failure, not a skip.

## Changing this

Change this document, then `api/test/Test/Scenario.purs`, whose steps are
written by hand, then the description until `make test` passes, then
`make vectors`, then `make conformance`.
