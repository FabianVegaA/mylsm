function unix_socket_alarm() {
  return io_done({ $: CID(Unit) });
}

io_eff(CID(unix_socket_alarm), unix_socket_alarm);
