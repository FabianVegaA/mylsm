function db_lock_run(file) {
  return io_tup(file, io_fail(65535));
}

io_eff(CID(DbLock.try_lock), db_lock_run);
