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
  Db.Db{"/d", MemTable.MT{Con{MemTable.Entry{"m", Some{"mv"}}, Nil{}}}, MemTable.MT{Nil{}}, 1n, Nil{}, Con{Con{Sstable.build(Con{MemTable.Entry{"l0", Some{"l0v"}}, Nil{}}, 0n, 1n), Nil{}}, Con{Con{Sstable.build(Con{MemTable.Entry{"l1", Some{"l1v"}}, Nil{}}, 0n, 1n), Nil{}}, Nil{}}}, 2n, ""}

def tomb_db() -> Db.Db:
  Db.Db{"/d", MemTable.MT{Con{MemTable.Entry{"x", None{}}, Nil{}}}, MemTable.MT{Nil{}}, 1n, Nil{}, Con{Con{Sstable.build(Con{MemTable.Entry{"x", Some{"old"}}, Nil{}}, 0n, 1n), Nil{}}, Nil{}}, 1n, ""}

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
