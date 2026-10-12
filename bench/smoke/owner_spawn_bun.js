const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");

const effects = new Map();
const context = {
  Bun,
  CID: (name) => typeof name === "function" ? name.name : name,
  Con: "Con",
  DbLock: { try_lock: "DbLock.try_lock", try_unlock: "DbLock.try_unlock" },
  owner_spawn: "owner_spawn",
  Unit: {},
  io_eff: (name, operation) => effects.set(name, operation),
  io_done: (value) => ({ value }),
  io_fail: (code) => ({ error: code }),
  io_tup: (file, result) => ({ file, result }),
  process,
  require,
};
for (const source of [
  "src/effs/db_lock.js",
  "src/effs/db_unlock.js",
  "src/effs/owner_spawn.js",
]) {
  vm.runInNewContext(fs.readFileSync(source, "utf8"), context);
}

const asBendList = (values) => values.reduceRight(
  (tail, head) => ({ $: "Con", head, tail }), { $: "Nil" });

async function main() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "mylsm-bun-spawn-"));
  const lockPath = path.join(directory, "LOCK");
  const markerPath = path.join(directory, "descriptor-state");
  const descriptor = fs.openSync(lockPath, "a");
  try {
    const locked = effects.get("DbLock.try_lock")(descriptor);
    if (locked.result.error !== undefined) {
      throw new Error("Bun flock effect did not acquire the database lock");
    }

    const child = path.resolve("bench/smoke/owner_spawn_fd_probe.js");
    const argv = asBendList([process.execPath, child, markerPath,
      String(descriptor)]);
    const spawned = effects.get("owner_spawn")(argv);
    if (!Number.isInteger(spawned.value) || spawned.value <= 0) {
      throw new Error("Bun owner spawn did not return a child process ID");
    }

    for (let attempt = 0; attempt < 200 && !fs.existsSync(markerPath); attempt++) {
      await Bun.sleep(10);
    }
    if (fs.readFileSync(markerPath, "utf8") !== "closed") {
      throw new Error("Bun owner child inherited the database lock descriptor");
    }

    const unlocked = effects.get("DbLock.try_unlock")(descriptor);
    if (unlocked.result.error !== undefined) {
      throw new Error("Bun flock effect did not release the database lock");
    }
    process.stdout.write("OWNER_SPAWN_BUN_PASSED\n");
  } finally {
    fs.closeSync(descriptor);
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack}\n`);
  process.exitCode = 1;
});
