import Base
import ../laws/BloomSchedule.bend as Laws
import ../src/Sstable.bend as Sstable

def Laws.bloom_schedule(e, l, n):
  Sstable.table_bits_build(e, l, n)
