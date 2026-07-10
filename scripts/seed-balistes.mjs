// Seed Amphora with the Balistes genre-starter patterns.
//
// Single source of truth: the typed patterns live in Triggerfish
// (Triggerfish.Balistes.Pattern). We import the compiled output and use
// Balistes' own Lepidoptera printer to serialise each into its canonical,
// hashable form, then POST to the store. Content-addressing makes re-runs
// idempotent for content; we guard labels/favourites by name/hash.
//
// Prereq: Triggerfish must be built (`spago build` there) so output/ exists,
// and Amphora must be running (default http://localhost:3024, or AMPHORA_BASE).
//
//   node scripts/seed-balistes.mjs

import { genreStarters, houseLoTempo110 } from "../../triggerfish/output/Triggerfish.Balistes.Pattern/index.js";
import { printPattern } from "../../triggerfish/output/Triggerfish.Balistes.Lepidoptera/index.js";

const BASE = process.env.AMPHORA_BASE || "http://localhost:3024";
const COLLECTION = "balistes-grid";
const KIND = "balistes-pattern";

const j = (method, path, body) =>
  fetch(BASE + path, {
    method,
    headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }).then(async (r) => {
    if (!r.ok) throw new Error(`${method} ${path} → HTTP ${r.status}: ${await r.text()}`);
    return r.json();
  });

// "house 122" → { genre: "house", bpm: 122 }.  Tempo is the trailing integer.
const parseName = (name) => {
  const m = name.match(/^(.*?)\s+(\d+)\s*$/);
  return m ? { genre: m[1].trim(), bpm: Number(m[2]) } : { genre: name, bpm: null };
};

async function seedOne(pat) {
  const payload = printPattern(pat);
  const { hash, deduped } = await j("POST", "/content", { kind: KIND, payload });

  const { genre, bpm } = parseName(pat.name);
  const tags = [genre];
  if (bpm != null) tags.push("bpm:" + bpm);

  // Guard the label: skip if this hash already carries a label with this name.
  const labels = await j("GET", `/labels?hash=${hash}`);
  const hasLabel = labels.some((l) => l.name === pat.name);
  if (!hasLabel) {
    await j("POST", "/labels", { contentHash: hash, name: pat.name, source: "convention", tags });
  }

  // Guard the favourite: skip if already in the collection.
  const favs = await j("GET", `/favorites?collection=${COLLECTION}`);
  const faved = favs.some((f) => f.contentHash === hash);
  if (!faved) {
    await j("POST", "/favorites", { contentHash: hash, collection: COLLECTION });
  }

  return { name: pat.name, hash, deduped, labelled: !hasLabel, faved: !faved };
}

async function main() {
  const patterns = [houseLoTempo110, ...genreStarters];
  console.log(`Seeding ${patterns.length} Balistes patterns → ${BASE} (${COLLECTION})`);
  for (const pat of patterns) {
    try {
      const r = await seedOne(pat);
      console.log(
        `  ${r.name.padEnd(18)} ${r.hash.slice(0, 12)}…  ` +
          `${r.deduped ? "dedup" : "new  "}  ${r.labelled ? "+label" : "     "} ${r.faved ? "+fav" : ""}`
      );
    } catch (e) {
      console.error(`  ✗ ${pat.name}: ${e.message}`);
    }
  }
  console.log("done.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
