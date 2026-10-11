let rename_noreplace_sys;

function rename_noreplace_run(oldPath, newPath) {
  try {
    if (rename_noreplace_sys === undefined) {
      const ffi = require("bun:ffi");
      const mac = process.platform === "darwin";
      const name = mac ? "renameatx_np" : "renameat2";
      const errno = mac ? "__error" : "__errno_location";
      const args = ["i32", "ptr", "i32", "ptr", "u32"];
      const lib = ffi.dlopen(mac ? "libSystem.dylib" : "libc.so.6", {
        [name]: { args, returns: "i32" },
        [errno]: { args: [], returns: "ptr" },
      });
      rename_noreplace_sys = {
        rename: lib.symbols[name],
        errno: lib.symbols[errno],
        read: ffi.read,
        mac,
      };
    }
    const oldName = Buffer.from(`${oldPath}\0`, "utf8");
    const newName = Buffer.from(`${newPath}\0`, "utf8");
    const result = rename_noreplace_sys.mac
      ? rename_noreplace_sys.rename(-2, oldName, -2, newName, 4)
      : rename_noreplace_sys.rename(-100, oldName, -100, newName, 1);
    return result === 0
      ? io_done({ $: CID(Unit) })
      : io_fail(Math.abs(rename_noreplace_sys.read.i32(
        rename_noreplace_sys.errno(), 0)));
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 95));
  }
}

io_eff(CID(rename_noreplace), rename_noreplace_run);
