function canonical_path(path) {
  const fs = require("fs");
  try {
    const resolved = String(fs.realpathSync(Buffer.from(io_bytes(path))));
    return io_done(resolved);
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(canonical_path), canonical_path);
