// A real Amphora server on a free port, with an empty database of its own.
// The live store on :3024 is never touched. For the replays in this folder.

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const root = join(dirname(fileURLToPath(import.meta.url)), "..");

const freePort = () =>
  new Promise((resolve, reject) => {
    const probe = createServer();
    probe.once("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });

// Starts the server and waits until it answers. Gives its base URL and
// what stops it and removes its database.
export const startScratchServer = async () => {
  const port = await freePort();
  const scratch = mkdtempSync(join(tmpdir(), "amphora-conformance-"));
  const server = spawn("node", ["run.js"], {
    cwd: root,
    env: { ...process.env, AMPHORA_PORT: String(port), AMPHORA_DB: join(scratch, "store.duckdb") },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let said = "";
  server.stdout.on("data", (chunk) => (said += chunk));
  server.stderr.on("data", (chunk) => (said += chunk));
  const base = `http://127.0.0.1:${port}`;
  const stop = async () => {
    server.kill("SIGTERM");
    await new Promise((resolve) => server.once("exit", resolve));
    rmSync(scratch, { recursive: true, force: true });
  };
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      if ((await fetch(base + "/health")).ok) return { base, stop };
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  await stop();
  throw new Error("the server did not come up:\n" + said);
};
