import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/Decimal.bend as Decimal
import ../src/SstFileV2.bend as SstFileV2

# Checksum decision kernel, tested without the byte stream: the streaming
# decoder accumulates one chained U32.mul per body byte, and the Bend
# checker does not share across such chains (end-to-end `{==}` over even a
# ~13-byte body diverges, while runtime evaluates it in milliseconds). The
# accept-path stream is covered at runtime (bench smoke + fault injection);
# the decision logic — the security kernel — is pinned here instead.

law sst2_checksum_reject_decision:
  {SstFileV2.checksum_decision(False{}, Nil{}, 1n) == SstFileV2.ParseRejected{SstFileV2.ChecksumMismatch{}} : SstFileV2.ParseResult}

law sst2_checksum_accept_decision:
  {SstFileV2.checksum_decision(True{}, Nil{}, 1n) == SstFileV2.Parsed{Sstable.from_sorted_unique(Nil{}, 1n)} : SstFileV2.ParseResult}

law sst2_checksum_value_accept:
  {SstFileV2.checksum_value(Decimal.Accepted{Decimal.Dec{5n, ""}}, Nil{}, 1n, 5) == SstFileV2.Parsed{Sstable.from_sorted_unique(Nil{}, 1n)} : SstFileV2.ParseResult}

law sst2_checksum_value_reject:
  {SstFileV2.checksum_value(Decimal.Accepted{Decimal.Dec{6n, ""}}, Nil{}, 1n, 5) == SstFileV2.ParseRejected{SstFileV2.ChecksumMismatch{}} : SstFileV2.ParseResult}
