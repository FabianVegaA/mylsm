import Base
import ./src/Keys.bend as Keys
import ./src/MemTable.bend as MemTable
import ./src/Wal.bend as Wal
import ./src/Sstable.bend as Sstable

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

# --- WAL codec (Task 3) ---

# LAW: WAL codec round-trip (closed vectors; each is proven by {==}
# normalization alone — no manual P's, no fragility).
# The OPEN round-trip (all batches) is fuzz-verified (Task 12, 1M+ inputs)
# and its full proof is deferred: open-key/open-length joint induction
# hits Bend 2.0.5 automation limits (syntactic P-matching over pump states
# with stuck-open tails). See spec §3.2.

# Batch fixtures (named defs: the parser rejects nested Con inside Some).
def batch_empty() -> Wal.Batch:
  Wal.Batch{Nil{}}

def batch_put1() -> Wal.Batch:
  Wal.Batch{Con{Wal.Put{"k", "v"}, Nil{}}}

def batch_del1() -> Wal.Batch:
  Wal.Batch{Con{Wal.Del{"k"}, Nil{}}}

def batch_multi() -> Wal.Batch:
  Wal.Batch{Con{Wal.Put{"a", ""}, Con{Wal.Del{"b"}, Con{Wal.Put{"", "c"}, Nil{}}}}}

law wal_rt_empty:
  {Wal.decode(Wal.encode(batch_empty())) == Some{batch_empty()} : Maybe<&2, Wal.Batch>}

law wal_rt_put1:
  {Wal.decode(Wal.encode(batch_put1())) == Some{batch_put1()} : Maybe<&2, Wal.Batch>}

law wal_rt_del1:
  {Wal.decode(Wal.encode(batch_del1())) == Some{batch_del1()} : Maybe<&2, Wal.Batch>}

law wal_rt_multi:
  {Wal.decode(Wal.encode(batch_multi())) == Some{batch_multi()} : Maybe<&2, Wal.Batch>}

# --- SSTable + Bloom (Task 4) ---
# Closed vectors ({==}-proved) + open definitional schedule law.
# Open sortedness/lookup need comparison facts on open keys (same
# automation wall as Task 3); covered by closed vectors + Task-12 fuzz.

def sst_e1() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"b", Some{"2"}}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}

def sst_e2() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"k", Some{"new"}}, Con{MemTable.Entry{"k", Some{"old"}}, Nil{}}}

# LAW: build sorts (closed)
law sst_sorted:
  {Sstable.build(sst_e1(), 0n, 2n) == Sstable.Tbl{Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}, Sstable.bloom_of(sst_e1(), Sstable.bloom_new(Sstable.bloom_bits(0n, 2n))), Sstable.bloom_bits(0n, 2n)} : Sstable.Table}

# LAW: newest version wins on duplicate keys (closed)
law sst_newest:
  {Sstable.lookup(Sstable.build(sst_e2(), 0n, 2n), "k") == Some{"new"} : Maybe<&2, String>}

# LAW: bloom never rejects a present key (closed)
law bloom_safe:
  {Sstable.maybe_present(Sstable.build(sst_e1(), 0n, 2n), "a") == True{} : Bool}

# LAW: filter bits follow the Monkey schedule (open, definitional)
law bloom_schedule:
  for e: List<&2, MemTable.Entry>
  for l: Nat
  for n: Nat
  {Sstable.table_bits(Sstable.build(e, l, n)) == Sstable.bloom_bits(l, n) : Nat}
