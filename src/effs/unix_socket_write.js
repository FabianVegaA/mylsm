function unix_socket_write(file, _offset, _length, _words) {
  const code = Math.abs(require("os").constants.errno.ENOTSUP ?? 95);
  return io_tup(file, io_fail(code));
}

io_eff(CID(unix_socket_write), unix_socket_write);
