const clock_origin = process.hrtime.bigint();

function clock_monotonic() {
  try {
    return io_done(Number(process.hrtime.bigint() - clock_origin));
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(clock_monotonic), clock_monotonic);
