import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SstFile.bend as SstFile
import ./SstFileV2.bend as SstFileV2
import ./SstStream.bend as SstStream
import ./SstStreamIo.bend as SstStreamIo
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest
import ./Flush.bend as Flush
import ./Compact.bend as Compact
import ./CompactIo.bend as CompactIo
import ./Fs.bend as Fs
import ./Db.bend as Db
import ./DbIo.bend as DbIo
import ./RecoverPure.bend as Pure

# Recovery + maintenance (Task 10).
#
# WAL framing v1 (no WAL-codec churn): each appended batch is
# dashes(len) ++ ";" ++ encode(batch). Replay parses frames oldest-first;
# a torn tail (crash mid-append) stops the walk (valid prefix kept) and is
# truncated on open (monotonic truncation to valid frames — safe to retry).
# Single wal.log (appends need no dir-sync: the entry pre-exists).
#
# Open: ensure dir; sweep *.tmp (best-effort); load manifest (absent =
# fresh; corrupt = fatal); shape-check all names; load tables positionally
# (listed-but-missing/corrupt = fatal, never silent); restore the flush
# counter (max dashes + 1 — open_db's 0 would collide); replay + truncate
# the WAL; return the Db.
#
# Maintenance (synchronous, observably identical ordering to background):
# after every acked batch: drain while L0 >= 8 (stall = blocking
# maintenance), flush when mem >= 4096, compact (self-gated at L0 > 4).
# True fork-based background (frozen mem + IO.spawn) is a benchmark-gated
# follow-up; ordering and stall semantics are already exact.

# --- Loaders (self-recursive IO; fatal via IO.die, never silent) ---


def load_tables(names: List<&2, String>, +ldir: String, +dir: String, +acc: List<&2, Sstable.Table>) -> IO(List<&2, Sstable.Table>):
  match names:
    case Nil{}:
      IO.pure(List<&2, Sstable.Table>, List.reverse(&2, Sstable.Table, acc))
    case Con{+n, t}:
      do IO<List<&2, Sstable.Table>>:
        tbl : Sstable.Table <- IO.try(Sstable.Table, SstStreamIo.read_table(dir ++ "/" ++ ldir ++ "/" ++ n))
        load_tables(t, ldir, dir, Con{tbl, acc})

def ldir_io(+opt: Maybe<&2, String>) -> IO(String):
  match opt:
    case None{}:
      IO.die(String, U32.from_nat(4n), "too many levels")
    case Some{d}:
      IO.pure(String, d)

def ldir_of(idx: Nat) -> Maybe<&2, String>:
  match idx:
    case 0n:
      Some{"l0"}
    case 1n+m:
      match m:
        case 0n:
          Some{"l1"}
        case 1n+p:
          match p:
            case 0n:
              Some{"l2"}
            case 1n+q:
              match q:
                case 0n:
                  Some{"l3"}
                case 1n+r:
                  None{}

def load_levels(lvls: List<&2, List<&2, String>>, +idx: Nat, +dir: String, +acc: List<&2, List<&2, Sstable.Table>>) -> IO(List<&2, List<&2, Sstable.Table>>):
  match lvls:
    case Nil{}:
      IO.pure(List<&2, List<&2, Sstable.Table>>, List.reverse(&2, List<&2, Sstable.Table>, acc))
    case Con{ns, t}:
      do IO<List<&2, List<&2, Sstable.Table>>>:
        ld : String <- ldir_io(ldir_of(idx))
        tabs : List<&2, Sstable.Table> <- load_tables(ns, ld, dir, Nil{})
        load_levels(t, Nat.add(idx, 1n), dir, Con{tabs, acc})

# --- WAL open (absent = fresh; torn tail truncated) ---

def trunc_go(short: Bool, +dir: String, +prefix: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match short:
    case True{}:
      Flush.write_file(Db.wal_path(dir), prefix)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})

def mem_tail_snd(+str: String, +dir: String) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  +valid = Pure.replay_valid(str)
  +ln = String.length(str)
  do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
    _u : Unit <- IO.try(Unit, trunc_go(Nat.is_lt(valid, ln), dir, String.take(str, valid)))
    return Done{Pure.replay_mem(str)}

def mem_tail_fst(fr: (File & Result<&1, &1, U32 & String, String>), +dir: String) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match fr:
    case (f3, r1):
      do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
        _cls : Unit <- File.close(f3)
        s : String <- IO.try(String, IO.pure(Result<&1, &1, U32 & String, String>, r1))
        mem_tail_snd(s, dir)

def wal_read(file: File, +dir: String) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
    fr : (File & Result<&1, &1, U32 & String, String>) <- File.read(file, U32.mul(U32.from_nat(1024n), U32.from_nat(1024n)))
    mem_tail_fst(fr, dir)

def wal_open(res: Result<&1, &1, U32 & String, File>, +dir: String) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match res:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Done{Db.Rot{MemTable.empty(), MemTable.empty(), 0n, 0n}})
    case Done{f}:
      wal_read(f, dir)

# --- Tmp sweep (best-effort) ---

def tmp_pick(keep: Bool, +name: String, +acc: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      Con{name, acc}
    case False{}:
      acc

def tmp_some(+ok: Bool, +name: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{name}
    case False{}:
      None{}

def tmp_map_list(xs: List<&1, String>) -> List<&2, Maybe<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Con{tmp_some(String.ends_with(h, ".tmp"), h), tmp_map_list(t)}

def cat_go(xs: List<&2, Maybe<&2, String>>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      match h:
        case None{}:
          cat_go(t)
        case Some{s}:
          Con{s, cat_go(t)}

def tmp_names(xs: List<&1, String>) -> List<&2, String>:
  cat_go(tmp_map_list(xs))

def sweep_one(res: Result<&1, &1, U32 & String, List<String>>, +dir: String) -> IO(Unit):
  match res:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{ns}:
      do IO<Unit>:
        _ign : Result<&1, &1, U32 & String, Unit> <- CompactIo.remove_list(Compact.prefix(tmp_names(ns), dir))
        IO.pure(Unit, Unit{})

def sweep_get(+dir: String, +sub: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, List<String>> <- Fs.read_dir(dir ++ "/" ++ sub)
    sweep_one(r, dir ++ "/" ++ sub)

def sweep_cnt(res: Result<&1, &1, U32 & String, Nat>, +dir: String, +sub: String) -> IO(Unit):
  match res:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{n}:
      sweep_get(dir, sub)

def sweep_dir(+dir: String, +sub: String) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(dir ++ "/" ++ sub)
    sweep_cnt(c, dir, sub)

# --- Open assembly ---

def wal_part(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(Db.wal_path(dir), "r")
    wal_open(r, dir)

def open_assemble(res: Db.RotRes, +dir: String, +mfst: Manifest.Manifest, levels: List<&2, List<&2, Sstable.Table>>) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match res:
    case Db.Rot{mem, frozen, mc, fc}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        return Done{Db.Db{dir, mem, frozen, Db.default_batch_cap(), Nil{}, levels, Pure.count_gen(Pure.mfst_lists(mfst)), Manifest.serialize(mfst), mc, fc}}

def open_levels_checked(ok: Bool, +dir: String, +mfst: Manifest.Manifest, levels: List<&2, List<&2, Sstable.Table>>) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(6n), "overlapping tables in L1+ manifest")})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        res : Db.RotRes <- IO.try(Db.RotRes, wal_part(dir))
        open_assemble(res, dir, mfst, levels)

def open_levels(+dir: String, +mfst: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    +levels : List<&2, List<&2, Sstable.Table>> <- load_levels(Pure.mfst_lists(mfst), 0n, dir, Nil{})
    open_levels_checked(Pure.l1_plus_disjoint(levels), dir, mfst, levels)

def open_names_go(ok: Bool, +dir: String, +mfst: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case True{}:
      open_levels(dir, mfst)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(5n), "bad manifest names")})

def sweep_root_go(+dir: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, List<String>> <- Fs.read_dir(dir)
    sweep_one(r, dir)

def sweep_root_cnt(res: Result<&1, &1, U32 & String, Nat>, +dir: String) -> IO(Unit):
  match res:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{n}:
      sweep_root_go(dir)

def sweep_root(+dir: String) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(dir)
    sweep_root_cnt(c, dir)

def open_db(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    _u0 : Unit <- IO.try(Unit, Flush.ensure_dir(dir))
    _s0 : Unit <- sweep_dir(dir, "l0")
    _s1 : Unit <- sweep_dir(dir, "l1")
    _s2 : Unit <- sweep_dir(dir, "l2")
    _s3 : Unit <- sweep_dir(dir, "l3")
    _s4 : Unit <- sweep_root(dir)
    +m : Manifest.Manifest <- IO.try(Manifest.Manifest, Flush.load_mfst(dir ++ "/MANIFEST"))
    open_names_go(Pure.manifest_names_ok(Pure.mfst_lists(m), 0n), dir, m)

# --- Maintenance (synchronous auto flush/compact + stall) ---
# One drain round always suffices (L0 >= 8 > 4, so the gated compaction
# fires and empties L0) — no loop, no cycle.

def flush_dec(full: Bool, +db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match full:
    case True{}:
      Flush.flush(db)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{db})

def flush_gate(db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, +mem_count, frozen_count}:
      flush_dec(Nat.is_lt(4096n, mem_count), Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count})

def l0_full(db: Db.Db) -> Bool:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Nat.is_lt(7n, List.length(&2, Sstable.Table, Compact.l0list(levels)))

def drain_once(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    f : Db.Db <- IO.try(Db.Db, Flush.flush(db))
    c : Db.Db <- IO.try(Db.Db, CompactIo.compact(f))
    return Done{c}

def drain_pick(full: Bool, +db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match full:
    case True{}:
      drain_once(db)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{db})

def drain_go(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  drain_pick(l0_full(db), db)

def maintain(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    d : Db.Db <- IO.try(Db.Db, drain_go(db))
    f : Db.Db <- IO.try(Db.Db, flush_gate(d))
    CompactIo.compact(f)

def maintain_unwrap(res: Result<&1, &1, U32 & String, Db.Db>) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match res:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{e})
    case Done{db}:
      maintain(db)

def write(+db: Db.Db, +batch: Wal.Batch) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    r : Result<&1, &1, U32 & String, Db.Db> <- DbIo.db_write(db, batch)
    maintain_unwrap(r)

def put(+db: Db.Db, +key: String, +val: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  write(db, Wal.Batch{Con{Wal.Put{key, val}, Nil{}}})

def del(+db: Db.Db, +key: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  write(db, Wal.Batch{Con{Wal.Del{key}, Nil{}}})

# --- Closed-vector laws live in laws/Recover.bend (spec law 7) ---
