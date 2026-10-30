import Base
import ../Keys.bend as Keys
import ../ResourceOptions.bend as ResourceOptions
import ../ByteMemTable.bend as ByteMemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries the state for Decision.
type Decision is Data:
  Parsed{options: ResourceOptions.Options}
  Malformed{}
  UnsupportedVersion{version: U32}
  InvalidOptions{}

# Handles word.
def word(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

def magic.value(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(4)

# Handles magic.
def magic() -> Bytes.Bytes:
  magic.value(Bytes.from_hex("4d4c4f36"))

def encode.transport(limits: ResourceOptions.TransportLimits) -> Bytes.Bytes:
  match limits:
    case ResourceOptions.TransportLimits{connections, frame_bytes,
      receive_bytes, response_bytes, frame_timeout_ms, response_timeout_ms}:
      Bytes.concat([word(connections), word(frame_bytes), word(receive_bytes),
        word(response_bytes), word(frame_timeout_ms), word(response_timeout_ms)])

def encode.queue(limits: ResourceOptions.QueueLimits) -> Bytes.Bytes:
  match limits:
    case ResourceOptions.QueueLimits{requests, bytes, timeout_ms}:
      Bytes.concat([word(requests), word(bytes), word(timeout_ms)])

def encode.readers(limits: ResourceOptions.ReaderLimits) -> Bytes.Bytes:
  match limits:
    case ResourceOptions.ReaderLimits{snapshots, cursors,
      cursors_per_snapshot, retained_root_bytes, retired_files,
      index_page_bytes, index_buffer_bytes, restore_bytes}:
      Bytes.concat([word(snapshots), word(cursors), word(cursors_per_snapshot),
        word(retained_root_bytes), word(retired_files), word(index_page_bytes),
        word(index_buffer_bytes), word(restore_bytes)])

# Handles encode.
def encode(options: ResourceOptions.Options) -> Bytes.Bytes:
  match options:
    case ResourceOptions.Options{transport, queue, readers}:
      Bytes.concat([magic(), word(1), encode.transport(transport),
        encode.queue(queue), encode.readers(readers)])

def read.word.result(pair: Bytes.Bytes & Maybe<&2, U32>) -> U32:
  match pair:
    case (_, None{}): 0
    case (_, Some{word}): word

def read.word(input: Bytes.Bytes, offset: U32) -> U32:
  read.word.result(Bytes.get.u32be(input, offset))

def read.fields(
  remaining: Nat,
  input: Bytes.Bytes & Bytes.Bytes,
  +offset: U32,
  fields: List<&2, U32>
) -> List<&2, U32>:
  match remaining:
    case 0n:
      match input:
        case (_, _): fields
    case 1n+rest:
      match input:
        case (to_read, retained):
          read.fields(rest, ByteMemTable.bytes.clone(retained),
            U32.add(offset, 4), Con{read.word(to_read, offset), fields})

def fields.of.options(options: ResourceOptions.Options) -> List<&2, U32>:
  match options:
    case ResourceOptions.Options{transport, queue, readers}:
      match transport:
        case ResourceOptions.TransportLimits{connections, frame_bytes,
          receive_bytes, response_bytes, frame_timeout_ms, response_timeout_ms}:
          match queue:
            case ResourceOptions.QueueLimits{requests, queue_bytes,
              queue_timeout_ms}:
              match readers:
                case ResourceOptions.ReaderLimits{snapshots, cursors,
                  cursors_per_snapshot, retained_root_bytes, retired_files,
                  index_page_bytes, index_buffer_bytes, restore_bytes}:
                  Con{restore_bytes, Con{index_buffer_bytes,
                    Con{index_page_bytes, Con{retired_files,
                    Con{retained_root_bytes, Con{cursors_per_snapshot,
                    Con{cursors, Con{snapshots, Con{queue_timeout_ms,
                    Con{queue_bytes, Con{requests, Con{response_timeout_ms,
                    Con{frame_timeout_ms, Con{response_bytes,
                    Con{receive_bytes, Con{frame_bytes,
                    Con{connections, Nil{}}}}}}}}}}}}}}}}}}

def options.from.fields(
  fields: List<&2, U32>
) -> Maybe<&2, ResourceOptions.Options>:
  match fields:
    case Con{restore_bytes, Con{index_buffer_bytes,
      Con{index_page_bytes, Con{retired_files,
      Con{retained_root_bytes, Con{cursors_per_snapshot,
      Con{cursors, Con{snapshots, Con{queue_timeout_ms,
      Con{queue_bytes, Con{requests, Con{response_timeout_ms,
      Con{frame_timeout_ms, Con{response_bytes, Con{receive_bytes,
      Con{frame_bytes, Con{connections, Nil{}}}}}}}}}}}}}}}}}}:
      Some{ResourceOptions.Options{
        ResourceOptions.TransportLimits{connections, frame_bytes,
          receive_bytes, response_bytes, frame_timeout_ms,
          response_timeout_ms},
        ResourceOptions.QueueLimits{requests, queue_bytes, queue_timeout_ms},
        ResourceOptions.ReaderLimits{snapshots, cursors,
          cursors_per_snapshot, retained_root_bytes, retired_files,
          index_page_bytes, index_buffer_bytes, restore_bytes}}}
    case _: None{}

def validated.result(result: ResourceOptions.Decision) -> Decision:
  match result:
    case ResourceOptions.Accepted{options}: Parsed{options}
    case _: InvalidOptions{}

# Handles validated.
def validated(options: ResourceOptions.Options) -> Decision:
  validated.result(ResourceOptions.validate(options))

def fields.options(
  result: Maybe<&2, ResourceOptions.Options>
) -> Decision:
  match result:
    case None{}: Malformed{}
    case Some{options}: validated(options)

def fields.result(fields: List<&2, U32>) -> Decision:
  fields.options(options.from.fields(fields))

# Handles fields.
def fields(input: Bytes.Bytes) -> Decision:
  fields.result(read.fields(17n, ByteMemTable.bytes.clone(input), 8, Nil{}))

def u32.duplicate.pair(+value: U32) -> U32 & U32:
  (value, value)

def version.classified(input: Bytes.Bytes, version: U32,
  supported: Bool) -> Decision:
  match supported:
    case True{}: fields(input)
    case False{}: UnsupportedVersion{version}

def version.checked(input: Bytes.Bytes, pair: U32 & U32) -> Decision:
  match pair:
    case (version, check):
      version.classified(input, version, U32.is_eq(check, 1))

def version.result(pair: Bytes.Bytes & Maybe<&2, U32>) -> Decision:
  match pair:
    case (_, None{}): Malformed{}
    case (retained, Some{version_code}):
      version.checked(retained, u32.duplicate.pair(version_code))

def version.read(pair: Bytes.Bytes & Bytes.Bytes) -> Decision:
  match pair:
    case (to_read, retained):
      version.result(Bytes.get.u32be(to_read, 4))

def magic.checked(input: Bytes.Bytes, matches: Bool) -> Decision:
  match matches:
    case True{}: version.read(ByteMemTable.bytes.clone(input))
    case False{}: Malformed{}

def magic.candidate(pair: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match pair:
    case (_, candidate): Keys.Bytes.eq(candidate, magic())

def magic.matches(pair: Bytes.Bytes & Bytes.Bytes) -> Decision:
  match pair:
    case (magic_source, retained):
      magic.checked(retained, magic.candidate(Bytes.slice(magic_source, 0, 4)))

def sized.result(input: Bytes.Bytes, valid: Bool) -> Decision:
  match valid:
    case False{}: Malformed{}
    case True{}:
      magic.matches(ByteMemTable.bytes.clone(input))

# Handles sized.
def sized(input: Bytes.Bytes, size: U32) -> Decision:
  sized.result(input, U32.is_eq(size, 76))

# Handles measured.
def measured(measured: Bytes.Bytes & U32) -> Decision:
  match measured:
    case (input, size): sized(input, size)

# Handles decode.
def decode(input: Bytes.Bytes) -> Decision:
  measured(Bytes.length(input))

def hex.decoded.result(bytes: Bytes.Bytes, canonical: Bool) -> Decision:
  match canonical:
    case True{}: decode(bytes)
    case False{}: Malformed{}

def hex.decoded.cloned(input: String,
  copies: Bytes.Bytes & Bytes.Bytes) -> Decision:
  match copies:
    case (canonical_bytes, parse_bytes):
      hex.decoded.result(parse_bytes,
        String.eq(Bytes.to_hex(canonical_bytes), input))

def hex.decoded(input: String,
  result: Maybe<&1, Bytes.Bytes>) -> Decision:
  match result:
    case None{}: Malformed{}
    case Some{bytes}:
      hex.decoded.cloned(input, ByteMemTable.bytes.clone(bytes))

def string.clone.pair.go(value: String, left: String,
  right: String) -> String & String:
  match value:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      string.clone.pair.go(rest, SCon{character, left},
        SCon{character, right})

def string.clone.pair(value: String) -> String & String:
  string.clone.pair.go(value, SNil{}, SNil{})

def string.clone.triple.second(length_input: String,
  parse_inputs: String & String) -> String & (String & String):
  match parse_inputs:
    case (canonical_input, decode_input):
      (length_input, (canonical_input, decode_input))

def string.clone.triple.first(copies: String & String) -> String & (String & String):
  match copies:
    case (length_input, parse_input):
      string.clone.triple.second(length_input,
        string.clone.pair(parse_input))

def string.clone.triple(value: String) -> String & (String & String):
  string.clone.triple.first(string.clone.pair(value))

def decode.hex.sized(input: String & String, valid: Bool) -> Decision:
  match input:
    case (canonical_input, decode_input):
      match valid:
        case True{}:
          hex.decoded(canonical_input, Bytes.from_hex(decode_input))
        case False{}: Malformed{}

def decode.hex.copies(copies: String & (String & String)) -> Decision:
  match copies:
    case (length_input, (canonical_input, decode_input)):
      decode.hex.sized((canonical_input, decode_input),
        Nat.is_eq(String.length(length_input), 152n))

def decode.hex(input: String) -> Decision:
  decode.hex.copies(string.clone.triple(input))
