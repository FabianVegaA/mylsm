import Base
import ../src/MemTable.bend as MemTable
import ../src/MergeIter.bend as MergeIter

# --- Merge iterator (Task 6): closed vectors + fuzz (spec laws 4, 5, 10) ---
# Merge of newest-first mem [b=v2, a=v1] over L1 [a=v0, c=v3].

def scan_mem() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"a", Some{"v1"}}, Nil{}}}

def scan_l1() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v0"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}

def scan_levels() -> List<&2, List<&2, MemTable.Entry>>:
  Con{scan_l1(), Nil{}}

def scan_merged() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}}

def scan_abc() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}}

def scan_ab() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", Some{"v2"}}, Nil{}}}

def scan_del() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", None{}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}}

def scan_ac() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}

# LAW: merge sorts, dedups, newest wins (closed)
law scan_newest:
  {MergeIter.merge(scan_mem(), scan_levels()) == scan_merged() : List<&2, MemTable.Entry>}

# LAW: range keeps lo <= key < hi (closed)
law scan_range:
  {MergeIter.scan(scan_abc(), "a", "c") == scan_ab() : List<&2, MemTable.Entry>}

# LAW: tombstones dropped (closed)
law scan_drops_dels:
  {MergeIter.scan(scan_del(), "a", "d") == scan_ac() : List<&2, MemTable.Entry>}

# LAW: get-scan agreement on unique-keyed runs (closed)
law scan_agree:
  {MemTable.get(MemTable.MT{scan_ab()}, "b") == Some{"v2"} : Maybe<&2, String>}
