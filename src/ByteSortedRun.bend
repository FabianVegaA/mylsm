import Base
import ./ByteMemTable.bend as ByteMemTable

def flatten.runs(runs: List<&1, List<&1, ByteMemTable.Entry>>) -> List<&1, ByteMemTable.Entry>:
  match runs:
    case Nil{}:
      Nil{}
    case Con{run, rest}:
      List.append(&1, ByteMemTable.Entry, run, flatten.runs(rest))

# Collapses a newest-first mutation list into unique byte-key order.
def sort_newest(entries: List<&1, ByteMemTable.Entry>) -> List<&1, ByteMemTable.Entry>:
  ByteMemTable.ordered_entries(ByteMemTable.Table{entries})

# Merges memory and runs in precedence order while retaining tombstones.
def merge_newest(
  memtable: List<&1, ByteMemTable.Entry>,
  runs: List<&1, List<&1, ByteMemTable.Entry>>
) -> List<&1, ByteMemTable.Entry>:
  sort_newest(List.append(&1, ByteMemTable.Entry, memtable, flatten.runs(runs)))
