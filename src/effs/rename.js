// Fs.rename

function rename(oldp, newp) {
  const fs = require("fs");
  try {
    fs.renameSync(Buffer.from(io_bytes(oldp)), Buffer.from(io_bytes(newp)));
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}
