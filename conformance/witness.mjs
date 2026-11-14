// witness.mjs: stands between a client and Amphora, and judges every request
// and every answer by the description (Amphora.Api).
//
// This is how a client in ANY language is held: run its real code with the
// witness as its store, and the witness says whether
//
//   1. each request is one some operation accepts (its method, path, query
//      and body, read strictly: no undeclared field), and
//   2. each answer is one that operation declares.
//
// Two ways to run it.
//
// Holding a client, in its tests. Starts a real Amphora on a database of its
// own, runs the command with AMPHORA_URL (and AMPHORA_BASE) naming the
// witness, and exits 0 only if the command did, nothing was judged wrong,
// and every operation named in --expect was asked at least once:
//
//   node conformance/witness.mjs --scratch --expect putContent,getContent -- go test ./internal/rig -run Wire
//
// Watching the rig. Stands in front of a store that is already running and
// reports until it is stopped (Ctrl-C), judging but never interfering:
//
//   node conformance/witness.mjs --upstream http://localhost:3024 --port 3924
//
// An OPTIONS request is passed through unjudged (a browser's preflight).

import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { join } from "node:path";
import { root, startScratchServer } from "./scratch-server.mjs";

const args = process.argv.slice(2);
const split = args.indexOf("--");
const own = split < 0 ? args : args.slice(0, split);
const command = split < 0 ? [] : args.slice(split + 1);
const option = (name) => {
  const at = own.indexOf(name);
  return at < 0 ? undefined : own[at + 1];
};
const expected = (option("--expect") ?? "").split(",").filter((name) => name !== "");

const { operations } = await import(join(root, "output/Amphora.Api/index.js"));
const { Tuple } = await import(join(root, "output/Data.Tuple/index.js"));
for (const name of expected) {
  if (!operations.some((operation) => operation.name === name)) throw new Error(`--expect names no operation: ${name}`);
}

let upstream = option("--upstream");
let stopUpstream = async () => {};
if (own.includes("--scratch")) {
  const scratch = await startScratchServer();
  upstream = scratch.base;
  stopUpstream = scratch.stop;
}
if (!upstream) throw new Error("say --scratch, or --upstream <url>");

const asked = new Map();
const wrong = [];

const read = (request) =>
  new Promise((resolve, reject) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });

const witness = createServer(async (request, response) => {
  const body = await read(request);
  const url = new URL(request.url, "http://witness");
  let answer;
  try {
    answer = await fetch(upstream + request.url, {
      method: request.method,
      headers: body === "" ? {} : { "Content-Type": request.headers["content-type"] ?? "application/json" },
      body: body === "" ? undefined : body,
    });
  } catch (error) {
    response.writeHead(502).end(String(error));
    wrong.push({ request: `${request.method} ${request.url}`, why: `the store did not answer: ${error}` });
    return;
  }
  const said = await answer.text();
  const headers = {};
  for (const name of ["content-type", "access-control-allow-origin", "access-control-allow-methods", "access-control-allow-headers"]) {
    if (answer.headers.has(name)) headers[name] = answer.headers.get(name);
  }
  response.writeHead(answer.status, headers).end(said);
  if (request.method === "OPTIONS") return;

  let path;
  try {
    path = url.pathname.split("/").slice(1).map(decodeURIComponent);
  } catch {
    path = url.pathname.split("/").slice(1);
  }
  const wire = { method: request.method, path, query: [...url.searchParams.entries()].map(([key, value]) => new Tuple(key, value)), body };
  const line = `${request.method} ${request.url}`;
  const operation = operations.find((candidate) => candidate.accepts(wire));
  if (!operation) {
    wrong.push({ request: line, body: body.slice(0, 300), why: `no operation accepts this request (the store answered ${answer.status})` });
    return;
  }
  asked.set(operation.name, (asked.get(operation.name) ?? 0) + 1);
  if (!operation.declares(answer.status)(said)) {
    wrong.push({ request: line, operation: operation.name, why: `${operation.name} does not declare this answer`, answer: `${answer.status} ${said.slice(0, 300)}` });
  }
});

const port = Number(option("--port") ?? 0);
await new Promise((resolve) => witness.listen(port, "127.0.0.1", resolve));
const here = `http://127.0.0.1:${witness.address().port}`;

const report = (commandFailed) => {
  const unasked = expected.filter((name) => !asked.has(name));
  for (const item of wrong) console.log("WRONG  " + JSON.stringify(item));
  for (const name of unasked) console.log(`UNASKED  ${name}: expected, and never asked`);
  const total = [...asked.values()].reduce((sum, count) => sum + count, 0);
  console.log(
    `witness: ${total} requests as ${[...asked.entries()].map(([name, count]) => `${name} ${count}`).join(", ") || "nothing"}; ` +
      `${wrong.length} wrong, ${unasked.length} unasked`
  );
  return commandFailed || wrong.length > 0 || unasked.length > 0 ? 1 : 0;
};

const finish = async (commandFailed) => {
  witness.close();
  await stopUpstream();
  process.exit(report(commandFailed));
};

if (command.length === 0) {
  console.log(`witness: ${here} in front of ${upstream}; Ctrl-C for the report`);
  process.on("SIGINT", () => finish(false));
  process.on("SIGTERM", () => finish(false));
} else {
  const child = spawn(command[0], command.slice(1), {
    stdio: "inherit",
    env: { ...process.env, AMPHORA_URL: here, AMPHORA_BASE: here },
  });
  child.on("exit", (code) => finish(code !== 0));
  child.on("error", (error) => {
    console.log(`witness: could not run ${command[0]}: ${error.message}`);
    finish(true);
  });
}
