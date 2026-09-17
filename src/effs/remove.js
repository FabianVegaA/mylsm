// Fs.remove

function remove(path) {
  const fs = require("fs");
  try {
    fs.unlinkSync(Buffer.from(io_bytes(path)));
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}
