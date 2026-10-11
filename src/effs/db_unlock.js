let db_unlock_sys;

function db_unlock_run(file) {
  try {
    if (db_unlock_sys === undefined) {
      const ffi = require("bun:ffi");
      const mac = process.platform === "darwin";
      const errno = mac ? "__error" : "__errno_location";
      const lib = ffi.dlopen(mac ? "libSystem.dylib" : "libc.so.6", {
        flock: { args: ["i32", "i32"], returns: "i32" },
        [errno]: { args: [], returns: "ptr" },
      });
      db_unlock_sys = { ...lib.symbols, errno: lib.symbols[errno], read: ffi.read };
    }
    const result = db_unlock_sys.flock(file, 8);
    const value = result === 0
      ? io_done({ $: CID(Unit) })
      : io_fail(Math.abs(db_unlock_sys.read.i32(db_unlock_sys.errno(), 0)));
    return io_tup(file, value);
  } catch (e) {
    return io_tup(file, io_fail(Math.abs(e.errno ?? 95)));
  }
}

io_eff(CID(DbLock.try_unlock), db_unlock_run);
