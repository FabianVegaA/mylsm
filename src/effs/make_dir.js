// Fs.make_dir

function make_dir(path) {
  const fs = require("fs");
  try {
    fs.mkdirSync(Buffer.from(io_bytes(path)), 0o700);
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(make_dir), make_dir);
