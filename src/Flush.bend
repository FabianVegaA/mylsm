import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SortedRun.bend as SortedRun
import ./SstFile.bend as SstFile
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest
import ./Fs.bend as Fs
import ./Db.bend as Db
import ./CrashPoint.bend as CrashPoint

# Flush (Task 8): sealed memtable -> L0 SSTable file + manifest + WAL reset.
#
# Crash protocol (each step durable before the next, tmp + rename for
# atomic visibility):
#   1. ensure <dir>/l0; write <name>.tmp; fsync; rename to <name>; fsync l0.
#   2. load manifest (absent file = fresh M{Nil}; corrupt = ABORT Fail).
#   3. write MANIFEST.tmp; fsync; rename; fsync dir.
#   4. remove wal.log (failure ignored: a stale WAL replays idempotently —
#      same versions, mem-first reads return equal values; merge dedups).
# A crash before step 3 leaves the table file orphaned (recovery ignores
# files absent from the manifest; Task 12 sweeps orphans). A crash after
# step 3 with a live WAL replays duplicates harmlessly (see above).
# Empty memtable flush is a no-op (no files touched).
# CrashPoint calls are test-only host effects. Unset or unequal checkpoints are
# successful no-ops; signal delivery and filesystem ordering are not Bend proofs.

def table_name(flushed: Nat) -> String:
  "l0-" ++ Nat.show(flushed) ++ ".tbl"

def l0_add(+levels: List<&2, List<&2, Sstable.Table>>, +tbl: Sstable.Table) -> List<&2, List<&2, Sstable.Table>>:
  match levels:
    case Nil{}:
      Con{Con{tbl, Nil{}}, Nil{}}
    case Con{l0, rest}:
      Con{Con{tbl, l0}, rest}

def mfst_add(+mfst: Manifest.Manifest, +name: String) -> Manifest.Manifest:
  match mfst:
    case Manifest.M{lvs}:
      match lvs:
        case Nil{}:
          Manifest.M{Con{Con{name, Nil{}}, Nil{}}}
        case Con{l0, rest}:
          Manifest.M{Con{Con{name, l0}, rest}}

# --- File helpers (pair-splits contained; straight-line callers above) ---

def write_tail(fr: (File & Result<&1, &1, U32 & String, Unit>), +path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match fr:
    case (f2, r):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        res : Unit <- IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, r))
        _cls : Unit <- File.close(f2)
        _syn : Unit <- IO.try(Unit, Fs.fsync(path))
        _p_rm : Unit <- IO.try(Unit, Fs.chmod(path, U32.from_nat(384n)))
        return Done{res}

def write_file(+path: String, +data: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    f : File <- IO.try(File, File.open(path, "w"))
    fr : (File & Result<&1, &1, U32 & String, Unit>) <- File.write(f, data)
    write_tail(fr, path)

def read_tail3(fr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match fr:
    case (f3, r1):
      do IO<Result<&1, &1, U32 & String, String>>:
        _cls : Unit <- File.close(f3)
        IO.pure(Result<&1, &1, U32 & String, String>, r1)


# Base File.read decodes each returned chunk independently. A chunk boundary can
# split a multi-byte UTF-8 character, so table files are read in one bounded call
# until a byte-oriented streaming effect with decoder carry is available.
def read_file(+path: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    f : File <- IO.try(File, File.open(path, "r"))
    fr : (File & Result<&1, &1, U32 & String, String>) <- File.read(f, U32.from_nat(4294967295n))
    read_tail3(fr)

def mfst_parsed(+opt: Maybe<&2, Manifest.Manifest>) -> Result<&1, &1, U32 & String, Manifest.Manifest>:
  match opt:
    case None{}:
      Fail{(U32.from_nat(1n), "bad manifest")}
    case Some{mm}:
      Done{mm}

def mfst_tail(res: Result<&1, &1, U32 & String, String>) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match res:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Manifest.Manifest>, Fail{e})
    case Done{s}:
      IO.pure(Result<&1, &1, U32 & String, Manifest.Manifest>, mfst_parsed(Manifest.parse(s)))

# A stat-confirmed absent manifest means a fresh database. Metadata, open, read,
# and parse errors for an existing manifest propagate fail-closed; they must
# never be reinterpreted as an empty database and overwritten.
def mread_tail(file: File) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
    fr : (File & Result<&1, &1, U32 & String, String>) <- File.read(file, U32.mul(U32.from_nat(1024n), U32.from_nat(1024n)))
    r : Result<&1, &1, U32 & String, String> <- read_tail3(fr)
    mfst_tail(r)

def mopen_tail(res: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match res:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Manifest.Manifest>, Fail{e})
    case Done{f}:
      mread_tail(f)

def load_mfst_exists(present: Bool, +path: String) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match present:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Manifest.Manifest>, Done{Manifest.M{Nil{}}})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        f : File <- IO.try(File, File.open(path, "r"))
        mread_tail(f)

def load_mfst(+path: String) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
    present : Bool <- IO.try(Bool, Fs.exists(path))
    load_mfst_exists(present, path)

def dir_tail(res: Result<&1, &1, U32 & String, Nat>, +path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match res:
    case Done{n}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
    case Fail{e}:
      Fs.make_dir(path)

def ensure_dir(+path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    r : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(path)
    dir_tail(r, path)

# --- Flush chain (defined bottom-up: tails first, entry last) ---

def flush_goB(
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +m2: Manifest.Manifest,
  +tbl: Sstable.Table,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +mem: MemTable.MemTable,
  +batch_cap: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    _v1 : Unit <- IO.try(Unit, write_file(mtmp, Manifest.serialize(m2)))
    _cp1 : Unit <- IO.try(Unit, CrashPoint.hit("flush.manifest_synced"))
    _v2 : Unit <- IO.try(Unit, Fs.rename(mtmp, mpath))
    _v3 : Unit <- IO.try(Unit, Fs.fsync(dir))
    _cp2 : Unit <- IO.try(Unit, CrashPoint.hit("flush.manifest_published"))
    _rm : Result<&1, &1, U32 & String, Unit> <- Fs.remove(Db.wal_path(dir))
    return Done{Db.Db{dir, mem, MemTable.MT{Nil{}}, batch_cap, Nil{}, l0_add(levels, tbl), Nat.add(flushed, 1n), Manifest.serialize(m2), 0n, 0n}}

def flush_drift(
  ok: Bool,
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +mfst: Manifest.Manifest,
  +tbl: Sstable.Table,
  +name: String,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +mem: MemTable.MemTable,
  +batch_cap: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(2n), "manifest drift")})
    case True{}:
      flush_goB(dir, mpath, mtmp, mfst_add(mfst, name), tbl, levels, flushed, mem, batch_cap)

def flush_goA(
  +dir: String,
  +l0dir: String,
  +tmp: String,
  +final: String,
  +mpath: String,
  +mtmp: String,
  +content: String,
  +tbl: Sstable.Table,
  +name: String,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +mem: MemTable.MemTable,
  +batch_cap: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    _u1 : Unit <- IO.try(Unit, ensure_dir(l0dir))
    _u2 : Unit <- IO.try(Unit, write_file(tmp, content))
    _cp1 : Unit <- IO.try(Unit, CrashPoint.hit("flush.table_synced"))
    _u3 : Unit <- IO.try(Unit, Fs.rename(tmp, final))
    _u4 : Unit <- IO.try(Unit, Fs.fsync(l0dir))
    _cp2 : Unit <- IO.try(Unit, CrashPoint.hit("flush.table_published"))
    +m : Manifest.Manifest <- IO.try(Manifest.Manifest, load_mfst(mpath))
    flush_drift(String.eq(Manifest.serialize(m), manifest_token), dir, mpath, mtmp, m, tbl, name, levels, flushed, mem, batch_cap)

def flush_pre(
  +dir: String,
  +entries: List<&2, MemTable.Entry>,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +batch_cap: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  +tbl = Sstable.build(entries, 0n, List.length(&2, MemTable.Entry, entries))
  +name = table_name(flushed)
  +l0dir = dir ++ "/l0"
  flush_goA(dir, l0dir, l0dir ++ "/" ++ name ++ ".tmp", l0dir ++ "/" ++ name, dir ++ "/MANIFEST", dir ++ "/MANIFEST.tmp", SstFile.serialize(Db.table_entries(tbl), 0n), tbl, name, levels, flushed, manifest_token, MemTable.MT{Nil{}}, batch_cap)

# Frozen-path flush MERGES mem (newer) over frozen (older) into one L0 table
# and drains both: the WAL is truncated on publish, so anything left in mem
# would otherwise exist nowhere on disk (loss window caught by 20485 smoke).
def flush_frozen(
  +dir: String,
  +mem: MemTable.MemTable,
  +entries: List<&2, MemTable.Entry>,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +batch_cap: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match mem:
    case MemTable.MT{live}:
      +merged = SortedRun.merge_many_newest(Con{live, Con{entries, Nil{}}})
      +tbl = Sstable.build(merged, 0n, List.length(&2, MemTable.Entry, merged))
      +name = table_name(flushed)
      +l0dir = dir ++ "/l0"
      flush_goA(dir, l0dir, l0dir ++ "/" ++ name ++ ".tmp", l0dir ++ "/" ++ name, dir ++ "/MANIFEST", dir ++ "/MANIFEST.tmp", SstFile.serialize(Db.table_entries(tbl), 0n), tbl, name, levels, flushed, manifest_token, MemTable.MT{Nil{}}, batch_cap)

def flush_pick(
  +frozen: MemTable.MemTable,
  +mem: MemTable.MemTable,
  +dir: String,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +batch_cap: Nat,
  +bcache: List<&2, Db.BEntry>,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match frozen mem:
    case MemTable.MT{Nil{}} MemTable.MT{Nil{}}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{Db.Db{dir, MemTable.MT{Nil{}}, MemTable.MT{Nil{}}, batch_cap, bcache, levels, flushed, manifest_token, 0n, 0n}})
    case MemTable.MT{Nil{}} MemTable.MT{Con{e, t}}:
      flush_pre(dir, Con{e, t}, levels, flushed, manifest_token, batch_cap)
    case MemTable.MT{Con{fe, ft}} _:
      flush_frozen(dir, mem, Con{fe, ft}, levels, flushed, manifest_token, batch_cap)

def flush(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      flush_pick(frozen, mem, dir, levels, flushed, manifest_token, batch_cap, bcache)

# --- Closed-vector laws live in laws/Flush.bend (spec law 6) ---
