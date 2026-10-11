function unix_socket_create() {
  return io_fail(Math.abs(require("os").constants.errno.ENOTSUP ?? require("os").constants.errno.EOPNOTSUPP ?? 95));
}

io_eff(CID(unix_socket_create), unix_socket_create);
