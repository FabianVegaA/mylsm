import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/Decimal.bend as Decimal
import ../src/SstFile.bend as SstFile
import ../src/SstFileV1Fast.bend as SstFileV1Fast

# V1 framing kernel, tested without the byte stream (same checker
# limitation documented in SstFileV2Checksum: end-to-end `{==}` over a
# hashed stream diverges). serialize is hash-free on the way out
# (U32-only accumulation); parse decisions are pinned below.

law sstfile_v1_tag:
  {String.starts_with(SstFile.serialize_v1(Con{MemTable.Entry{"b", Some{"2"}}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}, 0n), "T") == True{} : Bool}

law sstfile_v1_fast_reject:
  {SstFile.parse_v1("X") == None{} : Maybe<&2, Sstable.Table>}

law sstfile_v1_checksum_reject_decision:
  {SstFileV1Fast.checksum_decision(False{}, True{}, Nil{}, 1n, 0n) == SstFileV1Fast.ParseRejected{SstFileV1Fast.ChecksumMismatch{}} : SstFileV1Fast.ParseResult}

law sstfile_v1_checksum_value_accept:
  {SstFileV1Fast.checksum_value(Decimal.Accepted{Decimal.Dec{5n, ""}}, True{}, Nil{}, 1n, 0n, 5) == SstFileV1Fast.Parsed{SstFileV1Fast.build_table(True{}, Nil{}, 1n, 0n)} : SstFileV1Fast.ParseResult}

law sstfile_v1_checksum_value_reject:
  {SstFileV1Fast.checksum_value(Decimal.Accepted{Decimal.Dec{6n, ""}}, True{}, Nil{}, 1n, 0n, 5) == SstFileV1Fast.ParseRejected{SstFileV1Fast.ChecksumMismatch{}} : SstFileV1Fast.ParseResult}
