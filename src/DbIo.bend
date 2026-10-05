import Base
import ./Db.bend as Db
import ./Wal.bend as Wal
import ./Fs.bend as Fs
import ./CrashPoint.bend as CrashPoint
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

def wal.initialize.synced(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _synced : Unit <- IO.try(Unit, Fs.fsync(path))
        changed : Result<&1, &1, U32 & String, Unit> <- Fs.chmod(path, U32.from_nat(384n))
        return changed

def wal.initialize.written(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match pair:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        wal.initialize.synced(result, path)

def wal.initialize.header(+path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    file : File <- IO.try(File, File.open(path, "a"))
    written : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, Wal.log_header())
    wal.initialize.written(written, path)

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

# Handle wal initialize in the database filesystem effects.
def wal_initialize(+dir: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    present : Bool <- IO.try(Bool, Fs.exists(Db.wal_path(dir)))
    wal.initialize.present(present, Db.wal_path(dir))

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

# Handle db write in the database filesystem effects.
def db_write(+db: Db.Db, +batch: Wal.Batch) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      match batch:
        case Wal.Batch{muts}:
          do IO<Result<&1, &1, U32 & String, Db.Db>>:
            _res : Unit <- IO.try(Unit, wal_append(dir, Wal.Batch{muts}))
            return Db.rot_done(Db.apply_and_rotate(muts, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

# Handle db put in the database filesystem effects.
def db_put(+db: Db.Db, +key: String, +val: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  db_write(db, Wal.Batch{Con{Wal.Put{key, val}, Nil{}}})

# Handle db write staged in the database filesystem effects.
def db_write_staged(+db: Db.Db, +staged: List<&2, Wal.Batch>) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      db_write(Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}, Wal.Batch{Db.staged_muts(List.reverse(&2, Wal.Batch, staged))})

# Handle db del in the database filesystem effects.
def db_del(+db: Db.Db, +key: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  db_write(db, Wal.Batch{Con{Wal.Del{key}, Nil{}}})
