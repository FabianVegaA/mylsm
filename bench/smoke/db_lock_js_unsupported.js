const fs = require("node:fs");
const vm = require("node:vm");

for (const [path, name] of [
  [process.argv[2], "DbLock.try_lock"],
  [process.argv[3], "DbLock.try_unlock"],
]) {
  const effects = new Map();
  const context = {
    Buffer,
    process,
    require,
    DbLock: { try_lock: "DbLock.try_lock", try_unlock: "DbLock.try_unlock" },
    CID: (value) => value,
    io_eff: (identifier, operation) => effects.set(identifier, operation),
    io_fail: (code) => ({ error: code }),
    io_tup: (file, result) => ({ file, result }),
    io_done: (value) => ({ value }),
  };
  vm.runInNewContext(fs.readFileSync(path, "utf8"), context);
  const operation = effects.get(name);
  if (typeof operation !== "function") throw new Error(`${name} was not registered`);
  const result = operation(7);
  if (result.file !== 7 || result.result.error !== 95) {
    throw new Error(`${name} must return raw ENOTSUP when Bun FFI is unavailable`);
  }
}
process.stdout.write("DB_LOCK_JS_UNSUPPORTED_PASSED\n");
