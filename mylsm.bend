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
