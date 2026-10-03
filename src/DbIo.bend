import Base
import ./Db.bend as Db
import ./Wal.bend as Wal
import ./Fs.bend as Fs
import ./CrashPoint.bend as CrashPoint
import ./Decimal.bend as Decimal

# Host boundary for durable Db operations. Pure transitions and their laws live
# in Db; filesystem ordering remains an explicitly unproved host interaction.

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

def wal_append(+dir: String, +data: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    f : File <- IO.try(File, File.open(Db.wal_path(dir), "a"))
    fr : (File & Result<&1, &1, U32 & String, Unit>) <- File.write(f, Db.wal_frame(data))
    wal_tail(fr, dir)

def db_write(+db: Db.Db, +batch: Wal.Batch) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      match batch:
        case Wal.Batch{muts}:
          do IO<Result<&1, &1, U32 & String, Db.Db>>:
            _res : Unit <- IO.try(Unit, wal_append(dir, Wal.encode(Wal.Batch{muts})))
            return Db.rot_done(Db.apply_and_rotate(muts, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

def db_put(+db: Db.Db, +key: String, +val: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  db_write(db, Wal.Batch{Con{Wal.Put{key, val}, Nil{}}})

def db_write_staged(+db: Db.Db, +staged: List<&2, Wal.Batch>) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      db_write(Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}, Wal.Batch{Db.staged_muts(List.reverse(&2, Wal.Batch, staged))})

def db_del(+db: Db.Db, +key: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  db_write(db, Wal.Batch{Con{Wal.Del{key}, Nil{}}})

def reopen_read_loop(
  chunks_left: Nat,
  +path: String,
  +offset: Nat,
  +acc: List<&2, String>,
  pending: Maybe<&2, Db.ReChunk>,
) -> IO(Result<&1, &1, U32 & String, String>):
  match chunks_left pending:
    case 0n _:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{(U32.from_nat(7n), "wal exceeds streaming read limit")})
    case 1n+rest None{}:
      do IO<Result<&1, &1, U32 & String, String>>:
        raw : String <- IO.try(String, Fs.read_utf8_chunk(path, offset, Db.reopen_chunk_chars()))
        chunk : Db.ReChunk <- IO.try(Db.ReChunk, IO.pure(Result<&1, &1, U32 & String, Db.ReChunk>, Db.reopen_chunk_parse(Decimal.parse_semicolon(raw, Db.reopen_chunk_chars()))))
        reopen_read_loop(rest, path, offset, acc, Some{chunk})
    case 1n+rest Some{Db.ReChunk{bytes, text}}:
      match bytes:
        case 0n:
          IO.pure(Result<&1, &1, U32 & String, String>, Done{String.join(List.reverse(&2, String, acc), "")})
        case 1n+more:
          reopen_read_loop(rest, path, Nat.add(offset, 1n+more), Con{text, acc}, None{})

def reopen_read(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    content : String <- IO.try(String, reopen_read_loop(8192n, Db.wal_path(dir), 0n, Nil{}, None{}))
    return Done{Db.reopen_assemble(Db.reopen_replay(content), dir)}

def reopen_exists(ok: Result<&1, &1, U32 & String, Bool>, +dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{e})
    case Done{present}:
      match present:
        case False{}:
          IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{Db.open_db(dir)})
        case True{}:
          reopen_read(dir)

def reopen(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    r : Result<&1, &1, U32 & String, Bool> <- Fs.exists(Db.wal_path(dir))
    reopen_exists(r, dir)
