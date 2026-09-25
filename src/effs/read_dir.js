// Fs.read_dir_count / Fs.read_dir_at — indexed listing, mirroring read_dir.c.

function read_dir_count(path) {
  const fs = require("fs");
  try {
    const names = fs.readdirSync(Buffer.from(io_bytes(path))).map(String)
      .filter((s) => s !== "." && s !== ".." && !s.includes("\n"));
    return io_done(BigInt(names.length));
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

function read_dir_at(path, i) {
  const fs = require("fs");
  const idx = Number(i);
  try {
    const names = fs.readdirSync(Buffer.from(io_bytes(path))).map(String)
      .filter((s) => s !== "." && s !== ".." && !s.includes("\n"));
    return io_done(idx < names.length ? names[idx] : "");
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(read_dir_count), read_dir_count);
io_eff(CID(read_dir_at), read_dir_at);
