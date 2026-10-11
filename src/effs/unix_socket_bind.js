function unix_socket_bind(server, path) {
  return io_tup(server, io_fail(Math.abs(require("os").constants.errno.ENOTSUP ?? require("os").constants.errno.EOPNOTSUPP ?? 95)));
}

io_eff(CID(unix_socket_bind), unix_socket_bind);
