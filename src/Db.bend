import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./Wal.bend as Wal
import ./Fs.bend as Fs
import ./Manifest.bend as Manifest
import ./Decimal.bend as Decimal
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
  Db{dir: String, mem: MemTable.MemTable, frozen: MemTable.MemTable, batch_cap: Nat, bcache: List<&2, BEntry>, levels: List<&2, List<&2, Sstable.Table>>, flushed: Nat, manifest_token: String, mem_count: Nat, frozen_count: Nat}

# Rotation result: both tables plus their exact counts, so no pass ever
# walks a memtable to learn its size. Counts stay exact by construction
# (open_db starts 0/0; every transition does arithmetic, never List.length).
type RotRes is Data:
  Rot{mem: MemTable.MemTable, frozen: MemTable.MemTable, mem_count: Nat, frozen_count: Nat}

def wal_path(+dir: String) -> String:
  dir ++ "/wal.log"

def open_db(+dir: String) -> Db:
  Db{dir, MemTable.empty(), MemTable.empty(), default_batch_cap(), Nil{}, Nil{}, 0n, Manifest.serialize(Manifest.M{Nil{}}), 0n, 0n}

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
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
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
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      flatten_opt(hits_first(Con{MemTable.get_hit(mem, key), Con{MemTable.get_hit(frozen, key), levels_hits(levels, key)}}))

# --- Phase A3: table-identity read cache (assoc-list, bounded FIFO) ---
# LRU verdict (spike-by-inspection, 2026-09-25): hub lru has no simple public
# put, reads hand the cache back, and every op needs a W.U64 clock — adopting
# it threads time through the pure read path and changes db_get's shape for a
# marginal gain over this list. Custom assoc-list wins; see the Task 3 commit.

def pick_hit(hit: Bool, ans: Maybe<&2, String>, best: Maybe<&2, Maybe<&2, String>>) -> Maybe<&2, Maybe<&2, String>>:
  match hit:
    case True{}:
      Some{ans}
    case False{}:
      best

def bcache_go(+cache: List<&2, BEntry>, +tab: String, +key: String, +best: Maybe<&2, Maybe<&2, String>>) -> Maybe<&2, Maybe<&2, String>>:
  match cache:
    case Nil{}:
      best
    case Con{BEntry{t, ky, val}, rest}:
      bcache_go(rest, tab, key, pick_hit(Bool.and(String.eq(t, tab), String.eq(ky, key)), val, best))

def bcache_lookup(+cache: List<&2, BEntry>, +tab: String, +key: String) -> Maybe<&2, Maybe<&2, String>>:
  bcache_go(cache, tab, key, None{})

def bcache_push_all(+fresh: List<&2, BEntry>, +old: List<&2, BEntry>) -> List<&2, BEntry>:
  List.take(&2, BEntry, List.append(&2, BEntry, fresh, old), bcache_bound())

def probe_fill(hit: Maybe<&2, Maybe<&2, String>>, +tab: String, +key: String) -> (Maybe<&2, Maybe<&2, String>> & List<&2, BEntry>):
  match hit:
    case None{}:
      (None{}, Nil{})
    case Some{+inner}:
      (Some{inner}, Con{BEntry{tab, key, inner}, Nil{}})

def probe_cached(cached: Maybe<&2, Maybe<&2, String>>, +tab: Sstable.Table, +key: String) -> (Maybe<&2, Maybe<&2, String>> & List<&2, BEntry>):
  match cached:
    case None{}:
      probe_fill(table_hit(tab, key), Sstable.table_id(tab), key)
    case Some{ans}:
      (Some{ans}, Nil{})

def table_probe(+tab: Sstable.Table, +key: String, +cache: List<&2, BEntry>) -> (Maybe<&2, Maybe<&2, String>> & List<&2, BEntry>):
  probe_cached(bcache_lookup(cache, Sstable.table_id(tab), key), tab, key)

def tables_cons(cur: (Maybe<&2, Maybe<&2, String>> & List<&2, BEntry>), rest: (List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>)) -> (List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>):
  match cur:
    case (hit, delta):
      match rest:
        case (rhits, rdelta):
          (Con{hit, rhits}, List.append(&2, BEntry, delta, rdelta))

def tables_walk(+tabs: List<&2, Sstable.Table>, +key: String, +cache: List<&2, BEntry>) -> (List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>):
  match tabs:
    case Nil{}:
      (Nil{}, Nil{})
    case Con{+h, t}:
      tables_cons(table_probe(h, key, cache), tables_walk(t, key, cache))

def levels_cons(cur: (List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>), rest: (List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>)) -> (List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>):
  match cur:
    case (chits, cdelta):
      match rest:
        case (rhits, rdelta):
          (List.append(&2, Maybe<&2, Maybe<&2, String>>, chits, rhits), List.append(&2, BEntry, cdelta, rdelta))

def levels_cached(+lvls: List<&2, List<&2, Sstable.Table>>, +key: String, +cache: List<&2, BEntry>) -> (List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>):
  match lvls:
    case Nil{}:
      (Nil{}, Nil{})
    case Con{+h, t}:
      levels_cons(tables_walk(h, key, cache), levels_cached(t, key, cache))

def cached_levels(lr: (List<&2, Maybe<&2, Maybe<&2, String>>> & List<&2, BEntry>), +dir: String, +mem: MemTable.MemTable, +frozen: MemTable.MemTable, +batch_cap: Nat, +bcache: List<&2, BEntry>, +levels: List<&2, List<&2, Sstable.Table>>, +flushed: Nat, +manifest_token: String, +mem_count: Nat, +frozen_count: Nat) -> Db & Maybe<&2, String>:
  match lr:
    case (hits, delta):
      (Db{dir, mem, frozen, batch_cap, bcache_push_all(delta, bcache), levels, flushed, manifest_token, mem_count, frozen_count}, flatten_opt(hits_first(hits)))

def cached_frozen(fhit: Maybe<&2, Maybe<&2, String>>, +dir: String, +mem: MemTable.MemTable, +frozen: MemTable.MemTable, +batch_cap: Nat, +bcache: List<&2, BEntry>, +levels: List<&2, List<&2, Sstable.Table>>, +flushed: Nat, +manifest_token: String, +key: String, +mem_count: Nat, +frozen_count: Nat) -> Db & Maybe<&2, String>:
  match fhit:
    case Some{found}:
      (Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}, flatten_opt(Some{found}))
    case None{}:
      cached_levels(levels_cached(levels, key, bcache), dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count)

def cached_mem(mhit: Maybe<&2, Maybe<&2, String>>, +dir: String, +mem: MemTable.MemTable, +frozen: MemTable.MemTable, +batch_cap: Nat, +bcache: List<&2, BEntry>, +levels: List<&2, List<&2, Sstable.Table>>, +flushed: Nat, +manifest_token: String, +key: String, +mem_count: Nat, +frozen_count: Nat) -> Db & Maybe<&2, String>:
  match mhit:
    case Some{found}:
      (Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}, flatten_opt(Some{found}))
    case None{}:
      cached_frozen(MemTable.get_hit(frozen, key), dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, key, mem_count, frozen_count)

def db_get_cached(+db: Db, +key: String) -> Db & Maybe<&2, String>:
  match db:
    case Db{dir, +mem, +frozen, +batch_cap, +bcache, +levels, +flushed, +manifest_token, +mem_count, +frozen_count}:
      cached_mem(MemTable.get_hit(mem, key), dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, key, mem_count, frozen_count)

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

def batch_len(+muts: List<&2, Wal.Mut>) -> Nat:
  List.length(&2, Wal.Mut, muts)

def rotate_cnt(full: Bool, +grown: MemTable.MemTable, +frozen: MemTable.MemTable, +count: Nat, +fcount: Nat) -> RotRes:
  match full:
    case True{}:
      Rot{MemTable.empty(), grown, 0n, count}
    case False{}:
      Rot{grown, frozen, count, fcount}

def frozen_empty(+frozen: MemTable.MemTable) -> Bool:
  match frozen:
    case MemTable.MT{entries}:
      match entries:
        case Nil{}:
          True{}
        case Con{_, _}:
          False{}

def rotate_after(+grown: MemTable.MemTable, +frozen: MemTable.MemTable, +count: Nat, +fcount: Nat) -> RotRes:
  rotate_cnt(Bool.and(Nat.is_le(4096n, count), frozen_empty(frozen)), grown, frozen, count, fcount)

def apply_and_rotate(+muts: List<&2, Wal.Mut>, +mem: MemTable.MemTable, +frozen: MemTable.MemTable, +mem_count: Nat, +frozen_count: Nat) -> RotRes:
  rotate_after(apply_batch(muts, mem), frozen, Nat.add(mem_count, batch_len(muts)), frozen_count)

def apply_done(res: RotRes, +dir: String, +batch_cap: Nat, +bcache: List<&2, BEntry>, +levels: List<&2, List<&2, Sstable.Table>>, +flushed: Nat, +manifest_token: String) -> Db:
  match res:
    case Rot{mem2, frozen2, mc, fc}:
      Db{dir, mem2, frozen2, batch_cap, bcache, levels, flushed, manifest_token, mc, fc}

def rot_done(res: RotRes, +dir: String, +batch_cap: Nat, +bcache: List<&2, BEntry>, +levels: List<&2, List<&2, Sstable.Table>>, +flushed: Nat, +manifest_token: String) -> Result<&1, &1, U32 & String, Db>:
  Done{apply_done(res, dir, batch_cap, bcache, levels, flushed, manifest_token)}

def db_write(+db: Db, +batch: Wal.Batch) -> IO(Result<&1, &1, U32 & String, Db>):
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      match batch:
        case Wal.Batch{muts}:
          do IO<Result<&1, &1, U32 & String, Db>>:
            _res : Unit <- IO.try(Unit, wal_append(dir, Wal.encode(Wal.Batch{muts})))
            return rot_done(apply_and_rotate(muts, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

def db_put(+db: Db, +key: String, +val: String) -> IO(Result<&1, &1, U32 & String, Db>):
  db_write(db, Wal.Batch{Con{Wal.Put{key, val}, Nil{}}})

def batch_cap_of(+db: Db) -> Nat:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      batch_cap

def with_batch_cap(+db: Db, +cap: Nat) -> Db:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db{dir, mem, frozen, cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}

def staged_muts(+staged: List<&2, Wal.Batch>) -> List<&2, Wal.Mut>:
  match staged:
    case Nil{}:
      Nil{}
    case Con{Wal.Batch{muts}, t}:
      List.append(&2, Wal.Mut, muts, staged_muts(t))

def db_write_staged(+db: Db, +staged: List<&2, Wal.Batch>) -> IO(Result<&1, &1, U32 & String, Db>):
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      db_write(Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}, Wal.Batch{staged_muts(List.reverse(&2, Wal.Batch, staged))})

def db_del(+db: Db, +key: String) -> IO(Result<&1, &1, U32 & String, Db>):
  db_write(db, Wal.Batch{Con{Wal.Del{key}, Nil{}}})

# --- reopen (public API v0.3.2.0): WAL-only recovery over wal.log ---
# Checks wal.log existence; missing dir/file = open_db (empty tables).
# Present file is read positionally by chunks, concatenated, split into
# wal_frame frames (dashes(len) ++ ";" ++ data), each payload decoded with
# Wal.decode (checksum-validated). A torn/corrupt final suffix from a
# mid-append crash is discarded; valid batches apply in order over an empty
# memtable via apply_batch. Read errors propagate as Fail.

def reopen_chunk_chars() -> Nat:
  1048576n

type ReChunk is Data:
  ReChunk{bytes: Nat, text: String}

def reopen_chunk_parse(pair: Decimal.Parse) -> Result<&1, &1, U32 & String, ReChunk>:
  match pair:
    case Decimal.Rejected{error}:
      Fail{(U32.from_nat(8n), "bad UTF-8 chunk envelope")}
    case Decimal.Accepted{Decimal.Dec{value, rest}}:
      Done{ReChunk{value, rest}}

def reopen_dash_step(+done: Bool, isdash: Bool, +acc: Nat) -> (Bool & Nat):
  match done:
    case True{}:
      (True{}, acc)
    case False{}:
      match isdash:
        case True{}:
          (False{}, Nat.add(1n, acc))
        case False{}:
          (True{}, acc)

def reopen_dash_snd(st: (Bool & Nat)) -> Nat:
  match st:
    case (d, a):
      a

def reopen_dash_fst(st: (Bool & Nat), +ch: Char) -> (Bool & Nat):
  match st:
    case (done, acc):
      reopen_dash_step(done, Char.is_eq(ch, Char.from_u32(45)), acc)

def reopen_dash_go(fuel: Nat, st: (Bool & Nat), str: String) -> Nat:
  match fuel:
    case 0n:
      reopen_dash_snd(st)
    case 1n+f:
      match str:
        case SNil{}:
          reopen_dash_snd(st)
        case SCon{h, t}:
          reopen_dash_go(f, reopen_dash_fst(st, h), t)

def reopen_dashes_len(+str: String) -> Nat:
  reopen_dash_go(Nat.add(String.length(str), 1n), (False{}, 0n), str)

def reopen_semi_is(eq: Bool, +num: Nat) -> Maybe<&2, Nat>:
  match eq:
    case True{}:
      Some{num}
    case False{}:
      None{}

def reopen_semi(+ch: Char, +num: Nat) -> Maybe<&2, Nat>:
  reopen_semi_is(Char.is_eq(ch, Char.from_u32(59)), num)

def reopen_semi_go(dropped: String, +num: Nat) -> Maybe<&2, Nat>:
  match dropped:
    case SNil{}:
      None{}
    case SCon{h, t}:
      reopen_semi(h, num)

def reopen_frame_len(+str: String) -> Maybe<&2, Nat>:
  +num = reopen_dashes_len(str)
  reopen_semi_go(String.drop(str, num), num)

def reopen_consumed(+num: Nat) -> Nat:
  Nat.add(String.length(Wal.dashes(num)), Nat.add(1n, num))

def reopen_clip(+mlen: Maybe<&2, Nat>, +str: String) -> String:
  match mlen:
    case None{}:
      str
    case Some{n}:
      String.take(String.drop(str, Nat.add(String.length(Wal.dashes(n)), 1n)), n)

def reopen_drop(+mlen: Maybe<&2, Nat>, +str: String) -> String:
  match mlen:
    case None{}:
      str
    case Some{n}:
      String.drop(str, reopen_consumed(n))

def reopen_dec_apply(+m2: Maybe<&2, Wal.Batch>, +res: MemTable.MemTable) -> MemTable.MemTable:
  match m2:
    case None{}:
      res
    case Some{Wal.Batch{muts}}:
      apply_batch(muts, res)

def reopen_replay_go(fuel: Nat, +mem: MemTable.MemTable, +str: String) -> MemTable.MemTable:
  match fuel:
    case 0n:
      mem
    case 1n+g:
      +fl = reopen_frame_len(str)
      reopen_replay_go(g, reopen_dec_apply(Wal.decode(reopen_clip(fl, str)), mem), reopen_drop(fl, str))

def reopen_replay(+str: String) -> MemTable.MemTable:
  reopen_replay_go(Nat.add(String.length(str), 1n), MemTable.empty(), str)

def reopen_assemble(+mem: MemTable.MemTable, +dir: String) -> Db:
  Db{dir, mem, MemTable.empty(), default_batch_cap(), Nil{}, Nil{}, 0n, Manifest.serialize(Manifest.M{Nil{}}), MemTable.count(mem), 0n}

# Chunked WAL reader (SstStream.stream_loop shape): the freshly read chunk
# re-enters as the `pending` parameter, so every match scrutinee is a
# parameter or field and the loop is a single self-recursive def.
def reopen_read_loop(chunks_left: Nat, +path: String, +offset: Nat, +acc: String, pending: Maybe<&2, ReChunk>) -> IO(Result<&1, &1, U32 & String, String>):
  match chunks_left pending:
    case 0n _:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{(U32.from_nat(7n), "wal exceeds streaming read limit")})
    case 1n+rest None{}:
      do IO<Result<&1, &1, U32 & String, String>>:
        raw : String <- IO.try(String, Fs.read_utf8_chunk(path, offset, reopen_chunk_chars()))
        chunk : ReChunk <- IO.try(ReChunk, IO.pure(Result<&1, &1, U32 & String, ReChunk>, reopen_chunk_parse(Decimal.parse_semicolon(raw, reopen_chunk_chars()))))
        reopen_read_loop(rest, path, offset, acc, Some{chunk})
    case 1n+rest Some{ReChunk{bytes, text}}:
      match bytes:
        case 0n:
          IO.pure(Result<&1, &1, U32 & String, String>, Done{acc})
        case 1n+more:
          reopen_read_loop(rest, path, Nat.add(offset, 1n+more), acc ++ text, None{})

def reopen_read(+dir: String) -> IO(Result<&1, &1, U32 & String, Db>):
  do IO<Result<&1, &1, U32 & String, Db>>:
    content : String <- IO.try(String, reopen_read_loop(8192n, wal_path(dir), 0n, "", None{}))
    return Done{reopen_assemble(reopen_replay(content), dir)}

def reopen_exists(ok: Result<&1, &1, U32 & String, Bool>, +dir: String) -> IO(Result<&1, &1, U32 & String, Db>):
  match ok:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Db>, Fail{e})
    case Done{present}:
      match present:
        case False{}:
          IO.pure(Result<&1, &1, U32 & String, Db>, Done{open_db(dir)})
        case True{}:
          reopen_read(dir)

def reopen(+dir: String) -> IO(Result<&1, &1, U32 & String, Db>):
  do IO<Result<&1, &1, U32 & String, Db>>:
    r : Result<&1, &1, U32 & String, Bool> <- Fs.exists(wal_path(dir))
    reopen_exists(r, dir)

# --- Closed-vector laws live in laws/Db.bend (spec laws 1, 2, 3, 7) ---
