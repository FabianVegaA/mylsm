function unix_socket_accept(server) {
  return io_tup(server, io_fail(Math.abs(require("os").constants.errno.ENOTSUP ?? require("os").constants.errno.EOPNOTSUPP ?? 95)));
}

io_eff(CID(unix_socket_accept), unix_socket_accept);
