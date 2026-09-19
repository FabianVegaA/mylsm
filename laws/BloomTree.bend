import Base
import ../src/Sstable.bend as Sstable

law bloom_tree_well_formed:
  {Sstable.bloom_well_formed(Sstable.bloom_new(65n)) == True{} : Bool}
