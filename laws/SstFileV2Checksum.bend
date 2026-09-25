import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2

# Checksum decision kernel: the streaming decoder retains the body chars
# (reversed) and the claimed hex chars (reversed); at EOF the hub SHA-256
# verifies them. The decision logic — the security kernel — is pinned here.
# Fixtures use body "S2;1;0;" with its real SHA-256 hex digest, both reversed
# as the decoder accumulates them.

law sst2_checksum_reject_decision:
  {SstFileV2.checksum_decision(False{}, Nil{}, 1n) == SstFileV2.ParseRejected{SstFileV2.ChecksumMismatch{}} : SstFileV2.ParseResult}

law sst2_checksum_accept_decision:
  {SstFileV2.checksum_decision(True{}, Nil{}, 1n) == SstFileV2.Parsed{Sstable.from_sorted_unique(Nil{}, 1n)} : SstFileV2.ParseResult}

law sst2_checksum_value_accept:
  {SstFileV2.checksum_value("f7f24ae66eb2bdaee3f54037e415de2c2ff58bc13d49b7f8e92f51a840cd070b", Nil{}, 1n, ";0;1;2S") == SstFileV2.Parsed{Sstable.from_sorted_unique(Nil{}, 1n)} : SstFileV2.ParseResult}

law sst2_checksum_value_reject:
  {SstFileV2.checksum_value("0", Nil{}, 1n, ";0;1;2S") == SstFileV2.ParseRejected{SstFileV2.ChecksumMismatch{}} : SstFileV2.ParseResult}
