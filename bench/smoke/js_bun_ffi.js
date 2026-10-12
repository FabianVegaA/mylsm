const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");

const effects = new Map();
const context = {
  Buffer,
  process,
  require,
  Unit: {},
  DbLock: { try_lock: "DbLock.try_lock", try_unlock: "DbLock.try_unlock" },
  rename_noreplace: "Fs.rename_noreplace",
  CID: (value) => value,
  io_eff: (identifier, operation) => effects.set(identifier, operation),
  io_fail: (code) => ({ error: code }),
  io_done: (value) => ({ value }),
  io_tup: (file, result) => ({ file, result }),
};

for (const source of [
  "src/effs/db_lock.js",
  "src/effs/db_unlock.js",
  "src/effs/rename_noreplace.js",
]) {
  vm.runInNewContext(fs.readFileSync(source, "utf8"), context);
}

const directory = fs.mkdtempSync(path.join(os.tmpdir(), "mylsm-bun-ffi-"));
try {
  const lockPath = path.join(directory, "LOCK");
  fs.closeSync(fs.openSync(lockPath, "a"));
  const descriptor = fs.openSync(lockPath, "a");
  const locked = effects.get("DbLock.try_lock")(descriptor);
  if (locked.file !== descriptor || locked.result.value === undefined) {
    throw new Error("Bun flock effect did not acquire the file descriptor");
  }
  const unlocked = effects.get("DbLock.try_unlock")(descriptor);
  if (unlocked.file !== descriptor || unlocked.result.value === undefined) {
    throw new Error("Bun flock effect did not release the file descriptor");
  }
  fs.closeSync(descriptor);

  const source = path.join(directory, "source");
  const destination = path.join(directory, "destination");
  fs.writeFileSync(source, "payload");
  const renamed = effects.get("Fs.rename_noreplace")(source, destination);
  if (renamed.value === undefined || fs.readFileSync(destination, "utf8") !== "payload") {
    throw new Error("Bun no-replace rename did not publish the source");
  }

  const collisionSource = path.join(directory, "collision-source");
  fs.writeFileSync(collisionSource, "preserved");
  const collision = effects.get("Fs.rename_noreplace")(collisionSource, destination);
  if (collision.error !== 17 || fs.readFileSync(collisionSource, "utf8") !== "preserved") {
    throw new Error("Bun no-replace rename did not preserve a colliding source");
  }
  process.stdout.write("BUN_FFI_LOCK_RENAME_PASSED\n");
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
