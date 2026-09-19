import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2
import ../src/SstStream.bend as SstStream

def sst2_del_entries() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", None{}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}

def sst2_feed_two(+s: String) -> Result<&1, &1, U32 & String, Sstable.Table>:
  SstStream.finish_mode(SstStream.feed_mode(SstStream.feed_mode(SstStream.Unknown{}, String.take(s, 10n)), String.drop(s, 10n)))

law sst2_chunk_agree:
  {sst2_feed_two(SstFileV2.serialize(sst2_del_entries(), 1n)) == Done{Sstable.from_sorted_unique(sst2_del_entries(), 1n)} : Result<&1, &1, U32 & String, Sstable.Table>}
