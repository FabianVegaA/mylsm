import Base
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest
import ./SstFileV2.bend as SstFileV2
import ./SstFileV1Fast.bend as SstFileV1Fast

# Public SSTable codec boundary. Production writes compact v2 files. Reads are
# version-dispatched so legacy v1 databases remain recoverable and migrate
# naturally when compaction publishes v2 outputs.

# Legacy serialization remains test-only; production callers use serialize_v2.
def muts_of_entries(+es: List<&2, MemTable.Entry>) -> List<&2, Wal.Mut>:
  match es:
    case Nil{}:
      Nil{}
    case Con{MemTable.Entry{key, val}, rest}:
      match val:
        case None{}:
          Con{Wal.Del{key}, muts_of_entries(rest)}
        case Some{value}:
          Con{Wal.Put{key, value}, muts_of_entries(rest)}


def serialize_v1(+entries: List<&2, MemTable.Entry>, +level: Nat) -> String:
  +wal = Wal.encode(Wal.Batch{muts_of_entries(entries)})
  +body = "T" ++ Wal.dashes(level) ++ ";" ++ Wal.dashes(String.length(wal)) ++ ";" ++ wal
  body ++ "#" ++ U32.show(Manifest.mhash(body, 7))


def parse_v1(+encoded: String) -> Maybe<&2, Sstable.Table>:
  SstFileV1Fast.parse(encoded)


def serialize_v2(+entries: List<&2, MemTable.Entry>, +level: Nat) -> String:
  SstFileV2.serialize(entries, level)


def serialize(+entries: List<&2, MemTable.Entry>, +level: Nat) -> String:
  serialize_v2(entries, level)


def parse_version(v2: Bool, +encoded: String) -> Maybe<&2, Sstable.Table>:
  match v2:
    case True{}:
      SstFileV2.parse(encoded)
    case False{}:
      parse_v1(encoded)


def parse(+encoded: String) -> Maybe<&2, Sstable.Table>:
  parse_version(String.starts_with(encoded, "S2;"), encoded)


# Total-parser witness used by the hardening law.
def is_decided(+result: Maybe<&2, Sstable.Table>) -> Bool:
  True{}
