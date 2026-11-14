// Writes the generated table into AMPHORA-API.md from the description in
// api/src/Amphora/Api.purs (`write`), or fails if the document's table is
// not what the description gives (`check`).
//
// Run through `make vectors` and `make check-vectors`, after `spago build`.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const here = (path) => fileURLToPath(new URL(path, import.meta.url));
const { table } = await import(here("../output/Test.Generate/index.js"));

const path = here("AMPHORA-API.md");
const before = readFileSync(path, "utf8");
const open = "<!-- generated:operations -->";
const close = "<!-- /generated:operations -->";
const from = before.indexOf(open);
const to = before.indexOf(close);
if (from < 0 || to < from) throw new Error("AMPHORA-API.md has no operations markers");
const after = before.slice(0, from + open.length) + "\n" + table + "\n" + before.slice(to);
if (process.argv[2] === "write") writeFileSync(path, after);
else if (before !== after) {
  console.log("FAIL  conformance/AMPHORA-API.md's table is not what the description gives; run `make vectors`");
  process.exit(1);
} else console.log("declaration: the table is current");
