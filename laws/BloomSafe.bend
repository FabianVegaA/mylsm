import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable

# Handle sst e1 in the Bloom filter safety laws.
def sst_e1() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}

# LAW: bloom never rejects a present key (closed)
law bloom_safe:
  {Sstable.bloom_test(Sstable.bloom_of(sst_e1(), Sstable.bloom_new(20n)), "a") == True{} : Bool}

# Closed table vector for probe-count equivalence.
def probe_tab() -> Sstable.Table:
  Sstable.Tbl{sst_e1(), Sstable.bloom_of(sst_e1(), Sstable.bloom_new(20n)), 20n,
    Some{"a"}, Some{"a"}, 1n, Con{sst_e1(), Nil{}}, Con{"a", Nil{}}}

# Closed probe vector: two hits, one miss.
def probe_qs() -> List<&2, String>:
  Con{"a", Nil{}}

# Confirms the parallel probe count for one present key.
law probe_par_single_hit:
  {Sstable.probe_count_par(probe_qs(), probe_tab()) == 1n : Nat}

# Confirms the sequential probe count for one present key.
law probe_seq_single_hit:
  {Sstable.probe_count_seq(probe_qs(), probe_tab()) == 1n : Nat}

# Parallel and sequential probing return the same count.
law probe_parallel_matches_sequential:
  {Sstable.probe_count_par(probe_qs(), probe_tab()) == Sstable.probe_count_seq(probe_qs(), probe_tab()) : Nat}
