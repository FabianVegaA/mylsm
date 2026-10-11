function sleep_ms(milliseconds) {
  try {
    const delay = Number(milliseconds);
    if (!Number.isSafeInteger(delay) || delay < 0) return io_fail(22);
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, delay);
    return io_done({ $: CID(Unit) });
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(sleep_ms), sleep_ms);
