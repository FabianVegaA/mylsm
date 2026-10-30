function unix_socket_poll(file) {
  const code = Math.abs(require("os").constants.errno.ENOTSUP ?? 95);
  return io_tup(file, io_fail(code));
}

io_eff(CID(unix_socket_poll), unix_socket_poll);
