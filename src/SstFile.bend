import Base
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SstFileV2.bend as SstFileV2

# Sole SSTable codec boundary: compact v2. The legacy v1 representation was
# removed (no retrocompat); every file on disk is v2.

def serialize(+entries: List<&2, MemTable.Entry>, +level: Nat) -> String:
  SstFileV2.serialize(entries, level)


def parse(+encoded: String) -> Maybe<&2, Sstable.Table>:
  SstFileV2.parse(encoded)


# Total-parser witness used by the hardening law.
def is_decided(+result: Maybe<&2, Sstable.Table>) -> Bool:
  True{}
