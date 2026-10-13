import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/Db.bend as Db
import ../src/SortedRun.bend as SortedRun

# Closed SSTable vectors. Open sortedness/lookup need comparison facts on open
# keys; those formal limitations remain covered only by closed vectors and fuzz.
def sst_e1() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"", Some{"2"}}, Nil{}}}

# Handle sst e2 in the SSTable laws.
def sst_e2() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"k", Some{"new"}}, Con{MemTable.Entry{"k", Some{"old"}}, Nil{}}}

# Keeps one entry for the parallel Bloom construction witnesses.
def bloom_e() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"", Some{"1"}}, Nil{}}

# LAW: build sorts (closed)
law sst_sorted:
  {SortedRun.sort_newest(sst_e1()) == Con{MemTable.Entry{"", Some{"2"}}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}} : List<&2, MemTable.Entry>}

# LAW: newest version wins on duplicate keys (closed)
law sst_newest:
  {Sstable.lookup(Sstable.build(sst_e2(), 0n, 2n), "k") == Some{"new"} : Maybe<&2, String>}

# LAW: cached metadata is exact for canonical sorted construction
law sst_metadata_count:
  {Sstable.table_count(Sstable.from_sorted_unique(Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}, 1n)) == 2n : Nat}

# State the sst metadata bounds property for the SSTable laws.
law sst_metadata_bounds:
  {(Sstable.table_smallest(Sstable.from_sorted_unique(Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}, 1n)),
  Sstable.table_largest(Sstable.from_sorted_unique(Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}, 1n))) == (Some{"a"}, Some{"b"}) : Maybe<&2,
  String> & Maybe<&2, String>}

# LAW: block_get agrees with lookup on a hit (closed)
law sstable_block_get_equiv:
  {Sstable.block_get(Sstable.build(sst_e2(), 0n, 2n), "k") == Sstable.lookup(Sstable.build(sst_e2(), 0n, 2n), "k") : Maybe<&2, String>}

# LAW: block_get misses cleanly (closed)
law sstable_block_get_missing:
  {Sstable.block_get(Sstable.build(sst_e2(), 0n, 2n), "zzz") == None{} : Maybe<&2, String>}

# LAW: block_get_hit agrees with block_get on a hit (closed)
law sstable_block_hit_equiv:
  {Sstable.block_get_hit(Sstable.build(sst_e2(), 0n, 2n), "k") == Some{Some{"new"}} : Maybe<&2, Maybe<&2, String>>}

# LAW: block_get_hit misses cleanly (closed)
law sstable_block_hit_missing:
  {Sstable.block_get_hit(Sstable.build(sst_e2(), 0n, 2n), "zzz") == None{} : Maybe<&2, Maybe<&2, String>>}

# Handle blm a in the SSTable laws.
def blm_a() -> Sstable.Bloom:
  Sstable.bloom_of(Con{MemTable.Entry{"", Some{"1"}}, Nil{}}, Sstable.bloom_new(2n))

# LAW: union keeps member bits (closed)
law sstable_bloom_union_hit:
  {Sstable.bloom_test(Sstable.bloom_union(blm_a(), Sstable.bloom_new(2n)), "") == True{} : Bool}

# LAW: union adds no ghost bits for this vector (closed)
law sstable_bloom_union_miss:
  {Sstable.bloom_test(Sstable.bloom_union(blm_a(), Sstable.bloom_new(2n)), "a") == False{} : Bool}

# LAW: two-half parallel build equals the sequential build (closed)
law sstable_bloom_par_agrees:
  {Sstable.bloom_of_par(bloom_e(), 2n) == Sstable.bloom_of(bloom_e(), Sstable.bloom_new(2n)) : Sstable.Bloom}

# LAW: four-chunk parallel build equals the sequential build (closed)
law sstable_bloom_chunks_agree:
  {Sstable.bloom_of_chunks(bloom_e(), 2n) == Sstable.bloom_of(bloom_e(), Sstable.bloom_new(2n)) : Sstable.Bloom}

# LAW: hybrid build equals the sequential build (closed)
law sstable_bloom_hybrid_agrees:
  {Sstable.bloom_of_hybrid(bloom_e(), 2n) == Sstable.bloom_of(bloom_e(), Sstable.bloom_new(2n)) : Sstable.Bloom}
