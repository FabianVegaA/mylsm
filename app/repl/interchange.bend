import Base
import ../../src/StorageBytes.bend as StorageBytes
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Holds one exported key and its live value.
type Record is Data:
  Record{key: String, value: String}

# Names the export format on the first line of every export file.
def version_marker() -> String:
  "MYLSM-EXPORT-3"

def hex.encoded(result: Result<&1, &1, U32 & String, Bytes.Bytes>) -> Result<&1, &1, U32 & String, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{bytes}: Done{Bytes.to_hex(bytes)}

# Encodes text as hexadecimal UTF-8.
def hex(+text: String) -> Result<&1, &1, U32 & String, String>:
  hex.encoded(StorageBytes.from_string(text))

def line.joined(
  key: Result<&1, &1, U32 & String, String>,
  value: Result<&1, &1, U32 & String, String>
) -> Result<&1, &1, U32 & String, String>:
  match key:
    case Fail{error}: Fail{error}
    case Done{key_hex}:
      match value:
        case Fail{error}: Fail{error}
        case Done{value_hex}: Done{key_hex ++ " " ++ value_hex ++ "\n"}

# Encodes one record as a key and value line.
def line(record: Record) -> Result<&1, &1, U32 & String, String>:
  match record:
    case Record{key, value}: line.joined(hex(key), hex(value))

def lines.appended(
  head: Result<&1, &1, U32 & String, String>,
  tail: Result<&1, &1, U32 & String, String>
) -> Result<&1, &1, U32 & String, String>:
  match head:
    case Fail{error}: Fail{error}
    case Done{text}:
      match tail:
        case Fail{error}: Fail{error}
        case Done{rest}: Done{text ++ rest}

# Encodes every record, one per line.
def lines(records: List<&2, Record>) -> Result<&1, &1, U32 & String, String>:
  match records:
    case Nil{}: Done{""}
    case Con{record, rest}: lines.appended(line(record), lines(rest))

def serialize.lines(body: Result<&1, &1, U32 & String, String>) -> Result<&1, &1, U32 & String, String>:
  match body:
    case Fail{error}: Fail{error}
    case Done{text}: Done{version_marker() ++ "\n" ++ text}

# Writes records as the marker line followed by one hex key and value per line.
def serialize(records: List<&2, Record>) -> Result<&1, &1, U32 & String, String>:
  serialize.lines(lines(records))

def text.decoded(result: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match result:
    case Fail{_}: None{}
    case Done{text}: Some{text}

def text.of(bytes: Maybe<&1, Bytes.Bytes>) -> Maybe<&2, String>:
  match bytes:
    case None{}: None{}
    case Some{value}: text.decoded(StorageBytes.to_string_strict(value))

def record.of(key: Maybe<&2, String>, value: Maybe<&2, String>) -> Maybe<&2, Record>:
  match key:
    case None{}: None{}
    case Some{text}:
      match value:
        case None{}: None{}
        case Some{content}: Some{Record{text, content}}

def record.parts(parts: List<&2, String>) -> Maybe<&2, Record>:
  match parts:
    case Con{key, Con{value, Nil{}}}:
      record.of(text.of(Bytes.from_hex(key)), text.of(Bytes.from_hex(value)))
    case _: None{}

def records.pushed(
  record: Maybe<&2, Record>,
  rest: Maybe<&2, List<&2, Record>>
) -> Maybe<&2, List<&2, Record>>:
  match record:
    case None{}: None{}
    case Some{value}:
      match rest:
        case None{}: None{}
        case Some{tail}: Some{Con{value, tail}}

def records.line(line: String, rest: Maybe<&2, List<&2, Record>>) -> Maybe<&2, List<&2, Record>>:
  match line:
    case SNil{}: rest
    case SCon{character, tail}:
      records.pushed(record.parts(String.split(SCon{character, tail}, ' ')), rest)

# Decodes record lines, skipping empty ones and rejecting malformed ones.
def records(lines: List<&2, String>) -> Maybe<&2, List<&2, Record>>:
  match lines:
    case Nil{}: Some{Nil{}}
    case Con{line, rest}: records.line(line, records(rest))

def parse.marked(marked: Bool, rest: List<&2, String>) -> Maybe<&2, List<&2, Record>>:
  match marked:
    case True{}: records(rest)
    case False{}: None{}

def parse.lines(lines: List<&2, String>) -> Maybe<&2, List<&2, Record>>:
  match lines:
    case Nil{}: None{}
    case Con{first, rest}: parse.marked(String.eq(first, version_marker()), rest)

# Reads an export, rejecting any other version or malformed record line.
def parse(text: String) -> Maybe<&2, List<&2, Record>>:
  parse.lines(String.lines(text))
