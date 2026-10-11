function owner_spawn(argv) {
  const command = [];
  for (let xs = argv; xs.$ === CID(Con); xs = xs.tail) {
    command.push(xs.head);
  }
  try {
    const child = Bun.spawn({ cmd: command, stdin: "ignore", stdout: "ignore",
      stderr: "ignore" });
    child.unref();
    return io_done(child.pid);
  } catch (error) {
    return io_fail(Math.abs(error.errno ?? 5));
  }
}

io_eff(CID(owner_spawn), owner_spawn);
