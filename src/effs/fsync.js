// Fs.fsync ("r", not "r+": directory fsync must work for rename durability).

function fsync(path) {
  const fs = require("fs");
  const name = io_bytes(path);
  try {
    const fd = fs.openSync(Buffer.from(name), "r");
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(fsync), fsync);
