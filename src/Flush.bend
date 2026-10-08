import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SortedRun.bend as SortedRun
import ./SstStreamIo.bend as SstStreamIo
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest
import ./StorageBytes.bend as StorageBytes
import ./Fs.bend as Fs
import ./DbIo.bend as DbIo
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ./Db.bend as Db
import ./CrashPoint.bend as CrashPoint
import ./FlushPolicy.bend as Policy

# Represent ManifestReadState data used by the memtable flush.
type ManifestReadState is Type:
  ManifestNeed{file: File, remaining: Nat, chunks: List<&1, Bytes.Bytes>}
  ManifestGot{pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>, remaining: Nat, chunks: List<&1, Bytes.Bytes>}

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

# Handle l0 add in the memtable flush.
def l0_add(+levels: List<&2, List<&2, Sstable.Table>>, +tbl: Sstable.Table) -> List<&2, List<&2, Sstable.Table>>:
  match levels:
    case Nil{}:
      Con{Con{tbl, Nil{}}, Nil{}}
    case Con{l0, rest}:
      Con{Con{tbl, l0}, rest}

# Handle mfst add in the memtable flush.
def mfst_add(+mfst: Manifest.Manifest, +name: String) -> Manifest.Manifest:
  match mfst:
    case Manifest.M{lvs}:
      match lvs:
        case Nil{}:
          Manifest.M{Con{Con{name, Nil{}}, Nil{}}}
        case Con{l0, rest}:
          Manifest.M{Con{Con{name, l0}, rest}}

# --- File helpers (pair-splits contained; straight-line callers above) ---

def write_tail.chmod(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      Fs.chmod(path, U32.from_nat(384n))

def write_tail.fsync(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path)
        write_tail.chmod(synced, path)

# Writes the remaining bytes of a file buffer.
def write_tail(
  fr: File & Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match fr:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        write_tail.fsync(result, path)

def write_file.opened(
  opened: Result<&1, &1, U32 & String, File>,
  +path: String,
  +data: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        written : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, data)
        write_tail(written, path)

# Creates and syncs one storage file.
def write_file(+path: String, +data: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    write_file.opened(opened, path, data)

def write_manifest.bytes.opened(
  opened: Result<&1, &1, U32 & String, File>,
  +path: String,
  bytes: Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        written : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        write_tail(written, path)

def write_manifest.bytes(+path: String, bytes: Bytes.Bytes) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    write_manifest.bytes.opened(opened, path, bytes)

def write_manifest.encoded(
  path: String,
  encoded: Result<&1, &1, Manifest.Error, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match encoded:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{(U32.from_nat(1n), "cannot encode manifest")})
    case Done{bytes}:
      write_manifest.bytes(path, bytes)

# Write manifest for the memtable flush.
def write_manifest(path: String, manifest: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Unit>):
  write_manifest.encoded(path, Manifest.serialize(manifest))

# Read tail3 for the memtable flush.
def read_tail3(fr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match fr:
    case (f3, r1):
      do IO<Result<&1, &1, U32 & String, String>>:
        _cls : Unit <- File.close(f3)
        IO.pure(Result<&1, &1, U32 & String, String>, r1)


# Base File.read decodes each returned chunk independently. A chunk boundary can
# split a multi-byte UTF-8 character, so table files are read in one bounded call
# Reads a bounded storage file and returns its bytes.
def read_file.opened(
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, String>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, String>>:
        result : File & Result<&1, &1, U32 & String, String> <- File.read(file, U32.from_nat(4294967295n))
        read_tail3(result)

# Reads a bounded storage file and returns its bytes.
def read_file(+path: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read_file.opened(opened)

# Classifies the Manifest parse result before recovery.
def mfst_parsed(parsed: Manifest.ParseResult) -> Result<&1, &1, U32 & String, Manifest.Manifest>:
  match parsed:
    case Manifest.Parsed{manifest}:
      Done{manifest}
    case Manifest.UnsupportedVersion{_}:
      Fail{(Manifest.unsupported_version_error_code(), "unsupported manifest version")}
    case Manifest.Malformed{}:
      Fail{(Manifest.malformed_error_code(), "malformed manifest")}
    case Manifest.ParseLimitExceeded{}:
      Fail{(Manifest.parse_limit_error_code(), "manifest size limit exceeded")}

def manifest.read.result(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match pair:
    case (file, Fail{error}):
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        _closed : Unit <- File.close(file)
        return Fail{error}
    case (file, Done{bytes}):
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        _closed : Unit <- File.close(file)
        return mfst_parsed(Manifest.parse_result(bytes))

def manifest.read.loop(fuel: Nat, state: ManifestReadState) -> IO(File & Result<&1, &1, U32 & String, Bytes.Bytes>):
  match fuel:
    case 0n:
      match state:
        case ManifestNeed{file, +remaining, chunks}:
          match remaining:
            case 0n:
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Done{Bytes.concat(List.reverse(&1, Bytes.Bytes, chunks))}))
            case 1n+_:
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{(U32.from_nat(7n), "bounded manifest read exhausted")}))
        case ManifestGot{pair, _, _}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{error}))
            case (file, Done{_}):
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{(U32.from_nat(7n), "bounded manifest read exhausted")}))
    case 1n+rest:
      match state:
        case ManifestNeed{file, +remaining, chunks}:
          match remaining:
            case 0n:
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Done{Bytes.concat(List.reverse(&1, Bytes.Bytes, chunks))}))
            case 1n+_:
              do IO<File & Result<&1, &1, U32 & String, Bytes.Bytes>>:
                pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_bytes(file, U32.from_nat(remaining))
                manifest.read.loop(rest, ManifestGot{pair, remaining, chunks})
        case ManifestGot{pair, +remaining, chunks}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{error}))
            case (file, Done{Bytes.Bytes{0, _}}):
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{(U32.from_nat(8n), "truncated manifest file")}))
            case (file, Done{Bytes.Bytes{+len, buf}}):
              manifest.read.loop(rest, ManifestNeed{file, Nat.sub(remaining, U32.to_nat(len)), Con{Bytes.Bytes{len, buf}, chunks}})

def manifest.read.size.run(file: File, +size: Nat) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
    pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- manifest.read.loop(Nat.add(size, 1n), ManifestNeed{file, size, Nil{}})
    manifest.read.result(pair)

def manifest.read.size.valid(
  file: File,
  size: Nat,
  within: Bool
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match within:
    case False{}:
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        _closed : Unit <- File.close(file)
        return Fail{(U32.from_nat(9n), "manifest too large")}
    case True{}:
      manifest.read.size.run(file, size)

def manifest.read.size(
  file: File,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match result:
    case Fail{error}:
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        _closed : Unit <- File.close(file)
        return Fail{error}
    case Done{+size}:
      manifest.read.size.valid(file, size, Nat.is_le(size, U32.to_nat(StorageBytes.MAX_MANIFEST_BYTES())))

# Handle mfst open error in the memtable flush.
def mfst_open_error(
  missing: Bool,
  +code: U32
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match missing:
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, Manifest.Manifest>, Done{Manifest.M{Nil{}}})
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Manifest.Manifest>, Fail{(code, "cannot open manifest")})

# Handle mfst opened in the memtable flush.
def mfst_opened(
  path: String,
  result: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match result:
    case Fail{(+code, _)}:
      mfst_open_error(U32.is_eq(code, 2), code)
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
        manifest.read.size(file, size)

# Handle load mfst in the memtable flush.
def load_mfst(+path: String) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    mfst_opened(path, opened)

# Handle dir tail in the memtable flush.
def dir_tail(res: Result<&1, &1, U32 & String, Nat>, +path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match res:
    case Done{n}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
    case Fail{e}:
      Fs.make_dir(path)

# Handle ensure dir in the memtable flush.
def ensure_dir(+path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    r : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(path)
    dir_tail(r, path)

# --- Flush chain (defined bottom-up: tails first, entry last) ---

def flush_goB.wal(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +m2: Manifest.Manifest,
  +tbl: Sstable.Table,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +mem: MemTable.MemTable,
  +batch_cap: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>,
        Done{Db.Db{dir, mem, MemTable.MT{Nil{}}, batch_cap, Nil{},
          l0_add(levels, tbl), Nat.add(flushed, 1n), Manifest.token(m2), 0n, 0n}})

def flush_goB.synced(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +m2: Manifest.Manifest,
  +tbl: Sstable.Table,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +mem: MemTable.MemTable,
  +batch_cap: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("flush.manifest_published"))
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(Db.wal_path(dir))
        initialized : Result<&1, &1, U32 & String, Unit> <- DbIo.wal_initialize(dir)
        flush_goB.wal(initialized, dir, m2, tbl, levels, flushed, mem, batch_cap)

def flush_goB.renamed(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +m2: Manifest.Manifest,
  +tbl: Sstable.Table,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +mem: MemTable.MemTable,
  +batch_cap: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(dir)
        flush_goB.synced(synced, dir, m2, tbl, levels, flushed, mem, batch_cap)

def flush_goB.written(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +m2: Manifest.Manifest,
  +tbl: Sstable.Table,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +mem: MemTable.MemTable,
  +batch_cap: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("flush.manifest_synced"))
        renamed : Result<&1, &1, U32 & String, Unit> <- Fs.rename(mtmp, mpath)
        flush_goB.renamed(renamed, dir, m2, tbl, levels, flushed, mem, batch_cap)

# Publishes flushed SSTables and updates the Manifest.
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
    written : Result<&1, &1, U32 & String, Unit> <- write_manifest(mtmp, m2)
    flush_goB.written(written, dir, mpath, mtmp, m2, tbl, levels, flushed, mem, batch_cap)

# Flush drift for the memtable flush.
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

def flush_goA.loaded(
  result: Result<&1, &1, U32 & String, Manifest.Manifest>,
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +tbl: Sstable.Table,
  +name: String,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +mem: MemTable.MemTable,
  +batch_cap: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{+current}:
      flush_drift(String.eq(Manifest.token(current), manifest_token), dir,
        mpath, mtmp, current, tbl, name, levels, flushed, mem, batch_cap)

def flush_goA.synced(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +tbl: Sstable.Table,
  +name: String,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +mem: MemTable.MemTable,
  +batch_cap: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("flush.table_published"))
        current : Result<&1, &1, U32 & String, Manifest.Manifest> <- load_mfst(mpath)
        flush_goA.loaded(current, dir, mpath, mtmp, tbl, name, levels,
          flushed, manifest_token, mem, batch_cap)

def flush_goA.renamed(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +l0dir: String,
  +mpath: String,
  +mtmp: String,
  +tbl: Sstable.Table,
  +name: String,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +mem: MemTable.MemTable,
  +batch_cap: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(l0dir)
        flush_goA.synced(synced, dir, mpath, mtmp, tbl, name, levels,
          flushed, manifest_token, mem, batch_cap)

# Writes the MemTable to an SSTable and completes the flush.
def flush_goA.written(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +l0dir: String,
  +tmp: String,
  +final: String,
  +mpath: String,
  +mtmp: String,
  +tbl: Sstable.Table,
  +name: String,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +mem: MemTable.MemTable,
  +batch_cap: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        _cp1 : Unit <- IO.try(Unit, CrashPoint.hit("flush.table_synced"))
        renamed : Result<&1, &1, U32 & String, Unit> <- Fs.rename(tmp, final)
        flush_goA.renamed(renamed, dir, l0dir, mpath, mtmp, tbl, name, levels, flushed, manifest_token, mem, batch_cap)

def flush_goA.ensured(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +l0dir: String,
  +tmp: String,
  +final: String,
  +mpath: String,
  +mtmp: String,
  +entries: List<&2, MemTable.Entry>,
  +level: U32,
  +tbl: Sstable.Table,
  +name: String,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +mem: MemTable.MemTable,
  +batch_cap: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        written : Result<&1, &1, U32 & String, Unit> <- SstStreamIo.write_table(tmp, entries, level)
        flush_goA.written(written, dir, l0dir, tmp, final, mpath, mtmp, tbl, name, levels, flushed, manifest_token, mem, batch_cap)

# Writes the MemTable to an SSTable and completes the flush.
def flush_goA(
  +dir: String,
  +l0dir: String,
  +tmp: String,
  +final: String,
  +mpath: String,
  +mtmp: String,
  +entries: List<&2, MemTable.Entry>,
  +level: U32,
  +tbl: Sstable.Table,
  +name: String,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +mem: MemTable.MemTable,
  +batch_cap: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    ensured : Result<&1, &1, U32 & String, Unit> <- ensure_dir(l0dir)
    flush_goA.ensured(ensured, dir, l0dir, tmp, final, mpath, mtmp, entries, level, tbl, name, levels, flushed, manifest_token, mem, batch_cap)

# Flush pre for the memtable flush.
def flush_pre(
  +dir: String,
  +entries: List<&2, MemTable.Entry>,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +batch_cap: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  +tbl = Sstable.build(entries, 0n, List.length(&2, MemTable.Entry, entries))
  +name = Policy.table_name(flushed)
  +l0dir = dir ++ "/l0"
  flush_goA(dir, l0dir, l0dir ++ "/" ++ name ++ ".tmp", l0dir ++ "/" ++ name, dir ++ "/MANIFEST", dir ++ "/MANIFEST.tmp", Db.table_entries(tbl), 0, tbl, name, levels, flushed,
  manifest_token, MemTable.MT{Nil{}}, batch_cap)

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
      +name = Policy.table_name(flushed)
      +l0dir = dir ++ "/l0"
      flush_goA(dir, l0dir, l0dir ++ "/" ++ name ++ ".tmp", l0dir ++ "/" ++ name, dir ++ "/MANIFEST", dir ++ "/MANIFEST.tmp", Db.table_entries(tbl), 0, tbl, name, levels, flushed,
      manifest_token, MemTable.MT{Nil{}}, batch_cap)

# Flush pick for the memtable flush.
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

# Handle flush in the memtable flush.
def flush(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      flush_pick(frozen, mem, dir, levels, flushed, manifest_token, batch_cap, bcache)

# --- Closed-vector laws live in laws/Flush.bend (spec law 6) ---
