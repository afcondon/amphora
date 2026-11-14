// client.mjs: the PureScript client against the REAL server.
//
// Starts the server on a database of its own and runs Test.Client, which
// asks typed operations through Hawser.Fetch and checks the typed answers.
// Exit 0 when every expectation holds.
//
//   node conformance/client.mjs           after `spago build`

import { join } from "node:path";
import { root, startScratchServer } from "./scratch-server.mjs";

const { run } = await import(join(root, "output/Test.Client/index.js"));
const { base, stop } = await startScratchServer();
let failures;
try {
  failures = await run(base)();
} finally {
  await stop();
}
for (const failure of failures) console.log("FAIL  " + failure);
console.log(`the PureScript client against amphora: ${failures.length} failures`);
process.exit(failures.length === 0 ? 0 : 1);
