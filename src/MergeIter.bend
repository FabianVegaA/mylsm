import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SortedRun.bend as SortedRun

# Merge iterator (Task 6): concat sources (memtable newest-first, then
# SSTables newest-level-first) and canonicalize with balanced stable merge;
# first-inserted wins ties = newest wins). The range+tombstone filter is
# pump+fuel+leaf: String.cmp hands both strings back beside the verdict,
# so the key survives the keep/drop decision with no clone primitive.
# Order of defs is load-bearing (Bend 2: only backward references).

def scan_put2(q: (String & String) & Cmp, +v: String, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match q:
    case ((k3, _), c):
      match c:
        case LT{}:
          Con{MemTable.Entry{k3, Some{v}}, acc}
        case EQ{}:
          acc
        case GT{}:
          acc

def scan_put(p: (String & String) & Cmp, +hi: String, +v: String, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match p:
    case ((k2, _), c):
      match c:
        case LT{}:
          acc
        case EQ{}:
          scan_put2(String.cmp(k2, hi), v, acc)
        case GT{}:
          scan_put2(String.cmp(k2, hi), v, acc)

def scan_go(fuel: Nat, +lo: String, +hi: String, acc: List<&2, MemTable.Entry>, xs: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match fuel:
    case 0n:
      List.reverse(&2, MemTable.Entry, acc)
    case 1n+f:
      match xs:
        case Nil{}:
          List.reverse(&2, MemTable.Entry, acc)
        case Con{MemTable.Entry{key, val}, t}:
          match val:
            case None{}:
              scan_go(f, lo, hi, acc, t)
            case Some{v}:
              scan_go(f, lo, hi, scan_put(String.cmp(key, lo), hi, v, acc), t)

# Newest-first concat: memtable entries, then each level's tables in order.
def flatten(mem: List<&2, MemTable.Entry>, levels: List<&2, List<&2, MemTable.Entry>>) -> List<&2, MemTable.Entry>:
  match levels:
    case Nil{}:
      mem
    case Con{h, t}:
      List.append(&2, MemTable.Entry, mem, List.concat(&2, MemTable.Entry, Con{h, t}))

# Full merge: sorted, unique, newest version wins each key.
def merge(mem: List<&2, MemTable.Entry>, levels: List<&2, List<&2, MemTable.Entry>>) -> List<&2, MemTable.Entry>:
  SortedRun.sort_newest(flatten(mem, levels))

# Range scan over a merged run: lo <= key < hi, tombstones dropped.
def scan(+merged: List<&2, MemTable.Entry>, lo: String, hi: String) -> List<&2, MemTable.Entry>:
  scan_go(List.length(&2, MemTable.Entry, merged), lo, hi, Nil{}, merged)

# --- Closed-vector laws live in LAWS.bend (spec laws 4, 5, 10) ---
