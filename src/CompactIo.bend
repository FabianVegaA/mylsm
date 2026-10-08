import Base
import ./Compact.bend as Compact
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SstStreamIo.bend as SstStreamIo
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest
import ./Flush.bend as Flush
import ./Fs.bend as Fs
import ./Db.bend as Db
import ./CrashPoint.bend as CrashPoint

# Handle remove list in the compaction filesystem effects.
def remove_list(names: List<&2, String>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match names:
    case Nil{}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
    case Con{n, t}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _rm : Result<&1, &1, U32 & String, Unit> <- Fs.remove(n)
        remove_list(t)

# Tracks progress while removing published files.
type RemoveState is Type:
  RemoveStart{names: List<&2, String>}
  RemoveNames{names: List<&2, String>}
  RemoveResult{result: Result<&1, &1, U32 & String, Unit>, names: List<&2, String>}

# Removes every path and propagates the first failure.
def remove_list_strict(fuel: Nat, state: RemoveState) -> IO(Result<&1, &1, U32 & String, Unit>):
  match fuel:
    case 0n:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{(U32.from_nat(7n), "remove list exhausted")})
    case 1n+rest:
      match state:
        case RemoveStart{names}:
          remove_list_strict(rest, RemoveNames{names})
        case RemoveNames{names}:
          match names:
            case Nil{}:
              IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
            case Con{name, tail}:
              do IO<Result<&1, &1, U32 & String, Unit>>:
                removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(name)
                remove_list_strict(rest, RemoveResult{removed, tail})
        case RemoveResult{result, names}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
            case Done{Unit{}}:
              remove_list_strict(rest, RemoveNames{names})

# Starts checked removal of the published file list.
def remove_list_strict_start(pair: Nat & List<&2, String>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match pair:
    case (fuel, names):
      remove_list_strict(fuel, RemoveStart{names})

def compact_goB.removed(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest: Manifest.Manifest,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>,
        Done{Db.Db{dir, mem, frozen, batch_cap, Nil{}, levels2,
          Nat.add(flushed, 1n), Manifest.token(manifest), mem_count, frozen_count}})

def compact_goB.directory_synced(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +dels: List<&2, String>,
  +m2: Manifest.Manifest,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("compact.manifest_published"))
        removed : Result<&1, &1, U32 & String, Unit> <- remove_list_strict_start((Nat.add(Nat.mul(2n, List.length(&2, String, dels)), 2n), dels))
        compact_goB.removed(removed, dir, mem, levels2, flushed, m2,
          frozen, batch_cap, mem_count, frozen_count)

def compact_goB.renamed(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +dels: List<&2, String>,
  +m2: Manifest.Manifest,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(dir)
        compact_goB.directory_synced(synced, dir, dels, m2, mem, levels2,
          flushed, frozen, batch_cap, mem_count, frozen_count)

def compact_goB.written(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +dels: List<&2, String>,
  +m2: Manifest.Manifest,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("compact.manifest_synced"))
        renamed : Result<&1, &1, U32 & String, Unit> <- Fs.rename(mtmp, mpath)
        compact_goB.renamed(renamed, dir, dels, m2, mem,
          levels2, flushed, frozen, batch_cap, mem_count, frozen_count)

# Compact goB for the compaction filesystem effects.
def compact_goB(
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +m2: Manifest.Manifest,
  +dels: List<&2, String>,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    written : Result<&1, &1, U32 & String, Unit> <- Flush.write_manifest(mtmp, m2)
    compact_goB.written(written, dir, mpath, mtmp, dels, m2, mem, levels2,
      flushed, frozen, batch_cap, mem_count, frozen_count)

# Handle drift go in the compaction filesystem effects.
def drift_go(
  ok: Bool,
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +mfst: Manifest.Manifest,
  +oldl1: List<&2, Sstable.Table>,
  +remt: List<&2, Sstable.Table>,
  +outname: String,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case True{}:
      +new_mfst = Compact.mfst_new(mfst, Compact.rem_names(oldl1, Compact.ml1(mfst), remt), outname)
      +removed = Compact.abs_names(oldl1, Compact.ml1(mfst), remt)
      +dels = List.append(&2, String, Compact.prefix(Compact.ml0(mfst), dir ++ "/l0"), Compact.prefix(removed, dir ++ "/l1"))
      compact_goB(dir, mpath, mtmp, new_mfst, dels, mem, levels2, flushed, frozen, batch_cap, mem_count, frozen_count)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(2n), "manifest drift")})

def compact_goA.loaded(
  result: Result<&1, &1, U32 & String, Manifest.Manifest>,
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +oldl1: List<&2, Sstable.Table>,
  +remt: List<&2, Sstable.Table>,
  +outname: String,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{+manifest}:
      drift_go(String.eq(Manifest.token(manifest), manifest_token), dir, mpath,
        mtmp, manifest, oldl1, remt, outname, mem, levels2, flushed,
        frozen, batch_cap, mem_count, frozen_count)

def compact_goA.synced(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +mpath: String,
  +mtmp: String,
  +oldl1: List<&2, Sstable.Table>,
  +remt: List<&2, Sstable.Table>,
  +outname: String,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("compact.output_published"))
        manifest : Result<&1, &1, U32 & String, Manifest.Manifest> <- Flush.load_mfst(mpath)
        compact_goA.loaded(manifest, dir, mpath, mtmp, oldl1, remt, outname,
          mem, levels2, flushed, manifest_token, frozen, batch_cap, mem_count, frozen_count)

def compact_goA.renamed(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +l1dir: String,
  +mpath: String,
  +mtmp: String,
  +oldl1: List<&2, Sstable.Table>,
  +remt: List<&2, Sstable.Table>,
  +outname: String,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(l1dir)
        compact_goA.synced(synced, dir, mpath, mtmp, oldl1, remt, outname,
          mem, levels2, flushed, manifest_token, frozen, batch_cap, mem_count, frozen_count)

def compact_goA.written(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +l1dir: String,
  +tmp: String,
  +final: String,
  +mpath: String,
  +mtmp: String,
  +oldl1: List<&2, Sstable.Table>,
  +remt: List<&2, Sstable.Table>,
  +outname: String,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        _checkpoint : Unit <- IO.try(Unit, CrashPoint.hit("compact.output_synced"))
        renamed : Result<&1, &1, U32 & String, Unit> <- Fs.rename(tmp, final)
        compact_goA.renamed(renamed, dir, l1dir, mpath, mtmp, oldl1, remt,
          outname, mem, levels2, flushed, manifest_token, frozen, batch_cap, mem_count, frozen_count)

def compact_goA.ensured(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +l1dir: String,
  +tmp: String,
  +final: String,
  +mpath: String,
  +mtmp: String,
  +entries: List<&2, MemTable.Entry>,
  +level: U32,
  +outname: String,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +oldl1: List<&2, Sstable.Table>,
  +remt: List<&2, Sstable.Table>,
  +flushed: Nat,
  +manifest_token: String,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        written : Result<&1, &1, U32 & String, Unit> <- SstStreamIo.write_table(tmp, entries, level)
        compact_goA.written(written, dir, l1dir, tmp, final, mpath, mtmp,
          oldl1, remt, outname, mem, levels2, flushed, manifest_token, frozen,
          batch_cap, mem_count, frozen_count)

# Publishes the compacted run and removes obsolete files.
def compact_goA(
  +dir: String,
  +l1dir: String,
  +tmp: String,
  +final: String,
  +mpath: String,
  +mtmp: String,
  +entries: List<&2, MemTable.Entry>,
  +level: U32,
  +outname: String,
  +mem: MemTable.MemTable,
  +levels2: List<&2, List<&2, Sstable.Table>>,
  +oldl1: List<&2, Sstable.Table>,
  +remt: List<&2, Sstable.Table>,
  +flushed: Nat,
  +manifest_token: String,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    ensured : Result<&1, &1, U32 & String, Unit> <- Flush.ensure_dir(l1dir)
    compact_goA.ensured(ensured, dir, l1dir, tmp, final, mpath, mtmp,
      entries, level, outname, mem, levels2, oldl1, remt, flushed,
      manifest_token, frozen, batch_cap, mem_count, frozen_count)

# Compact pre for the compaction filesystem effects.
def compact_pre(
  +dir: String,
  +mem: MemTable.MemTable,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +mem_count: Nat,
  +frozen_count: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  +levels2 = Compact.compact_levels(levels)
  +newl1 = Compact.l1list(levels2)
  +out = Compact.hd_tbl(newl1)
  +remt = Compact.tail_of(newl1)
  +l1dir = dir ++ "/l1"
  +outname = "l1-" ++ Nat.show(flushed) ++ ".tbl"
  +tmp = l1dir ++ "/" ++ outname ++ ".tmp"
  +final = l1dir ++ "/" ++ outname
  compact_goA(
    dir, l1dir, tmp, final, dir ++ "/MANIFEST", dir ++ "/MANIFEST.tmp",
    Db.table_entries(out), 1, outname, mem, levels2, Compact.l1list(levels), remt, flushed,
    manifest_token, frozen, batch_cap, mem_count, frozen_count,
  )

# Compact trig for the compaction filesystem effects.
def compact_trig(
  gt: Bool,
  +dir: String,
  +mem: MemTable.MemTable,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +bcache: List<&2, Db.BEntry>,
  +mem_count: Nat,
  +frozen_count: Nat,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match gt:
    case True{}:
      compact_pre(dir, mem, levels, flushed, manifest_token, frozen, batch_cap, mem_count, frozen_count)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}})

# Handle compact in the compaction filesystem effects.
def compact(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      match levels:
        case Nil{}:
          IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{Db.Db{dir, mem, frozen, batch_cap, bcache, Nil{}, flushed, manifest_token, mem_count, frozen_count}})
        case Con{+l0, r1}:
          compact_trig(Nat.is_lt(4n, List.length(&2, Sstable.Table, l0)), dir, mem, Con{l0, r1}, flushed, manifest_token, frozen, batch_cap, bcache, mem_count, frozen_count)
