function clock_monotonic() {
  try {
    return io_done(process.hrtime.bigint());
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(clock_monotonic), clock_monotonic);
