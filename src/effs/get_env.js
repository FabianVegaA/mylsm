// Console.get_env — copy an environment value, mirroring get_env.c.

function get_env(name) {
  try {
    const key = Buffer.from(io_bytes(name)).toString("utf8");
    return io_done(String(process.env[key] ?? ""));
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}

io_eff(CID(get_env), get_env);
