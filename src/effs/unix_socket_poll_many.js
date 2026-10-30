function unix_socket_poll_many(interests) {
  return io_tup(interests, io_fail(95));
}

io_eff(CID(unix_socket_poll_many), unix_socket_poll_many);
