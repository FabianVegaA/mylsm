import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile

# V2 framing kernel, tested without the byte stream (same checker
# limitation documented in SstFileV2Checksum: end-to-end `{==}` over a
# hashed stream diverges).

law sstfile_v2_tag:
  {String.starts_with(SstFile.serialize(Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}, 0n), "S2;") == True{} : Bool}

law sstfile_v2_reject:
  {SstFile.parse("X") == None{} : Maybe<&2, Sstable.Table>}
