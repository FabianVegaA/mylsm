// Fs.chmod

function chmod(path, bits) {
  const fs = require("fs");
  try {
    fs.chmodSync(Buffer.from(io_bytes(path)), bits < 0o10000 ? bits : 0o600);
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(chmod), chmod);
