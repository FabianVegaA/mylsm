import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/Wal.bend as Wal
import ../src/Db.bend as Db

# Small local fixture duplicated from the WAL domain for recovery composition.
def batch_multi() -> Wal.Batch:
  Wal.Batch{Con{Wal.Put{"a", ""}, Con{Wal.Del{"b"}, Con{Wal.Put{"", "c"}, Nil{}}}}}

# --- Db write path (Task 7): closed vectors (spec laws 1, 2, 3, 7) ---
# IO itself is unprovable; the laws pin the pure core (batch application,
# replay) that the IO path must funnel through after fsync.

def db_muts1() -> List<&2, Wal.Mut>:
  Con{Wal.Put{"k", "v"}, Nil{}}

def db_muts2() -> List<&2, Wal.Mut>:
  Con{Wal.Put{"a", "1"}, Con{Wal.Del{"b"}, Con{Wal.Put{"c", "3"}, Nil{}}}}

def db_mem2() -> MemTable.MemTable:
  MemTable.MT{Con{MemTable.Entry{"c", Some{"3"}}, Con{MemTable.Entry{"b", None{}}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}}}

def batch_muts(+batch: Wal.Batch) -> List<&2, Wal.Mut>:
  match batch:
    case Wal.Batch{m}:
      m

def db_decoded(+batch: Wal.Batch) -> Maybe<&2, Wal.Batch>:
  Wal.decode(Wal.encode(batch))

def db_replay_go(+opt: Maybe<&2, Wal.Batch>) -> MemTable.MemTable:
  match opt:
    case None{}:
      MemTable.empty()
    case Some{Wal.Batch{muts}}:
      Db.apply_batch(muts, MemTable.empty())

def db_replay(+batch: Wal.Batch) -> MemTable.MemTable:
  db_replay_go(db_decoded(batch))

# LAW: read-your-writes through batch application (closed)
law db_ryw:
  {MemTable.get(Db.apply_batch(db_muts1(), MemTable.empty()), "k") == Some{"v"} : Maybe<&2, String>}

# LAW: delete hides through batch application (closed)
law db_del:
  {MemTable.get(Db.apply_batch(Con{Wal.Del{"k"}, Nil{}}, Db.apply_batch(db_muts1(), MemTable.empty())), "k") == None{} : Maybe<&2, String>}

# LAW: batch applies as one atomic sequential transition (closed)
law db_batch_atomic:
  {Db.apply_batch(db_muts2(), MemTable.empty()) == db_mem2() : MemTable.MemTable}

# LAW: recovery replay equals direct application (closed; composes wal_rt)
law db_recover:
  {db_replay(batch_multi()) == Db.apply_batch(batch_muts(batch_multi()), MemTable.empty()) : MemTable.MemTable}

# --- db_get per-source search (Phase A2): closed vectors ---

def two_level_db() -> Db.Db:
  Db.Db{"/d", MemTable.MT{Con{MemTable.Entry{"m", Some{"mv"}}, Nil{}}}, MemTable.MT{Nil{}}, 1n, Nil{}, Con{Con{Sstable.build(Con{MemTable.Entry{"l0", Some{"l0v"}}, Nil{}}, 0n, 1n), Nil{}}, Con{Con{Sstable.build(Con{MemTable.Entry{"l1", Some{"l1v"}}, Nil{}}, 0n, 1n), Nil{}}, Nil{}}}, 2n, "", 1n, 0n}

def tomb_db() -> Db.Db:
  Db.Db{"/d", MemTable.MT{Con{MemTable.Entry{"x", None{}}, Nil{}}}, MemTable.MT{Nil{}}, 1n, Nil{}, Con{Con{Sstable.build(Con{MemTable.Entry{"x", Some{"old"}}, Nil{}}, 0n, 1n), Nil{}}, Nil{}}, 1n, "", 1n, 0n}

# LAW: mem shadows L0 shadows L1 (closed)
law db_get_newest_wins:
  {(Db.db_get(two_level_db(), "m"), Db.db_get(two_level_db(), "l0"), Db.db_get(two_level_db(), "l1")) == (Some{"mv"}, Some{"l0v"}, Some{"l1v"}) : Maybe<&2, String> & Maybe<&2, String> & Maybe<&2, String>}

# LAW: mem tombstone hides the L0 value (closed)
law db_get_tombstone_hides:
  {Db.db_get(tomb_db(), "x") == None{} : Maybe<&2, String>}

# LAW: absent key misses everywhere (closed)
law db_get_miss:
  {Db.db_get(two_level_db(), "zzz") == None{} : Maybe<&2, String>}

# --- db_get_cached transparency (Phase A3): closed vectors ---

def cached_snd(pair: (Db.Db & Maybe<&2, String>)) -> Maybe<&2, String>:
  match pair:
    case (db2, v):
      v

def cached_val(+db: Db.Db, +key: String) -> Maybe<&2, String>:
  cached_snd(Db.db_get_cached(db, key))

# LAW: cached reads agree with uncached reads (closed)
law db_cache_transparent_hit:
  {cached_val(two_level_db(), "l0") == Db.db_get(two_level_db(), "l0") : Maybe<&2, String>}

# LAW: cached tombstone still hides (closed)
law db_cache_transparent_tomb:
  {cached_val(tomb_db(), "x") == Db.db_get(tomb_db(), "x") : Maybe<&2, String>}

# LAW: cached miss agrees (closed)
law db_cache_transparent_miss:
  {cached_val(two_level_db(), "zzz") == Db.db_get(two_level_db(), "zzz") : Maybe<&2, String>}

# --- grouped commits (Phase B1): closed vectors ---

def stage_two() -> List<&2, Wal.Batch>:
  Con{Wal.Batch{Con{Wal.Put{"b", "2"}, Nil{}}}, Con{Wal.Batch{Con{Wal.Put{"a", "1"}, Nil{}}}, Nil{}}}

# LAW: staged fold applies oldest batch first, equal to sequential writes (closed)
law db_staged_order:
  {Db.apply_batch(Db.staged_muts(List.reverse(&2, Wal.Batch, stage_two())), MemTable.empty()) == Db.apply_batch(Con{Wal.Put{"b", "2"}, Nil{}}, Db.apply_batch(Con{Wal.Put{"a", "1"}, Nil{}}, MemTable.empty())) : MemTable.MemTable}

# --- active/frozen rotation (Phase B2): closed vectors ---

def small_mem() -> MemTable.MemTable:
  MemTable.MT{Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}

def mem_entries(tab: MemTable.MemTable) -> List<&2, MemTable.Entry>:
  match tab:
    case MemTable.MT{entries}:
      entries

def pair_entries(res: Db.RotRes) -> List<&2, MemTable.Entry>:
  match res:
    case Db.Rot{mem2, frozen2, mc, fc}:
      List.append(&2, MemTable.Entry, mem_entries(mem2), mem_entries(frozen2))

# LAW: no rotation below cap keeps tables and counts in place (closed)
law rotate_below_cap:
  {Db.rotate_cnt(False{}, small_mem(), MemTable.empty(), 3n, 0n) == Db.Rot{small_mem(), MemTable.empty(), 3n, 0n} : Db.RotRes}

# LAW: rotation moves a full memtable to frozen and zeroes its count (closed)
law rotate_fires:
  {Db.rotate_cnt(True{}, small_mem(), MemTable.empty(), 3n, 0n) == Db.Rot{MemTable.empty(), small_mem(), 0n, 3n} : Db.RotRes}

# LAW: rotation preserves every entry (closed)
law rotate_preserves:
  {pair_entries(Db.apply_and_rotate(db_muts2(), MemTable.empty(), MemTable.empty(), 0n, 0n)) == mem_entries(Db.apply_batch(db_muts2(), MemTable.empty())) : List<&2, MemTable.Entry>}

# LAW: frozen emptiness detector (closed)
law frozen_empty_branches:
  {(Db.frozen_empty(MemTable.empty()), Db.frozen_empty(small_mem())) == (True{}, False{}) : Bool & Bool}
