import Base
import ./Compact.bend as Compact
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SstFile.bend as SstFile
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest
import ./Flush.bend as Flush
import ./Fs.bend as Fs
import ./Db.bend as Db
import ./CrashPoint.bend as CrashPoint

def remove_list(names: List<&2, String>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match names:
    case Nil{}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
    case Con{n, t}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _rm : Result<&1, &1, U32 & String, Unit> <- Fs.remove(n)
        remove_list(t)

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
    _v1 : Unit <- IO.try(Unit, Flush.write_file(mtmp, Manifest.serialize(m2)))
    _cp1 : Unit <- IO.try(Unit, CrashPoint.hit("compact.manifest_synced"))
    _v2 : Unit <- IO.try(Unit, Fs.rename(mtmp, mpath))
    _v3 : Unit <- IO.try(Unit, Fs.fsync(dir))
    _cp2 : Unit <- IO.try(Unit, CrashPoint.hit("compact.manifest_published"))
    _ign : Result<&1, &1, U32 & String, Unit> <- remove_list(dels)
    return Done{Db.Db{dir, mem, frozen, batch_cap, Nil{}, levels2, Nat.add(flushed, 1n), Manifest.serialize(m2), mem_count, frozen_count}}

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

def compact_goA(
  +dir: String,
  +l1dir: String,
  +tmp: String,
  +final: String,
  +mpath: String,
  +mtmp: String,
  +content: String,
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
    _u1 : Unit <- IO.try(Unit, Flush.ensure_dir(l1dir))
    _u2 : Unit <- IO.try(Unit, Flush.write_file(tmp, content))
    _cp1 : Unit <- IO.try(Unit, CrashPoint.hit("compact.output_synced"))
    _u3 : Unit <- IO.try(Unit, Fs.rename(tmp, final))
    _u4 : Unit <- IO.try(Unit, Fs.fsync(l1dir))
    _cp2 : Unit <- IO.try(Unit, CrashPoint.hit("compact.output_published"))
    +m : Manifest.Manifest <- IO.try(Manifest.Manifest, Flush.load_mfst(mpath))
    drift_go(String.eq(Manifest.serialize(m), manifest_token), dir, mpath, mtmp, m, oldl1, remt, outname, mem, levels2, flushed, frozen, batch_cap, mem_count, frozen_count)

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
  +content = SstFile.serialize(Db.table_entries(out), 1n)
  compact_goA(
    dir, l1dir, tmp, final, dir ++ "/MANIFEST", dir ++ "/MANIFEST.tmp",
    content, outname, mem, levels2, Compact.l1list(levels), remt, flushed,
    manifest_token, frozen, batch_cap, mem_count, frozen_count,
  )

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

def compact(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      match levels:
        case Nil{}:
          IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{Db.Db{dir, mem, frozen, batch_cap, bcache, Nil{}, flushed, manifest_token, mem_count, frozen_count}})
        case Con{+l0, r1}:
          compact_trig(Nat.is_lt(4n, List.length(&2, Sstable.Table, l0)), dir, mem, Con{l0, r1}, flushed, manifest_token, frozen, batch_cap, bcache, mem_count, frozen_count)
