const fs = require("node:fs");
const vm = require("node:vm");

const effects = new Map();
const context = {
  process,
  require,
  rename_noreplace: "Fs.rename_noreplace",
  CID: (value) => value,
  io_eff: (identifier, operation) => effects.set(identifier, operation),
  io_fail: (code) => ({ error: code }),
  io_done: (value) => ({ value }),
};
vm.runInNewContext(fs.readFileSync(process.argv[2], "utf8"), context);
const operation = effects.get("Fs.rename_noreplace");
if (typeof operation !== "function") throw new Error("rename effect was not registered");
const result = operation("source", "destination");
if (result.error !== 95) throw new Error("missing Bun FFI must return raw ENOTSUP");
process.stdout.write("RENAME_NOREPLACE_JS_UNSUPPORTED_PASSED\n");
