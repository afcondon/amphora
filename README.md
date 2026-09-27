# Amphora ⚱

The **Atlantis artefact store** — a content-addressed DuckDB library the
browser editors (Triggerfish, Calypso, Vetula) read and write over HTTP. It
holds both the artefacts the rig *makes* (scenes, clips, patterns, configs)
and the reference data it *draws on* (the universe of scales). The BEAM rig
never touches it — this is an editor-side concern.

Design: [`docs/DESIGN.md`](docs/DESIGN.md). Marginalia project **#250**.

## The idea

Every stored object's identity is the **SHA-256 of its canonical payload**.
Save the same thing twice and it collapses to one node; content is immutable;
an "edit" is *new content + a re-pointed label*, git-style. Same content →
same id on every machine, so syncing between hosts is a conflict-free set-merge.

Three relations plus curation:

- **content** — immutable, content-addressed `(hash, kind, payload)`
- **label** — mutable metadata; one content, **many** labels (this is how one
  pitch-class set carries many scale names)
- **morphism** — the derivation graph `(from → to, kind)`
- **favorite** — curation, e.g. `scale-picker` populates the instrument pickers
- **ref** — a name that points at one content and can be moved (git's refs):
  compare-and-swap, so a writer who lost a race is told where the ref is now
  and can make its change again on top. Every move is logged and recorded as
  the morphism `ref:<name>`. Names are namespaced by app (`conspicillum/library`).

## Run

```bash
npm install          # duckdb node driver
spago build
node run.js          # listens on :3024 (AMPHORA_PORT / BACKEND_PORT override)
```

`AMPHORA_DB` overrides the DuckDB path (default `db/amphora.duckdb`).
The schema (`schema/init.sql`) is applied idempotently on every start.

## API

| Method | Path | Body / query | Returns |
|--------|------|--------------|---------|
| GET  | `/health` | | `ok` |
| POST | `/content` | `{kind, payload}` | `{hash, deduped}` |
| GET  | `/content?kind=…` | | `[{hash, kind, createdAt}]` |
| GET  | `/content/:hash` | | `{hash, kind, payload, createdAt}` |
| POST | `/labels` | `{contentHash, name, source?, harmonicRoot?, harmonicScale?, harmonicChord?, tags?}` | `{id}` |
| GET  | `/labels?hash=…` | | `[label]` |
| POST | `/morphisms` | `{from, to, kind, params?}` | `{ok}` |
| GET  | `/morphisms?from=…&to=…` | | `[morphism]` |
| POST | `/favorites` | `{contentHash, collection}` | `{ok}` |
| GET  | `/favorites?collection=…` | | `[favorite]` |
| DELETE | `/favorites?hash=…&collection=…` | | `{ok}` (unpublish; the content stays) |
| GET  | `/refs?prefix=…` | | `[{name, hash, movedAt}]` |
| GET  | `/refs/<name>` | | `{name, hash, movedAt}`, or 404 |
| POST | `/refs/<name>` | `{to, expected}` (`expected` null or absent: create) | `{name, hash, movedAt}`; **409** `{error, current}` if it had moved; 404 if `to` is not stored content |
| GET  | `/moves?ref=<name>` | | `[{name, from, to, movedAt}]`, oldest first |

`params` on a morphism is any JSON value, stored in canonical string form.

## Status

**P0 landed** — schema + content-addressed API + save→hash→dedup→recall proven
(content, labels, morphisms, favourites; persistence across restart). Next:
P0.5 Zeitler scale-universe seed + `scale-picker` curation (task #147); P1 the
editors migrate off `localStorage`; P2 the Hylograph morphism-graph browser.
Bosun-supervise in the Atlantis group once the editors depend on it.
