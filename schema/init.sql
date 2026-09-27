-- Amphora schema — the Atlantis artefact store.
--
-- Three relations plus curation, exactly as docs/DESIGN.md:
--   content  — immutable, content-addressed (hash = SHA-256 of the
--              canonical payload the client sends). Save-twice collapses.
--   label    — mutable human-facing metadata; one content, many labels
--              (this is how one pitch-class set carries many scale names).
--   morphism — the derivation graph; edges you navigate instead of folders.
--   favorite — curation, e.g. the `scale-picker` collection populates the
--              instrument pickers.
--   ref      — a name that points at one content and can be moved, git's
--              refs. Moves are compare-and-swap; each is logged in ref_move
--              (and recorded as a morphism `ref:<name>`), so a ref's history
--              is the ordered list of where it has pointed.
--
-- Idempotent: safe to run on every server start.

CREATE TABLE IF NOT EXISTS content (
  hash       TEXT PRIMARY KEY,
  kind       TEXT NOT NULL,
  payload    TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT now()
);

CREATE SEQUENCE IF NOT EXISTS seq_label_id START 1;

CREATE TABLE IF NOT EXISTS label (
  id             BIGINT PRIMARY KEY DEFAULT nextval('seq_label_id'),
  content_hash   TEXT NOT NULL,
  name           TEXT NOT NULL,
  source         TEXT,
  harmonic_root  TEXT,
  harmonic_scale TEXT,
  harmonic_chord TEXT,
  created_at     TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS label_tag (
  label_id BIGINT NOT NULL,
  tag      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS morphism (
  from_hash TEXT NOT NULL,
  to_hash   TEXT NOT NULL,
  kind      TEXT NOT NULL,
  params    TEXT
);

CREATE TABLE IF NOT EXISTS favorite (
  content_hash TEXT NOT NULL,
  collection   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS ref (
  name     TEXT PRIMARY KEY,
  hash     TEXT NOT NULL,
  moved_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ref_move (
  name      TEXT NOT NULL,
  from_hash TEXT,
  to_hash   TEXT NOT NULL,
  moved_at  TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_label_hash    ON label (content_hash);
CREATE INDEX IF NOT EXISTS idx_morphism_from ON morphism (from_hash);
CREATE INDEX IF NOT EXISTS idx_morphism_to   ON morphism (to_hash);
CREATE INDEX IF NOT EXISTS idx_favorite_coll ON favorite (collection);
CREATE INDEX IF NOT EXISTS idx_ref_move_name ON ref_move (name);
