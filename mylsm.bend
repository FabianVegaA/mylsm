import Base
import ./src/Keys.bend as Keys
import ./src/MemTable.bend as MemTable
import ./src/SortedRun.bend as SortedRun
import ./src/Sstable.bend as Sstable
import ./src/SstFile.bend as SstFile
import ./src/Wal.bend as Wal
import ./src/Manifest.bend as Manifest
import ./src/MergeIter.bend as MergeIter
import ./src/Db.bend as Db

# --- Level 2: part control (1:1 delegates) ---
def cmp(+s1: String, +s2: String) -> Cmp:
  Keys.cmp(s1, s2)

def eq(+s1: String, +s2: String) -> Bool:
  Keys.eq(s1, s2)

def mem_empty() -> MemTable.MemTable:
  MemTable.empty()

def mem_put(tab: MemTable.MemTable, key: String, val: String) -> MemTable.MemTable:
  MemTable.put(tab, key, val)

def mem_del(tab: MemTable.MemTable, key: String) -> MemTable.MemTable:
  MemTable.del(tab, key)

def mem_get(tab: MemTable.MemTable, +key: String) -> Maybe<&2, String>:
  MemTable.get(tab, key)

def mem_count(tab: MemTable.MemTable) -> Nat:
  MemTable.count(tab)

def sort_newest(entries: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  SortedRun.sort_newest(entries)

def range_scan(+merged: List<&2, MemTable.Entry>, lo: String, hi: String) -> List<&2, MemTable.Entry>:
  MergeIter.scan(merged, lo, hi)

def sst_build(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Sstable.Table:
  Sstable.build(entries, level, est_keys)

def sst_from_sorted_unique(+entries: List<&2, MemTable.Entry>, level: Nat) -> Sstable.Table:
  Sstable.from_sorted_unique(entries, level)

def sst_build_sorted(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Sstable.Table:
  Sstable.build_sorted(entries, level, est_keys)

def wal_encode(batch: Wal.Batch) -> String:
  Wal.encode(batch)

def wal_decode(+str: String) -> Maybe<&2, Wal.Batch>:
  Wal.decode(str)

def sst_serialize(+entries: List<&2, MemTable.Entry>, +level: Nat) -> String:
  SstFile.serialize(entries, level)

def sst_parse(+encoded: String) -> Maybe<&2, Sstable.Table>:
  SstFile.parse(encoded)

def mfst_serialize(mfst: Manifest.Manifest) -> String:
  Manifest.serialize(mfst)

def mfst_parse(+str: String) -> Maybe<&2, Manifest.Manifest>:
  Manifest.parse(str)

# --- Level 1: Sess session monad (primary API) ---
type Sess<a, -A: Kind(a)> is Kind(a <&> &1):
  Sess{run: Db.Db -> (Db.Db & A)}

def Sess.pure(a, -A: Kind(a), val: A) -> Sess<a, A>:
  Sess{db => (db, val)}

def Sess.run_go(b, -B: Kind(b), sess: Sess<b, B>, st: Db.Db) -> Db.Db & B:
  match sess:
    case Sess{run}: run(st)

def Sess.apply(a, -A: Kind(a), b, -B: Kind(b), pair: Db.Db & A, fun: A -> Sess<b, B>) -> Db.Db & B:
  match pair:
    case (st, x): Sess.run_go(b, B, fun(x), st)

def Sess.bind(a, -A: Kind(a), -B: Kind(a), sess: Sess<a, A>, fun: A -> Sess<a, B>) -> Sess<a, B>:
  Sess{st => Sess.apply(a, A, a, B, Sess.run_go(a, A, sess, st), fun)}

def open(+dir: String) -> Db.Db:
  Db.open_db(dir)

def put_go(+db: Db.Db, +key: String, +val: String) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      Db.Db{dir, Db.apply_batch(Con{Wal.Put{key, val}, Nil{}}, mem), frozen, batch_cap, bcache, levels, flushed, manifest_token}

def del_go(+db: Db.Db, +key: String) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      Db.Db{dir, Db.apply_batch(Con{Wal.Del{key}, Nil{}}, mem), frozen, batch_cap, bcache, levels, flushed, manifest_token}

def batch_go(+db: Db.Db, +muts: List<&2, Wal.Mut>) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      Db.Db{dir, Db.apply_batch(muts, mem), frozen, batch_cap, bcache, levels, flushed, manifest_token}

def sget_go(+db: Db.Db, +key: String) -> Db.Db & Maybe<&2, String>:
  (db, Db.db_get(db, key))

def sput(+key: String, +val: String) -> Sess<&2, Unit>:
  Sess{db => (put_go(db, key, val), Unit{})}

def sdel(+key: String) -> Sess<&2, Unit>:
  Sess{db => (del_go(db, key), Unit{})}

def sbatch(+muts: List<&2, Wal.Mut>) -> Sess<&2, Unit>:
  Sess{db => (batch_go(db, muts), Unit{})}

def sget(+key: String) -> Sess<&2, Maybe<&2, String>>:
  Sess{db => sget_go(db, key)}

def run_sess(a, -A: Kind(a), st: Db.Db, sess: Sess<a, A>) -> Db.Db & A:
  Sess.run_go(a, A, sess, st)

def value_of(a, -A: Kind(a), pair: Db.Db & A) -> A:
  match pair:
    case (db, x): x

def encode_batch(batch: Wal.Batch) -> String:
  Wal.encode(batch)
