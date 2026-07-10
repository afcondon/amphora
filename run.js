// Runner for the Amphora backend.
// Launched from the amphora repo root, so cwd-relative paths
// (schema/init.sql, db/amphora.duckdb) resolve correctly.

import { main } from "./output/Amphora.Main/index.js";

main();
