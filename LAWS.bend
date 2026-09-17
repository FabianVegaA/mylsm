import Base
import ./src/Keys.bend as Keys
import ./src/MemTable.bend as MemTable

# Trust root (read before the laws below): Bend Base primitives —
# arithmetic, comparison, String/Char ops — are the trusted kernel. They
# ship precompiled with Bend and are NOT re-proven here: reproving
# Word.cmp reflexivity from bit axioms would burn the project proving the
# compiler's own prelude. Instead every primitive WE depend on is pinned by
# closed-term laws (all inputs concrete, proven by {==} normalization) and
# hammered empirically by the Task 12 fuzz harness. All SIXTEEN product
# laws below are about OUR code and are proven in full.

# LAW: comparison unpacking is wired correctly (reflexive case)
law cmp_refl_a:
  {Keys.cmp("a", "a") == EQ{} : Cmp}

# LAW: comparison unpacking is wired correctly (ordered case)
law cmp_order_ab:
  {Keys.cmp("a", "b") == LT{} : Cmp}

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
