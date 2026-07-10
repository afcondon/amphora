import * as crypto from "node:crypto";

export const sha256Hex = (input) => () =>
  crypto.createHash("sha256").update(input, "utf8").digest("hex");
