// Fs.exists — distinguish an absent path from metadata failures.

function exists(path) {
  const fs = require("fs");
  try {
    fs.statSync(Buffer.from(io_bytes(path)));
    return io_done(true);
  } catch (e) {
    if (e && e.code === "ENOENT") {
      return io_done(false);
    }
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(exists), exists);
