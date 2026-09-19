// Fs.read_utf8_chunk — positional reads ending on a complete UTF-8 boundary.

function utf8_safe_prefix(data) {
  if (data.length === 0) return 0;
  let lead = data.length - 1;
  while (lead > 0 && ((data[lead] & 0xC0) === 0x80)) lead -= 1;
  const c = data[lead];
  const need = c < 0x80 ? 1 : (c & 0xE0) === 0xC0 ? 2 : (c & 0xF0) === 0xE0 ? 3 : (c & 0xF8) === 0xF0 ? 4 : 1;
  return data.length - lead < need ? lead : data.length;
}

function read_utf8_chunk(path, offset, requested) {
  const fs = require("fs");
  const size = Number(requested);
  const position = Number(offset);
  let fd;
  try {
    if (!Number.isSafeInteger(size) || size <= 0 || !Number.isSafeInteger(position) || position < 0) {
      return io_fail(22);
    }
    fd = fs.openSync(Buffer.from(io_bytes(path)), "r");
    const data = Buffer.allocUnsafe(size);
    const got = fs.readSync(fd, data, 0, size, position);
    const slice = data.subarray(0, got);
    const safe = got < size ? got : utf8_safe_prefix(slice);
    const header = Buffer.from(String(safe) + ";", "ascii");
    return io_done(Buffer.concat([header, slice.subarray(0, safe)]).toString("utf8"));
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}
