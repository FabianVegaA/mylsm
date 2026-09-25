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
def cmp(+a: String, +b: String) -> Cmp:
  Keys.cmp(a, b)

def eq(+a: String, +b: String) -> Bool:
  Keys.eq(a, b)

def mem_empty() -> MemTable.MemTable:
  MemTable.empty()

def mem_put(t: MemTable.MemTable, k: String, v: String) -> MemTable.MemTable:
  MemTable.put(t, k, v)

def mem_del(t: MemTable.MemTable, k: String) -> MemTable.MemTable:
  MemTable.del(t, k)

def mem_get(t: MemTable.MemTable, +k: String) -> Maybe<&2, String>:
  MemTable.get(t, k)

def mem_count(t: MemTable.MemTable) -> Nat:
  MemTable.count(t)

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

def wal_encode(b: Wal.Batch) -> String:
  Wal.encode(b)

def wal_decode(+s: String) -> Maybe<&2, Wal.Batch>:
  Wal.decode(s)

def sst_serialize(+entries: List<&2, MemTable.Entry>, +level: Nat) -> String:
  SstFile.serialize(entries, level)

def sst_parse(+encoded: String) -> Maybe<&2, Sstable.Table>:
  SstFile.parse(encoded)

def mfst_serialize(m: Manifest.Manifest) -> String:
  Manifest.serialize(m)

def mfst_parse(+s: String) -> Maybe<&2, Manifest.Manifest>:
  Manifest.parse(s)

# --- Level 1: Sess session monad (primary API) ---
type Sess<a, -A: Kind(a)> is Kind(a <&> &1):
  Sess{run: Db.Db -> (Db.Db & A)}

def Sess.pure(a, -A: Kind(a), x: A) -> Sess<a, A>:
  Sess{db => (db, x)}

def Sess.run_go(b, -B: Kind(b), s: Sess<b, B>, st: Db.Db) -> Db.Db & B:
  match s:
    case Sess{run}: run(st)

def Sess.apply(a, -A: Kind(a), b, -B: Kind(b), p: Db.Db & A, f: A -> Sess<b, B>) -> Db.Db & B:
  match p:
    case (st, x): Sess.run_go(b, B, f(x), st)

def Sess.bind(a, -A: Kind(a), -B: Kind(a), m: Sess<a, A>, f: A -> Sess<a, B>) -> Sess<a, B>:
  Sess{st => Sess.apply(a, A, a, B, Sess.run_go(a, A, m, st), f)}

def open(+dir: String) -> Db.Db:
  Db.open_db(dir)

def put_go(+db: Db.Db, +k: String, +v: String) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      Db.Db{dir, Db.apply_batch(Con{Wal.Put{k, v}, Nil{}}, mem), frozen, batch_cap, bcache, levels, flushed, manifest_token}

def del_go(+db: Db.Db, +k: String) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      Db.Db{dir, Db.apply_batch(Con{Wal.Del{k}, Nil{}}, mem), frozen, batch_cap, bcache, levels, flushed, manifest_token}

def batch_go(+db: Db.Db, +muts: List<&2, Wal.Mut>) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      Db.Db{dir, Db.apply_batch(muts, mem), frozen, batch_cap, bcache, levels, flushed, manifest_token}

def sget_go(+db: Db.Db, +k: String) -> Db.Db & Maybe<&2, String>:
  (db, Db.db_get(db, k))

def sput(+k: String, +v: String) -> Sess<&2, Unit>:
  Sess{db => (put_go(db, k, v), Unit{})}

def sdel(+k: String) -> Sess<&2, Unit>:
  Sess{db => (del_go(db, k), Unit{})}

def sbatch(+muts: List<&2, Wal.Mut>) -> Sess<&2, Unit>:
  Sess{db => (batch_go(db, muts), Unit{})}

def sget(+k: String) -> Sess<&2, Maybe<&2, String>>:
  Sess{db => sget_go(db, k)}

def run_sess(a, -A: Kind(a), st: Db.Db, s: Sess<a, A>) -> Db.Db & A:
  Sess.run_go(a, A, s, st)

def value_of(a, -A: Kind(a), p: Db.Db & A) -> A:
  match p:
    case (db, x): x

def encode_batch(b: Wal.Batch) -> String:
  Wal.encode(b)
