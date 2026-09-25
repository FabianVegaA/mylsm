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

# LAW: hit-detecting read-your-writes (outer Some = hit)
law mt_hit_ryw:
  for t: MemTable.MemTable
  for +k: String
  for +v: String
  {MemTable.get_hit(MemTable.put(t, k, v), k) == Some{Some{v}} : Maybe<&2, Maybe<&2, String>>}

# LAW: hit-detecting delete reads as a tombstone hit, not a miss
law mt_hit_del:
  for t: MemTable.MemTable
  for +k: String
  for v: String
  {MemTable.get_hit(MemTable.del(MemTable.put(t, k, v), k), k) == Some{None{}} : Maybe<&2, Maybe<&2, String>>}

# LAW: hit-detecting miss on empty
law mt_hit_miss:
  for +k: String
  {MemTable.get_hit(MemTable.empty(), k) == None{} : Maybe<&2, Maybe<&2, String>>}
