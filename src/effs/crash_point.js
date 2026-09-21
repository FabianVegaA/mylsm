// CrashPoint.stop — JavaScript twin of crash_point.c. Bend owns policy.

function stop(name) {
  try {
    const requested = Buffer.from(io_bytes(name));
    if (process.platform !== "darwin" && process.platform !== "linux") {
      const os = require("os");
      return io_fail(Math.abs(os.constants.errno.ENOTSUP ?? 95));
    }
    const fs = require("fs");
    const marker = Buffer.concat([Buffer.from("crash_point_reached="), requested, Buffer.from("\n")]);
    let offset = 0;
    while (offset < marker.length) {
      const written = fs.writeSync(2, marker, offset, marker.length - offset);
      if (written <= 0) {
        return io_fail(5);
      }
      offset += written;
    }
    process.kill(process.pid, "SIGSTOP");
    return io_done({ $: "Unit" });
  } catch (error) {
    return io_fail(Math.abs(error.errno ?? 5));
  }
}
