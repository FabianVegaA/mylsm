import Base
import ../src/MemTable.bend as MemTable
import ../src/Wal.bend as Wal
import ../src/Manifest.bend as Manifest

# Pure deterministic interchange format:
#   MYLSM-EXPORT-1:<unary payload length>:<WAL payload>#<decimal mhash>
#
# The WAL payload is already length-framed per key/value, so every String
# character is opaque data. The outer unary length rejects truncation and
# trailing payload bytes. The checksum covers everything before the final '#'.

def version_marker() -> String:
  "MYLSM-EXPORT-1"

def bool_and(lhs: Bool, rhs: Bool) -> Bool:
  match lhs:
    case True{}:
      rhs
    case False{}:
      False{}

def all_dash(str: String) -> Bool:
  match str:
    case SNil{}:
      True{}
    case SCon{h, t}:
      bool_and(Char.is_eq(h, '-'), all_dash(t))

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

def entries_of_muts(ms: List<&2, Wal.Mut>) -> List<&2, MemTable.Entry>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{m, t}:
      match m:
        case Wal.Put{key, val}:
          Con{MemTable.Entry{key, Some{val}}, entries_of_muts(t)}
        case Wal.Del{key}:
          Con{MemTable.Entry{key, None{}}, entries_of_muts(t)}

def serialize(+entries: List<&2, MemTable.Entry>) -> String:
  +payload = Wal.encode(Wal.Batch{muts_of_entries(entries)})
  +body = version_marker() ++ ":" ++ Wal.dashes(String.length(payload)) ++ ":" ++ payload
  body ++ "#" ++ U32.show(Manifest.mhash(body, 7))

def checksum_value(+read: Maybe<&2, U32>, chk: String, body: String) -> Bool:
  match read:
    case None{}:
      False{}
    case Some{+got}:
      bool_and(String.eq(chk, U32.show(got)), U32.is_eq(got, Manifest.mhash(body, 7)))

def checksum_ok(+chk: String, body: String) -> Bool:
  checksum_value(U32.read(chk), chk, body)

def entries_if(ok: Bool, decoded: Maybe<&2, Wal.Batch>) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match ok:
    case False{}:
      None{}
    case True{}:
      match decoded:
        case None{}:
          None{}
        case Some{Wal.Batch{muts}}:
          Some{entries_of_muts(muts)}

def decode_payload(+mark: String, +lens: String, +payload: String) -> Maybe<&2, List<&2, MemTable.Entry>>:
  +shape_ok = bool_and(
    String.eq(mark, version_marker()),
    bool_and(all_dash(lens), Nat.is_eq(String.length(lens), String.length(payload)))
  )
  entries_if(shape_ok, Wal.decode(payload))

def parse_body_parts(parts: List<&2, String>) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match parts:
    case Con{mark, Con{lens, Con{payload_head, payload_tail}}}:
      decode_payload(mark, lens, String.join(Con{payload_head, payload_tail}, ":"))
    case _:
      None{}

def parse_body(body: String) -> Maybe<&2, List<&2, MemTable.Entry>>:
  parse_body_parts(String.split(body, ':'))

def split_last_hash(parts: List<&2, String>, acc: List<&2, String>) -> (List<&2, String> & String):
  match parts:
    case Nil{}:
      (List.reverse(&2, String, acc), "")
    case Con{h, Nil{}}:
      (List.reverse(&2, String, acc), h)
    case Con{h, Con{k, t}}:
      split_last_hash(Con{k, t}, Con{h, acc})

def parse_checked(ok: Bool, body: String) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match ok:
    case False{}:
      None{}
    case True{}:
      parse_body(body)

def parse_split(pair: (List<&2, String> & String)) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match pair:
    case (body_parts, chk):
      +body = String.join(body_parts, "#")
      parse_checked(checksum_ok(chk, body), body)

def parse(str: String) -> Maybe<&2, List<&2, MemTable.Entry>>:
  parse_split(split_last_hash(String.split(str, '#'), Nil{}))
