function unix_socket_connect(client, path) {
  return io_tup(client, io_fail(Math.abs(require("os").constants.errno.ENOTSUP ?? require("os").constants.errno.EOPNOTSUPP ?? 95)));
}

io_eff(CID(unix_socket_connect), unix_socket_connect);
