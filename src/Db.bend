import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest

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

# Represent BEntry data used by the database state and operations.
type BEntry is Data:
  BEntry{tab: String, key: String, val: Maybe<&2, String>}

# Return the default batch cap in the database state and operations.
def default_batch_cap() -> Nat:
  1n

# Handle bcache bound in the database state and operations.
def bcache_bound() -> Nat:
  256n

# manifest_token is the exact serialized Manifest observed by this handle. Flush
# and compaction compare it before publication to reject stale-handle drift.
type Db is Data:
  Db{dir: String, mem: MemTable.MemTable, frozen: MemTable.MemTable, batch_cap: Nat, bcache: List<&2, BEntry>, levels: List<&2, List<&2, Sstable.Table>>, flushed: Nat,
  manifest_token: String, mem_count: Nat, frozen_count: Nat}

# Rotation result: both tables plus their exact counts, so no pass ever
# walks a memtable to learn its size. Counts stay exact by construction
# (open_db starts 0/0; every transition does arithmetic, never List.length).
type RotRes is Data:
  Rot{mem: MemTable.MemTable, frozen: MemTable.MemTable, mem_count: Nat, frozen_count: Nat}

# Handle wal path in the database state and operations.
def wal_path(+dir: String) -> String:
  dir ++ "/wal.log"

# Open db for the database state and operations.
def open_db(+dir: String) -> Db:
  Db{dir, MemTable.empty(), MemTable.empty(), default_batch_cap(), Nil{}, Nil{}, 0n, Manifest.token(Manifest.M{Nil{}}), 0n, 0n}

# --- Pure write core (laws below pin batch == sequential) ---

# Apply mut for the database state and operations.
def apply_mut(+mem: MemTable.MemTable, +mut: Wal.Mut) -> MemTable.MemTable:
  match mut:
    case Wal.Put{key, val}:
      MemTable.put(mem, key, val)
    case Wal.Del{key}:
      MemTable.del(mem, key)

# Apply batch for the database state and operations.
def apply_batch(+muts: List<&2, Wal.Mut>, +mem: MemTable.MemTable) -> MemTable.MemTable:
  match muts:
    case Nil{}:
      mem
    case Con{+h, t}:
      apply_batch(t, apply_mut(mem, h))

# --- Pure read core (concat newest-first, first match wins) ---

# Return the table entries for the database state and operations.
def table_entries(+tab: Sstable.Table) -> List<&2, MemTable.Entry>:
  match tab:
    case Sstable.Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      entries

# Return the level entries for the database state and operations.
def level_entries(+tabs: List<&2, Sstable.Table>) -> List<&2, MemTable.Entry>:
  match tabs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      List.append(&2, MemTable.Entry, table_entries(h), level_entries(t))

# Check all level entries for the database state and operations.
def all_level_entries(+lvls: List<&2, List<&2, Sstable.Table>>) -> List<&2, MemTable.Entry>:
  match lvls:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      List.append(&2, MemTable.Entry, level_entries(h), all_level_entries(t))

# Check all entries for the database state and operations.
def all_entries(+db: Db) -> List<&2, MemTable.Entry>:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      match mem:
        case MemTable.MT{entries}:
          List.append(&2, MemTable.Entry, entries, all_level_entries(levels))

# Return the table hit if for the database state and operations.
def table_hit_if(present: Bool, tab: Sstable.Table, +key: String) -> Maybe<&2, Maybe<&2, String>>:
  match present:
    case False{}:
      None{}
    case True{}:
      Sstable.block_get_hit(tab, key)

# Return the table hit for the database state and operations.
def table_hit(+tab: Sstable.Table, +key: String) -> Maybe<&2, Maybe<&2, String>>:
  table_hit_if(Sstable.maybe_present(tab, key), tab, key)

# Return the table s hits for the database state and operations.
def tables_hits(+tabs: List<&2, Sstable.Table>, +key: String) -> List<&2, Maybe<&2, Maybe<&2, String>>>:
  match tabs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Con{table_hit(h, key), tables_hits(t, key)}

# Return the level s hits for the database state and operations.
def levels_hits(+lvls: List<&2, List<&2, Sstable.Table>>, +key: String) -> List<&2, Maybe<&2, Maybe<&2, String>>>:
  match lvls:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      List.append(&2, Maybe<&2, Maybe<&2, String>>, tables_hits(h, key), levels_hits(t, key))

# Resolve the hit for s first for the database state and operations.
def hits_first(+hits: List<&2, Maybe<&2, Maybe<&2, String>>>) -> Maybe<&2, Maybe<&2, String>>:
  match hits:
    case Nil{}:
      None{}
    case Con{None{}, t}:
      hits_first(t)
    case Con{Some{found}, t}:
      Some{found}

# Flatten opt for the database state and operations.
def flatten_opt(+opt: Maybe<&2, Maybe<&2, String>>) -> Maybe<&2, String>:
  match opt:
    case None{}:
      None{}
    case Some{inner}:
      inner

# Handle db get in the database state and operations.
def db_get(+db: Db, +key: String) -> Maybe<&2, String>:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      flatten_opt(hits_first(Con{MemTable.get_hit(mem, key), Con{MemTable.get_hit(frozen, key), levels_hits(levels, key)}}))

# --- Phase A3: table-identity read cache (assoc-list, bounded FIFO) ---
# LRU verdict (spike-by-inspection, 2026-09-25): hub lru has no simple public
# put, reads hand the cache back, and every op needs a W.U64 clock — adopting
# it threads time through the pure read path and changes db_get's shape for a
# marginal gain over this list. Custom assoc-list wins; see the Task 3 commit.

# Select hit for the database state and operations.
def pick_hit(hit: Bool, ans: Maybe<&2, String>, best: Maybe<&2, Maybe<&2, String>>) -> Maybe<&2, Maybe<&2, String>>:
  match hit:
    case True{}:
      Some{ans}
    case False{}:
      best

# Handle bcache go in the database state and operations.
def bcache_go(
  +cache: List<&2, BEntry>,
  +tab: String,
  +key: String,
  +best: Maybe<&2, Maybe<&2, String>>
) -> Maybe<&2, Maybe<&2, String>>:
  match cache:
    case Nil{}:
      best
    case Con{BEntry{t, ky, val}, rest}:
      bcache_go(rest, tab, key, pick_hit(Bool.and(String.eq(t, tab), String.eq(ky, key)), val, best))

# Handle bcache lookup in the database state and operations.
def bcache_lookup(+cache: List<&2, BEntry>, +tab: String, +key: String) -> Maybe<&2, Maybe<&2, String>>:
  bcache_go(cache, tab, key, None{})

# Handle bcache push all in the database state and operations.
def bcache_push_all(+fresh: List<&2, BEntry>, +old: List<&2, BEntry>) -> List<&2, BEntry>:
  List.take(&2, BEntry, List.append(&2, BEntry, fresh, old), bcache_bound())

# Probe fill for the database state and operations.
def probe_fill(
  hit: Maybe<&2, Maybe<&2, String>>,
  +tab: String,
  +key: String
) -> (Maybe<&2, Maybe<&2, String>> & List<&2, BEntry>):
  match hit:
    case None{}:
      (None{}, Nil{})
    case Some{+inner}:
      (Some{inner}, Con{BEntry{tab, key, inner}, Nil{}})

# Probe cached for the database state and operations.
def probe_cached(
  cached: Maybe<&2, Maybe<&2, String>>,
  +tab: Sstable.Table,
  +key: String
) -> (Maybe<&2, Maybe<&2, String>> & List<&2, BEntry>):
  match cached:
    case None{}:
      probe_fill(table_hit(tab, key), Sstable.table_id(tab), key)
    case Some{ans}:
      (Some{ans}, Nil{})

# Return the table probe for the database state and operations.
def table_probe(
  +tab: Sstable.Table,
  +key: String,
  +cache: List<&2, BEntry>
) -> (Maybe<&2, Maybe<&2, String>> & List<&2, BEntry>):
  probe_cached(bcache_lookup(cache, Sstable.table_id(tab), key), tab, key)

# Return the table s cons for the database state and operations.
def tables_cons(
  cur: Maybe<&2, Maybe<&2, String>> & List<&2, BEntry>,
  rest: List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>
) -> List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>:
  match cur:
    case (hit, delta):
      match rest:
        case (rhits, rdelta):
          (Con{hit, rhits}, List.append(&2, BEntry, delta, rdelta))

# Return the table s walk for the database state and operations.
def tables_walk(
  +tabs: List<&2, Sstable.Table>,
  +key: String,
  +cache: List<&2, BEntry>
) -> List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>:
  match tabs:
    case Nil{}:
      (Nil{}, Nil{})
    case Con{+h, t}:
      tables_cons(table_probe(h, key, cache), tables_walk(t, key, cache))

# Return the level s cons for the database state and operations.
def levels_cons(
  cur: List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>,
  rest: List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>
) -> List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>:
  match cur:
    case (chits, cdelta):
      match rest:
        case (rhits, rdelta):
          (List.append(&2, Maybe<&2, Maybe<&2, String>>, chits, rhits), List.append(&2, BEntry, cdelta, rdelta))

# Return the level s cached for the database state and operations.
def levels_cached(
  +lvls: List<&2, List<&2, Sstable.Table>>,
  +key: String,
  +cache: List<&2, BEntry>
) -> List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>:
  match lvls:
    case Nil{}:
      (Nil{}, Nil{})
    case Con{+h, t}:
      levels_cons(tables_walk(h, key, cache), levels_cached(t, key, cache))

# Read the cached levels for the database state and operations.
def cached_levels(
  lr: List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>,
  +dir: String,
  +mem: MemTable.MemTable,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +bcache: List<&2, BEntry>,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +mem_count: Nat,
  +frozen_count: Nat
) -> Db & Maybe<&2, String>:
  match lr:
    case (hits, delta):
      (Db{dir, mem, frozen, batch_cap, bcache_push_all(delta, bcache), levels, flushed, manifest_token, mem_count, frozen_count}, flatten_opt(hits_first(hits)))

# Read the cached frozen for the database state and operations.
def cached_frozen(
  fhit: Maybe<&2, Maybe<&2, String>>,
  +dir: String,
  +mem: MemTable.MemTable,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +bcache: List<&2, BEntry>,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +key: String,
  +mem_count: Nat,
  +frozen_count: Nat
) -> Db & Maybe<&2, String>:
  match fhit:
    case Some{found}:
      (Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}, flatten_opt(Some{found}))
    case None{}:
      cached_levels(levels_cached(levels, key, bcache), dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count)

# Read the cached mem for the database state and operations.
def cached_mem(
  mhit: Maybe<&2, Maybe<&2, String>>,
  +dir: String,
  +mem: MemTable.MemTable,
  +frozen: MemTable.MemTable,
  +batch_cap: Nat,
  +bcache: List<&2, BEntry>,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String,
  +key: String,
  +mem_count: Nat,
  +frozen_count: Nat
) -> Db & Maybe<&2, String>:
  match mhit:
    case Some{found}:
      (Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}, flatten_opt(Some{found}))
    case None{}:
      cached_frozen(MemTable.get_hit(frozen, key), dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, key, mem_count, frozen_count)

# Handle db get cached in the database state and operations.
def db_get_cached(+db: Db, +key: String) -> Db & Maybe<&2, String>:
  match db:
    case Db{dir, +mem, +frozen, +batch_cap, +bcache, +levels, +flushed, +manifest_token, +mem_count, +frozen_count}:
      cached_mem(MemTable.get_hit(mem, key), dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, key, mem_count, frozen_count)

# Handle batch len in the database state and operations.
def batch_len(+muts: List<&2, Wal.Mut>) -> Nat:
  List.length(&2, Wal.Mut, muts)

# Rotate cnt for the database state and operations.
def rotate_cnt(full: Bool, +grown: MemTable.MemTable, +frozen: MemTable.MemTable, +count: Nat, +fcount: Nat) -> RotRes:
  match full:
    case True{}:
      Rot{MemTable.empty(), grown, 0n, count}
    case False{}:
      Rot{grown, frozen, count, fcount}

# Handle frozen empty in the database state and operations.
def frozen_empty(+frozen: MemTable.MemTable) -> Bool:
  match frozen:
    case MemTable.MT{entries}:
      match entries:
        case Nil{}:
          True{}
        case Con{_, _}:
          False{}

# Rotate after for the database state and operations.
def rotate_after(+grown: MemTable.MemTable, +frozen: MemTable.MemTable, +count: Nat, +fcount: Nat) -> RotRes:
  rotate_cnt(Bool.and(Nat.is_le(4096n, count), frozen_empty(frozen)), grown, frozen, count, fcount)

# Apply and rotate for the database state and operations.
def apply_and_rotate(
  +muts: List<&2, Wal.Mut>,
  +mem: MemTable.MemTable,
  +frozen: MemTable.MemTable,
  +mem_count: Nat,
  +frozen_count: Nat
) -> RotRes:
  rotate_after(apply_batch(muts, mem), frozen, Nat.add(mem_count, batch_len(muts)), frozen_count)

# Apply done for the database state and operations.
def apply_done(
  res: RotRes,
  +dir: String,
  +batch_cap: Nat,
  +bcache: List<&2, BEntry>,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String
) -> Db:
  match res:
    case Rot{mem2, frozen2, mc, fc}:
      Db{dir, mem2, frozen2, batch_cap, bcache, levels, flushed, manifest_token, mc, fc}

# Handle rot done in the database state and operations.
def rot_done(
  res: RotRes,
  +dir: String,
  +batch_cap: Nat,
  +bcache: List<&2, BEntry>,
  +levels: List<&2, List<&2, Sstable.Table>>,
  +flushed: Nat,
  +manifest_token: String
) -> Result<&1, &1, U32 & String, Db>:
  Done{apply_done(res, dir, batch_cap, bcache, levels, flushed, manifest_token)}

# Handle batch cap of in the database state and operations.
def batch_cap_of(+db: Db) -> Nat:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      batch_cap

# Handle with batch cap in the database state and operations.
def with_batch_cap(+db: Db, +cap: Nat) -> Db:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db{dir, mem, frozen, cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}

# Stage d muts for the database state and operations.
def staged_muts(+staged: List<&2, Wal.Batch>) -> List<&2, Wal.Mut>:
  match staged:
    case Nil{}:
      Nil{}
    case Con{Wal.Batch{muts}, t}:
      List.append(&2, Wal.Mut, muts, staged_muts(t))

# --- Closed-vector laws live in laws/Db.bend (spec laws 1, 2, 3, 7) ---
