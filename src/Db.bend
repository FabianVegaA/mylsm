import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./Wal.bend as Wal
import ./Fs.bend as Fs
import ./Manifest.bend as Manifest
import ./CrashPoint.bend as CrashPoint

# Db API (Task 7): durable write path + reads.
#
# Write path (durability ordering, the load-bearing property): encode the
# batch -> append the WAL -> fsync -> THEN update mem. A crash before fsync
# loses at most unacked writes (recovery replays the WAL prefix, Task 10).
# This ordering is a code-review property (no law over IO exists); Task 12
# fault-injection crashes between each step to verify it empirically.
# CrashPoint calls are test-only host effects. Unset or unequal checkpoints are
# successful no-ops; signal delivery and filesystem ordering are not Bend proofs.
#
# Read path: mem (newest-first) ++ L0 newest-first ++ L1 ... — first match
# wins INCLUDING tombstones (MemTable.scan_go freezes), so deletes can never
# resurrect older versions. Cross-level newest-first order is CORRECT iff
# Task 9 maintains the L0-drain invariant: compaction always drains ALL of
# L0 (inputs deleted), so every L0 table is strictly newer than every L1+
# table; within a level, tables are stored newest-first. Flush (Task 8)
# Cons'es new tables at the head; compaction (Task 9) preserves the order.

type BEntry is Data:
  BEntry{tab: String, key: String, val: Maybe<&2, String>}

def default_batch_cap() -> Nat:
  1n

def bcache_bound() -> Nat:
  256n

# manifest_token is the exact serialized Manifest observed by this handle. Flush
# and compaction compare it before publication to reject stale-handle drift.
type Db is Data:
  Db{dir: String, mem: MemTable.MemTable, frozen: MemTable.MemTable, batch_cap: Nat, bcache: List<&2, BEntry>, levels: List<&2, List<&2, Sstable.Table>>, flushed: Nat, manifest_token: String}

def wal_path(+dir: String) -> String:
  dir ++ "/wal.log"

def open_db(+dir: String) -> Db:
  Db{dir, MemTable.empty(), MemTable.empty(), default_batch_cap(), Nil{}, Nil{}, 0n, Manifest.serialize(Manifest.M{Nil{}})}

# --- Pure write core (laws below pin batch == sequential) ---

def apply_mut(+mem: MemTable.MemTable, +mut: Wal.Mut) -> MemTable.MemTable:
  match mut:
    case Wal.Put{key, val}:
      MemTable.put(mem, key, val)
    case Wal.Del{key}:
      MemTable.del(mem, key)

def apply_batch(+muts: List<&2, Wal.Mut>, +mem: MemTable.MemTable) -> MemTable.MemTable:
  match muts:
    case Nil{}:
      mem
    case Con{+h, t}:
      apply_batch(t, apply_mut(mem, h))

# --- Pure read core (concat newest-first, first match wins) ---

def table_entries(+tab: Sstable.Table) -> List<&2, MemTable.Entry>:
  match tab:
    case Sstable.Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      entries

def level_entries(+tabs: List<&2, Sstable.Table>) -> List<&2, MemTable.Entry>:
  match tabs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      List.append(&2, MemTable.Entry, table_entries(h), level_entries(t))

def all_level_entries(+lvls: List<&2, List<&2, Sstable.Table>>) -> List<&2, MemTable.Entry>:
  match lvls:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      List.append(&2, MemTable.Entry, level_entries(h), all_level_entries(t))

def all_entries(+db: Db) -> List<&2, MemTable.Entry>:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      match mem:
        case MemTable.MT{entries}:
          List.append(&2, MemTable.Entry, entries, all_level_entries(levels))

def table_hit_if(present: Bool, tab: Sstable.Table, +key: String) -> Maybe<&2, Maybe<&2, String>>:
  match present:
    case False{}:
      None{}
    case True{}:
      Sstable.block_get_hit(tab, key)

def table_hit(+tab: Sstable.Table, +key: String) -> Maybe<&2, Maybe<&2, String>>:
  table_hit_if(Sstable.maybe_present(tab, key), tab, key)

def tables_hits(+tabs: List<&2, Sstable.Table>, +key: String) -> List<&2, Maybe<&2, Maybe<&2, String>>>:
  match tabs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Con{table_hit(h, key), tables_hits(t, key)}

def levels_hits(+lvls: List<&2, List<&2, Sstable.Table>>, +key: String) -> List<&2, Maybe<&2, Maybe<&2, String>>>:
  match lvls:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      List.append(&2, Maybe<&2, Maybe<&2, String>>, tables_hits(h, key), levels_hits(t, key))

def hits_first(+hits: List<&2, Maybe<&2, Maybe<&2, String>>>) -> Maybe<&2, Maybe<&2, String>>:
  match hits:
    case Nil{}:
      None{}
    case Con{None{}, t}:
      hits_first(t)
    case Con{Some{found}, t}:
      Some{found}

def flatten_opt(+opt: Maybe<&2, Maybe<&2, String>>) -> Maybe<&2, String>:
  match opt:
    case None{}:
      None{}
    case Some{inner}:
      inner

def db_get(+db: Db, +key: String) -> Maybe<&2, String>:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      flatten_opt(hits_first(Con{MemTable.get_hit(mem, key), Con{MemTable.get_hit(frozen, key), levels_hits(levels, key)}}))

# WAL framing v1 is applied here (see Recover): each batch is stored as
# dashes(len) ++ ";" ++ encode(batch) so replay can stream frames and
# truncate a torn tail. Files are permissioned 0600 at creation.
def wal_frame(+data: String) -> String:
  Wal.dashes(String.length(data)) ++ ";" ++ data

# Tail of the append: match heads the def body (params always
# destructurable), so the write's pair splits with single uses.
def wal_tail(fr: (File & Result<&1, &1, U32 & String, Unit>), +dir: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match fr:
    case (f2, r):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        res : Unit <- IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, r))
        _cp1 : Unit <- IO.try(Unit, CrashPoint.hit("wal.appended"))
        _cls : Unit <- File.close(f2)
        _syn : Unit <- IO.try(Unit, Fs.fsync(wal_path(dir)))
        _cp2 : Unit <- IO.try(Unit, CrashPoint.hit("wal.synced"))
        _prm : Unit <- IO.try(Unit, Fs.chmod(wal_path(dir), U32.from_nat(384n)))
        return Done{res}

def wal_append(+dir: String, +data: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    f : File <- IO.try(File, File.open(wal_path(dir), "a"))
    fr : (File & Result<&1, &1, U32 & String, Unit>) <- File.write(f, wal_frame(data))
    wal_tail(fr, dir)

def db_write(+db: Db, +batch: Wal.Batch) -> IO(Result<&1, &1, U32 & String, Db>):
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      match batch:
        case Wal.Batch{muts}:
          do IO<Result<&1, &1, U32 & String, Db>>:
            _res : Unit <- IO.try(Unit, wal_append(dir, Wal.encode(Wal.Batch{muts})))
            return Done{Db{dir, apply_batch(muts, mem), frozen, batch_cap, bcache, levels, flushed, manifest_token}}

def db_put(+db: Db, +key: String, +val: String) -> IO(Result<&1, &1, U32 & String, Db>):
  db_write(db, Wal.Batch{Con{Wal.Put{key, val}, Nil{}}})

def db_del(+db: Db, +key: String) -> IO(Result<&1, &1, U32 & String, Db>):
  db_write(db, Wal.Batch{Con{Wal.Del{key}, Nil{}}})

# --- Closed-vector laws live in laws/Db.bend (spec laws 1, 2, 3, 7) ---
