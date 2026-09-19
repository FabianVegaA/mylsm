import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile
import ../src/SstFileV2.bend as SstFileV2

# Cross-version agreement on malformed input (fast early reject on both
# sides). Accept-path equivalence (same data reads identically under both
# versions) is covered at runtime: it requires end-to-end parse, which the
# checker cannot normalize (see SstFileV2Checksum).

law sst2_v1_v2_reject_agree:
  {SstFile.parse_v1("X") == SstFileV2.parse("X") : Maybe<&2, Sstable.Table>}
