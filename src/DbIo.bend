import Base
import ./Db.bend as Db
import ./Wal.bend as Wal
import ./Fs.bend as Fs
import ./CrashPoint.bend as CrashPoint
import ./DurableCommit.bend as Commit
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Host boundary for durable Db operations. Pure transitions and their laws live
# in Db; filesystem ordering remains an explicitly unproved host interaction.

# Handle wal tail in the database filesystem effects.
def wal_tail(fr: (File & Result<&1, &1, U32 & String, Unit>), +dir: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match fr:
    case (f2, r):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        res : Unit <- IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, r))
        _cp1 : Unit <- IO.try(Unit, CrashPoint.hit("wal.appended"))
        _cls : Unit <- File.close(f2)
        _syn : Unit <- IO.try(Unit, Fs.fsync(Db.wal_path(dir)))
        _cp2 : Unit <- IO.try(Unit, CrashPoint.hit("wal.synced"))
        _prm : Unit <- IO.try(Unit, Fs.chmod(Db.wal_path(dir), U32.from_nat(384n)))
        return Done{res}

def wal.initialize.fsync(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      Fs.chmod(path, U32.from_nat(384n))

def wal.initialize.synced(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path)
        wal.initialize.fsync(synced, path)

def wal.initialize.written(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match pair:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        wal.initialize.synced(result, path)

def wal.initialize.opened(
  opened: Result<&1, &1, U32 & String, File>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        written : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, Wal.log_header())
        wal.initialize.written(written, path)

def wal.initialize.header(+path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "a")
    wal.initialize.opened(opened, path)

def wal.initialize.header_if_empty(
  empty: Bool,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match empty:
    case True{}:
      wal.initialize.header(path)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})

def wal.initialize.existing(
  result: Result<&1, &1, U32 & String, Nat>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{size}:
      wal.initialize.header_if_empty(Nat.is_eq(size, 0n), path)

def wal.initialize.present(
  present: Bool,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match present:
    case False{}:
      wal.initialize.header(path)
    case True{}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
        wal.initialize.existing(size, path)

def wal.initialize.exists(
  result: Result<&1, &1, U32 & String, Bool>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{present}:
      wal.initialize.present(present, path)

# Creates the WAL only when it is absent.
def wal_initialize(+dir: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    present : Result<&1, &1, U32 & String, Bool> <- Fs.exists(Db.wal_path(dir))
    wal.initialize.exists(present, Db.wal_path(dir))

# Handle wal encoded in the database filesystem effects.
def wal_encoded(
  +dir: String,
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, Unit>,
        Fail{(U32.from_nat(3n), "WAL batch cannot be encoded")})
    case Done{frame}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        f : File <- IO.try(File, File.open(Db.wal_path(dir), "a"))
        fr : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(f, frame)
        wal_tail(fr, dir)

# Handle wal append in the database filesystem effects.
def wal_append(+dir: String, batch: Wal.Batch) -> IO(Result<&1, &1, U32 & String, Unit>):
  wal_encoded(dir, Wal.encode_frame(batch))

# Turns the fsync result into a durable or uncertain commit stage.
def append_synced(result: Result<&1, &1, U32 & String, Unit>, file: File) -> IO(Commit.Stage):
  match result:
    case Fail{(code, message)}:
      do IO<Commit.Stage>:
        _closed : Unit <- File.close(file)
        return Commit.AppendUnknown{code, message}
    case Done{Unit{}}:
      do IO<Commit.Stage>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("wal.synced"))
        _closed : Unit <- File.close(file)
        return Commit.DurableAppend{}

# Syncs the WAL after a successful append and closes the file.
def append_written(pair: File & Result<&1, &1, U32 & String, Unit>, +path: String) -> IO(Commit.Stage):
  match pair:
    case (file, Fail{(code, message)}):
      do IO<Commit.Stage>:
        _closed : Unit <- File.close(file)
        return Commit.AppendUnknown{code, message}
    case (file, Done{Unit{}}):
      do IO<Commit.Stage>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("wal.appended"))
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path)
        append_synced(synced, file)

# Rejects an open failure before append or writes the encoded frame.
def append_opened(opened: Result<&1, &1, U32 & String, File>, frame: Bytes.Bytes, +path: String) -> IO(Commit.Stage):
  match opened:
    case Fail{(code, message)}:
      IO.pure(Commit.Stage, Commit.AppendRejected{code, message})
    case Done{file}:
      do IO<Commit.Stage>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("wal.before_append"))
        written : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, frame)
        append_written(written, path)

# Opens the WAL and appends one encoded frame.
def append_frame(+path: String, frame: Bytes.Bytes) -> IO(Commit.Stage):
  do IO<Commit.Stage>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "a")
    append_opened(opened, frame, path)

# Rejects encoding errors before opening the WAL.
def encoded_append(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>,
  +dir: String,
  muts: List<&2, Wal.Mut>,
) -> IO(Commit.Stage & List<&2, Wal.Mut>):
  match result:
    case Fail{error}:
      IO.pure(Commit.Stage & List<&2, Wal.Mut>, (Commit.EncodingRejected{error}, muts))
    case Done{frame}:
      do IO<Commit.Stage & List<&2, Wal.Mut>>:
        stage : Commit.Stage <- append_frame(Db.wal_path(dir), frame)
        return (stage, muts)

# Encodes a batch and appends it to the WAL.
def wal_commit(+dir: String, +batch: Wal.Batch) -> IO(Commit.Stage & List<&2, Wal.Mut>):
  match batch:
    case Wal.Batch{muts}:
      encoded_append(Wal.encode_frame(Wal.Batch{muts}), dir, muts)

# Persists a batch before applying its pure commit transition.
def db_write_durable(+db: Db.Db, +batch: Wal.Batch) -> IO(Db.Db & Commit.Stage):
  match db:
    case Db.Db{dir, _, _, _, _, _, _, _, _, _}:
      do IO<Db.Db & Commit.Stage>:
        pair : Commit.Stage & List<&2, Wal.Mut> <- wal_commit(dir, batch)
        return Commit.apply(pair, db)

# Persists a batch and rotates the MemTable when needed.
def db_write(+db: Db.Db, +batch: Wal.Batch) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      match batch:
        case Wal.Batch{muts}:
          do IO<Result<&1, &1, U32 & String, Db.Db>>:
            _res : Unit <- IO.try(Unit, wal_append(dir, Wal.Batch{muts}))
            return Db.rot_done(Db.apply_and_rotate(muts, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

# Writes one key/value pair through the legacy core path.
def db_put(+db: Db.Db, +key: String, +val: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  db_write(db, Wal.Batch{Con{Wal.Put{key, val}, Nil{}}})

# Restores staged mutation order before writing the batch.
def db_write_staged(+db: Db.Db, +staged: List<&2, Wal.Batch>) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      db_write(Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}, Wal.Batch{Db.staged_muts(List.reverse(&2, Wal.Batch, staged))})

# Writes one tombstone through the legacy core path.
def db_del(+db: Db.Db, +key: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  db_write(db, Wal.Batch{Con{Wal.Del{key}, Nil{}}})
