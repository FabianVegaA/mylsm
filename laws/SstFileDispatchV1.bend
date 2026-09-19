import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile
import ../src/SstFileV2.bend as SstFileV2

# Version routing, tested without streams: parse_version is a pure Bool
# dispatch, and parse detects the tag in the first 3 bytes. Both sides of
# each equality reject the tiny input before any hash accumulates.

law sst2_dispatch_v1_passthrough:
  {SstFile.parse_version(False{}, "X") == SstFile.parse_v1("X") : Maybe<&2, Sstable.Table>}

law sst2_dispatch_v1_tag:
  {SstFile.parse("S1;X") == SstFile.parse_v1("S1;X") : Maybe<&2, Sstable.Table>}
