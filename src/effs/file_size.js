// Fs.file_size — read-only byte size via statSync, mirroring exists.js.

function file_size(path) {
  const fs = require("fs");
  try {
    const size = fs.statSync(Buffer.from(io_bytes(path))).size;
    return io_done(BigInt(size < 0 ? 0 : size));
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(file_size), file_size);
