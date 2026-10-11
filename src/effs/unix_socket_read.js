function unix_socket_read(file, _max) {
  const code = Math.abs(require("os").constants.errno.ENOTSUP ?? 95);
  return io_tup(file, io_fail(code));
}

io_eff(CID(unix_socket_read), unix_socket_read);
