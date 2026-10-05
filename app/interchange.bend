import Base
import ../src/MemTable.bend as MemTable
import ../src/Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Handle the format version for marker in the portable interchange format.
def version_marker() -> String:
  "MYLSM-EXPORT-2"

# Convert mutations for of entries for the portable interchange format.
def muts_of_entries(es: List<&2, MemTable.Entry>) -> List<&2, Wal.Mut>:
  match es:
    case Nil{}:
      Nil{}
    case Con{MemTable.Entry{key, val}, t}:
      match val:
        case None{}:
          Con{Wal.Del{key}, muts_of_entries(t)}
        case Some{value}:
          Con{Wal.Put{key, value}, muts_of_entries(t)}

# Convert entries for of muts for the portable interchange format.
def entries_of_muts(ms: List<&2, Wal.Mut>) -> List<&2, MemTable.Entry>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{mutation, t}:
      match mutation:
        case Wal.Put{key, val}:
          Con{MemTable.Entry{key, Some{val}}, entries_of_muts(t)}
        case Wal.Del{key}:
          Con{MemTable.Entry{key, None{}}, entries_of_muts(t)}

def serialize.frame(
  frame: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Result<&1, &1, Wal.Error, String>:
  match frame:
    case Fail{error}:
      Fail{error}
    case Done{bytes}:
      Done{version_marker() ++ ":" ++ Bytes.to_hex(bytes)}

# Handle serialize in the portable interchange format.
def serialize(+entries: List<&2, MemTable.Entry>) -> Result<&1, &1, Wal.Error, String>:
  serialize.frame(Wal.encode_frame(Wal.Batch{muts_of_entries(entries)}))

def parse.frame(
  result: Result<&1, &1, Wal.Error, Wal.Batch>
) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match result:
    case Fail{_}:
      None{}
    case Done{Wal.Batch{muts}}:
      Some{entries_of_muts(muts)}

def parse.hex(value: Maybe<&1, Bytes.Bytes>) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match value:
    case None{}:
      None{}
    case Some{bytes}:
      parse.frame(Wal.decode_frame(bytes))

def parse.payload(payload: String, valid: Bool) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match valid:
    case True{}:
      parse.hex(Bytes.from_hex(payload))
    case False{}:
      None{}

def parse.parts(parts: List<&2, String>) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match parts:
    case Con{marker, Con{payload, Nil{}}}:
      parse.payload(payload, String.eq(marker, version_marker()))
    case _:
      None{}

# Handle parse in the portable interchange format.
def parse(str: String) -> Maybe<&2, List<&2, MemTable.Entry>>:
  parse.parts(String.split(str, ':'))
