function truncate(path, offset) {
  const fs = require("fs");
  const size = Number(offset);
  if (!Number.isSafeInteger(size) || size < 0) return io_fail(22);
  try {
    fs.truncateSync(Buffer.from(io_bytes(path)), size);
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(truncate), truncate);
