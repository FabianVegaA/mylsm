function emit(line) {
  try {
    const bytes = Buffer.from(io_bytes(line));
    const written = require("fs").writeSync(2, bytes);
    return written === bytes.length ? io_done({ $: "Unit" }) : io_fail(5);
  } catch (error) {
    return io_fail(Math.abs(error.errno ?? 5));
  }
}

io_eff(CID(emit), emit);
