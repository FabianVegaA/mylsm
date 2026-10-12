function run(program, args, env, logPath) {
  const command = [program];
  for (let items = args; items.$ === CID(Con); items = items.tail) {
    command.push(items.head);
  }
  const childEnv = { ...process.env };
  for (let items = env; items.$ === CID(Con); items = items.tail) {
    childEnv[items.head.fst] = items.head.snd;
  }
  let descriptor;
  try {
    const options = { cmd: command, env: childEnv, stdin: "inherit", stdout: "inherit", stderr: "inherit" };
    if (logPath.$ === CID(Some)) {
      descriptor = require("node:fs").openSync(logPath.value, "w");
      options.stdout = descriptor;
      options.stderr = descriptor;
    }
    const child = Bun.spawnSync(options);
    if (child.exitCode === null || child.exitCode === undefined) {
      return io_fail(5);
    }
    return io_done(child.exitCode);
  } catch (error) {
    return io_fail(Math.abs(error.errno ?? 5));
  } finally {
    if (descriptor !== undefined) {
      require("node:fs").closeSync(descriptor);
    }
  }
}

io_eff(CID(run), run);
