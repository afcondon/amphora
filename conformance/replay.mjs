// replay.mjs: the scenario of conformance/vectors/amphora-api.json, against
// the REAL server.
//
// Starts `node run.js` on a free port with an empty database of its own (the
// live store on :3024 is never touched), sends every step in order, and
// checks three things about each answer:
//
//   1. the status is the one the scenario says;
//   2. the answer is one the operation DECLARES (asked of the compiled
//      description, Amphora.Api: a success is read strictly, a failure must
//      be one of the operation's own with a body of the declared shape);
//   3. the body contains what the scenario says, and has the count it says.
//
// Exit 0 when every step holds. A missing vector file is a failure.
//
//   node conformance/replay.mjs           after `spago build`

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { root, startScratchServer } from "./scratch-server.mjs";

const vectors = JSON.parse(readFileSync(join(root, "conformance/vectors/amphora-api.json"), "utf8"));
if (vectors["amphora-api-vectors"] !== 1) throw new Error("a vector format this replayer does not understand");
if (!Array.isArray(vectors.scenario) || vectors.scenario.length === 0) throw new Error("no scenario: nothing would be tested");

const { operations } = await import(join(root, "output/Amphora.Api/index.js"));
const declared = new Map(operations.map((operation) => [operation.name, operation]));

// Every key given must be there with that value; for an array, each element
// given must be contained in some element of the answer.
const contains = (actual, wanted) => {
  if (Array.isArray(wanted)) {
    if (!Array.isArray(actual)) return false;
    // Arrays of plain values (tags) are compared whole.
    if (wanted.every((item) => item === null || typeof item !== "object")) {
      return actual.length === wanted.length && wanted.every((item, at) => actual[at] === item);
    }
    return wanted.every((item) => actual.some((candidate) => contains(candidate, item)));
  }
  if (wanted !== null && typeof wanted === "object") {
    if (actual === null || typeof actual !== "object") return false;
    return Object.entries(wanted).every(([key, value]) => key in actual && contains(actual[key], value));
  }
  return actual === wanted;
};

const { base, stop } = await startScratchServer();

const failures = [];
try {
  for (const step of vectors.scenario) {
    const url =
      base + "/" + step.path.map(encodeURIComponent).join("/") +
      (step.query.length ? "?" + step.query.map(([key, value]) => encodeURIComponent(key) + "=" + encodeURIComponent(value)).join("&") : "");
    const answer = await fetch(url, {
      method: step.method,
      headers: step.bodyText === "" ? {} : { "Content-Type": "application/json" },
      body: step.bodyText === "" ? undefined : step.bodyText,
    });
    const body = await answer.text();
    const fail = (why) => failures.push(`${step.name}: ${why}\n    ${step.method} ${url}\n    answered ${answer.status} ${body.slice(0, 300)}`);

    if (answer.status !== step.status) {
      fail(`the scenario says ${step.status}`);
      continue;
    }
    if (step.operation !== "") {
      const operation = declared.get(step.operation);
      if (!operation) fail(`no operation is called ${step.operation}`);
      else if (!operation.declares(answer.status)(body)) fail(`${step.operation} does not declare this answer`);
    }
    if ("contains" in step || "count" in step) {
      let parsed;
      try {
        parsed = JSON.parse(body);
      } catch {
        fail("the body is not JSON");
        continue;
      }
      if ("contains" in step && !contains(parsed, step.contains)) fail(`the body does not contain ${JSON.stringify(step.contains)}`);
      if ("count" in step && !(Array.isArray(parsed) && parsed.length === step.count)) fail(`the scenario says ${step.count} elements`);
    }
  }
} finally {
  await stop();
}

for (const failure of failures) console.log("FAIL  " + failure);
console.log(`amphora against its description: ${vectors.scenario.length} steps, ${failures.length} failures`);
process.exit(failures.length === 0 ? 0 : 1);
