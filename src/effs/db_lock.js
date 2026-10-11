let db_lock_sys;

function db_lock_run(file) {
  try {
    if (db_lock_sys === undefined) {
      const ffi = require("bun:ffi");
      const mac = process.platform === "darwin";
      const errno = mac ? "__error" : "__errno_location";
      const lib = ffi.dlopen(mac ? "libSystem.dylib" : "libc.so.6", {
        flock: { args: ["i32", "i32"], returns: "i32" },
        [errno]: { args: [], returns: "ptr" },
      });
      db_lock_sys = { ...lib.symbols, errno: lib.symbols[errno], read: ffi.read };
    }
    const result = db_lock_sys.flock(file, 6);
    const value = result === 0
      ? io_done({ $: CID(Unit) })
      : io_fail(Math.abs(db_lock_sys.read.i32(db_lock_sys.errno(), 0)));
    return io_tup(file, value);
  } catch (e) {
    return io_tup(file, io_fail(Math.abs(e.errno ?? 95)));
  }
}

io_eff(CID(DbLock.try_lock), db_lock_run);
