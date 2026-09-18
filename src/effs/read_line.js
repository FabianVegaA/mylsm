// Console.read_line — bounded synchronous line input, mirroring read_line.c.

function read_line() {
  const fs = require("fs");
  const os = require("os");
  const max = 1024 * 1024;
  const byte = Buffer.alloc(1);
  const bytes = [];
  try {
    for (;;) {
      const count = fs.readSync(0, byte, 0, 1, null);
      if (count === 0 || byte[0] === 0x0a) {
        return io_done(Buffer.from(bytes).toString("utf8"));
      }
      if (bytes.length === max) {
        return io_fail(os.constants.errno.EFBIG ?? 27);
      }
      bytes.push(byte[0]);
    }
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}
