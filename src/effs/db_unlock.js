function db_unlock_run(file) {
  return io_tup(file, io_fail(65535));
}

io_eff(CID(DbLock.try_unlock), db_unlock_run);
