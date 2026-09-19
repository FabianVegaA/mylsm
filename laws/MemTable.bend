import Base
import ../src/MemTable.bend as MemTable

# --- MemTable (Task 2) ---

# LAW: memtable read-your-writes
law mt_ryw:
  for t: MemTable.MemTable
  for +k: String
  for +v: String
  {MemTable.get(MemTable.put(t, k, v), k) == Some{v} : Maybe<&2, String>}

# LAW: memtable delete hides the key
law mt_del:
  for t: MemTable.MemTable
  for +k: String
  for v: String
  {MemTable.get(MemTable.del(MemTable.put(t, k, v), k), k) == None{} : Maybe<&2, String>}
