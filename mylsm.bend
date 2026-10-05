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
import ./src/Recover.bend as Recover
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# --- Level 2: part control (1:1 delegates) ---
def cmp(+s1: String, +s2: String) -> Cmp:
  Keys.cmp(s1, s2)

# Key equality: true exactly for identical strings.
def eq(+s1: String, +s2: String) -> Bool:
  Keys.eq(s1, s2)

# Empty MemTable: no entries, count zero.
def mem_empty() -> MemTable.MemTable:
  MemTable.empty()

# MemTable with one live version prepended (newest-first log).
def mem_put(tab: MemTable.MemTable, key: String, val: String) -> MemTable.MemTable:
  MemTable.put(tab, key, val)

# MemTable with one tombstone prepended; hides older versions on read.
def mem_del(tab: MemTable.MemTable, key: String) -> MemTable.MemTable:
  MemTable.del(tab, key)

# Newest-first read; a tombstone answers None and hides older versions.
def mem_get(tab: MemTable.MemTable, +key: String) -> Maybe<&2, String>:
  MemTable.get(tab, key)

# Number of log entries, live and tombstoned.
def mem_count(tab: MemTable.MemTable) -> Nat:
  MemTable.count(tab)

# Canonicalize newest-first entries into a strict ordered run.
def sort_newest(entries: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  SortedRun.sort_newest(entries)

# Range scan over a merged run: lo <= key < hi, tombstones dropped.
def range_scan(+merged: List<&2, MemTable.Entry>, lo: String, hi: String) -> List<&2, MemTable.Entry>:
  MergeIter.scan(merged, lo, hi)

# Build an SSTable, canonicalizing entries newest-first.
def sst_build(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Sstable.Table:
  Sstable.build(entries, level, est_keys)

# Build an SSTable trusting an already strict, unique run (no sorting).
def sst_from_sorted_unique(+entries: List<&2, MemTable.Entry>, level: Nat) -> Sstable.Table:
  Sstable.from_sorted_unique(entries, level)

# Build an SSTable from a sorted run with an explicit key estimate.
def sst_build_sorted(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Sstable.Table:
  Sstable.build_sorted(entries, level, est_keys)

# Handle wal encode in the public module exports.
def wal_encode(batch: Wal.Batch) -> Result<&1, &1, Wal.Error, Bytes.Bytes>:
  Wal.encode_frame(batch)

# Handle wal decode in the public module exports.
def wal_decode(encoded: Bytes.Bytes) -> Result<&1, &1, Wal.Error, Wal.Batch>:
  Wal.decode_frame(encoded)

# Encode an SST as packed v3 bytes.
def sst_encode(
  +entries: List<&2, MemTable.Entry>,
  +level: U32
) -> Result<&1, &1, SstFile.Error, Bytes.Bytes>:
  SstFile.encode_file(entries, level)

# Parse packed v3 bytes with strict bounds and checksum verification.
def sst_parse(
  encoded: Bytes.Bytes
) -> Result<&1, &1, SstFile.Error, Sstable.Table>:
  SstFile.parse(encoded)

# Serialize a Manifest to its exact on-disk bytes.
def mfst_serialize(mfst: Manifest.Manifest) -> Result<&1, &1, Manifest.Error, Bytes.Bytes>:
  Manifest.serialize(mfst)

# Handle mfst parse in the public module exports.
def mfst_parse(encoded: Bytes.Bytes) -> Maybe<&2, Manifest.Manifest>:
  Manifest.parse(encoded)

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

# Open a database handle over a directory label (pure; no IO touched).
def open(+dir: String) -> Db.Db:
  Db.open_db(dir)

# Recover a persisted database from its directory.
def open_recovering(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  Recover.open_db(dir)

# Pure put transition used by the session action.
def put_go(+db: Db.Db, +key: String, +val: String) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db.apply_done(Db.apply_and_rotate(Con{Wal.Put{key, val}, Nil{}}, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

# Pure delete transition used by the session action.
def del_go(+db: Db.Db, +key: String) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db.apply_done(Db.apply_and_rotate(Con{Wal.Del{key}, Nil{}}, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

# Pure batch transition used by the session action.
def batch_go(+db: Db.Db, +muts: List<&2, Wal.Mut>) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db.apply_done(Db.apply_and_rotate(muts, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

# Pure point-read transition used by the session action (cache-backed).
def sget_go(+db: Db.Db, +key: String) -> Db.Db & Maybe<&2, String>:
  Db.db_get_cached(db, key)

# Session step writing one key.
def sput(+key: String, +val: String) -> Sess<&2, Unit>:
  Sess{db => (put_go(db, key, val), Unit{})}

# Session step deleting one key.
def sdel(+key: String) -> Sess<&2, Unit>:
  Sess{db => (del_go(db, key), Unit{})}

# Session step applying a whole mutation batch at once.
def sbatch(+muts: List<&2, Wal.Mut>) -> Sess<&2, Unit>:
  Sess{db => (batch_go(db, muts), Unit{})}

# Session step reading one key.
def sget(+key: String) -> Sess<&2, Maybe<&2, String>>:
  Sess{db => sget_go(db, key)}

# Execute a whole session against a handle.
def run_sess(a, -A: Kind(a), st: Db.Db, sess: Sess<a, A>) -> Db.Db & A:
  Sess.run_go(a, A, sess, st)

# Project the answer out of a runner pair.
def value_of(a, -A: Kind(a), pair: Db.Db & A) -> A:
  match pair:
    case (db, x): x
