# Amphora — the Atlantis artefact store

> Amphorae are the sealed vessels you recover from a wreck. This one holds
> everything the live-coding rig makes and everything it draws on — content-
> addressed, deduplicated, findable, and shared across machines.

Amphora is the persistent backend for the **Atlantis** live-coding system: a
principled, content-addressed store that the browser editors (Triggerfish,
Calypso, Vetula) read and write over HTTP. It replaces the scattered, ephemeral
state of today — Odonus scenes in `localStorage`, clips in-session, the logbook
gone on reload — with one addressable source of truth. The BEAM rig stays out of
the DB path; this is an editor-side concern.

## Two things it holds

1. **Artefacts** — what the rig *makes and plays*: Odonus scenes, clips,
   recordings, Tidal patterns, Vetula paths, and the sibling machines'
   configs (Balistes / Stellatus / Sufflamen / Selene).
2. **Reference** — what the rig *draws on*: the universe of scales (every
   scale + its modes + names, seeded from Zeitler's *Exciting Universe of
   Music Theory* catalogue), from which the user curates favourites that
   populate the scale pickers across the instruments (task #147).

Both are the same kind of thing under the hood — see below.

## The keystone: content-addressing

**Every stored object's identity is the hash of its canonical payload.** Save
the same scene twice and it collapses to one node; dedup is free and structural,
not a scan-on-save. This requires a *canonical form* to hash — which we already
have where it counts: Lepidoptera's print/parse round-trip is byte-stable, so the
printed patch hashes deterministically.

Content-addressing makes content **immutable**. "Editing a scene" is *new
content + re-point its label* — git-style. History is retained for free and every
version stays findable.

It is also what earns **"shared, distributed."** Same content → same id on every
machine, so syncing Amphora between the MBP and the Mac Mini is a set-merge with
no conflicts — a semilattice, the same algebra as Bosun's reconcile. Distribution
becomes a merge, not a sync-conflict problem.

## Data model

Three relations:

- **content** *(immutable, content-addressed)*
  `hash (PK) · kind · payload · created_at`
  — scenes, clips, recordings, patterns, paths, machine configs, **and scales**.
  `payload` is the canonical bytes/JSON that were hashed.

- **label** *(mutable metadata on content)*
  `id (PK) · content_hash (FK) · name · source · harmonic_root · harmonic_scale ·
  harmonic_chord · created_at`  + `label_tag(label_id, tag)`
  — the human-facing view. One content can carry **many** labels (see scales).

- **morphism** *(the graph)*
  `from_hash · to_hash · kind · params(JSON)`
  — `promoted · rendered · transcribed · conducted · exported · derived_from …`.
  Reproducible derivations; the edges you navigate instead of a folder tree.

Plus **curation**: `favorite(content_hash, collection)` — e.g.
`collection = 'scale-picker'` is the set of scales that populate the pickers.

### Recipe vs rendering

Most content is a tiny **recipe** (Lepidoptera text, a seed, a path, a pattern).
Because the engine is deterministic (the lockstep property), a **clip** is a
*cache* of `f(recipe, seed, harmony, span)` — storable, but regenerable. The
exception is a **recording** of external/human play (a guitar take over a
section), which isn't recipe-derivable and is stored as a primary rendering. The
`kind`/provenance carries this distinction; the `derived_from` morphism ties a
cached rendering back to the recipe that produced it.

### Scales are just content too

A scale = its normalized pitch-class/interval set = a hash. Names are **labels**
on that hash. So the pentatonic that is **Tizita** in the Ethiopian qenet system
and something else in another tradition is **one content node with several name
labels** — content-addressing collapses the set and preserves every cultural name
as an annotation. This same-set/many-names structure is precisely why a DB beats
a hardcoded scale list.

- **Seed**: import Zeitler's full ~2048-scale catalogue with his names.
- **Augment**: add qenet names (Tizita, Bati, Ambassel, Anchihoye), maqam, and
  the user's own — as additional labels on existing hashes.
- **Curate**: the user favourites the hashes they want; the pickers read the
  `scale-picker` collection.
- **Operations** stay in **harmonia** (realize / quantise); Amphora owns the
  *catalogue + curation*, harmonia owns the *maths*.

## Stack & deployment

- **DuckDB** — ecosystem-consistent (Marginalia, CodeExplorer), JSON payloads,
  analytical queries over the library ("all D-dorian clips, last month").
- **PureScript-typed schema** + an **HTTPurple / Node HTTP API** (same lineage as
  Marginalia's API and Calypso's server). Port **3024** (adjacent to Triggerfish's
  3023 in the Atlantis cluster).
- **Bosun-supervised** in the **Atlantis** group — and notably the first
  *stateful/data* member of that group, so it's a real test of Bosun supervising a
  service with a database behind it (readiness, drain-on-signal, artifact-not-
  build-wrapper).
- Editors get a small typed client; **`localStorage` is retired** as a store of
  record (one source of truth, and it's the addressable one).

## The browser: the library IS the morphism graph

The library browser is not a list — it's the morphism graph rendered in
Hylograph: a force-directed field of artefacts and the transformations between
them. Recall becomes *following an edge*, not scrolling folders. This is the
"frontispiece" idea, load-bearing rather than decorative, and squarely on the
Hylograph-control-surfaces direction.

## Phasing

- **P0** — schema + content-addressed API + one client: migrate Odonus
  scenes/clips off `localStorage`; prove save → hash → dedup → recall.
- **P0.5** — seed the scale universe (Zeitler import) + the `scale-picker`
  curation + wire the pickers to read favourites (task #147).
- **P1** — the other editors (Calypso, Vetula, the sibling machines) read/write.
- **P2** — the Hylograph morphism-graph browser.

## Deferred / open

- Cross-machine sync (the merge is trivial by construction; the transport isn't
  built) — a natural fit for the Bosun-federation direction.
- `.mid` export as a morphism target.
- Whether recordings store raw events or a compressed/columnar form in DuckDB.
- Retention/GC for cached renderings (recipes are cheap to keep; clips can be
  re-rendered, so they're evictable).
