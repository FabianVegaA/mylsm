function unix_socket_write_nonblocking(file, _offset, _length, words) {
  const code = Math.abs(require("os").constants.errno.ENOTSUP ?? 95);
  return io_tup(file, io_tup(words, io_fail(code)));
}

io_eff(CID(unix_socket_write_nonblocking), unix_socket_write_nonblocking);
