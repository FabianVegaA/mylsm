import Base
import ../ByteMemTable.bend as ByteMemTable
import ../ByteWal.bend as ByteWal
import ../Wal.bend as Wal
import ./Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Represents a decoded byte-oriented owner database operation.
type Operation is Type:
  Get{key: Bytes.Bytes}
  Put{key: Bytes.Bytes, value: Bytes.Bytes}
  Delete{key: Bytes.Bytes}
  WriteBatch{mutations: List<&1, ByteWal.Mutation>}
  Flush{}
  Compact{}
  Stats{}
  SnapshotOpen{}

# Reports decoded arguments or a malformed/unsupported operation.
type Decision is Type:
  Decoded{operation: Operation}
  MalformedArguments{}
  UnsupportedOperation{}

def bytes.triple.second(
  first: Bytes.Bytes,
  pair: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (second, third): (first, second, third)

def bytes.triple.pair(
  pair: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (first, second):
      bytes.triple.second(first, ByteMemTable.bytes.clone(second))

def bytes.triple(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  bytes.triple.pair(ByteMemTable.bytes.clone(bytes))

def put.result(
  key: Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes & Bytes.Bytes
) -> Decision:
  match key:
    case (_, owned_key):
      match value:
        case (_, owned_value): Decoded{Put{owned_key, owned_value}}

def put.sliced(
  copies: Bytes.Bytes & Bytes.Bytes,
  key_lengths: U32 & U32,
  value_lengths: U32 & U32
) -> Decision:
  match copies:
    case (key_source, value_source):
      match key_lengths:
        case (key_length, key_offset):
          match value_lengths:
            case (value_length, _):
              put.result(Bytes.slice(key_source, 8, key_length),
                Bytes.slice(value_source, (8 + key_offset : U32), value_length))

def put.bound.result(
  valid: Bool,
  payload: Bytes.Bytes,
  key_lengths: U32 & U32,
  value_lengths: U32 & U32
) -> Decision:
  match valid:
    case False{}: MalformedArguments{}
    case True{}:
      put.sliced(ByteMemTable.bytes.clone(payload), key_lengths, value_lengths)

def put.bound.checked(
  payload: Bytes.Bytes,
  actual_length: U32,
  key_lengths: U32 & U32 & U32,
  value_lengths: U32 & U32 & U32
) -> Decision:
  match key_lengths:
    case (key_check, (key_length, key_offset)):
      match value_lengths:
        case (value_check, (value_length, value_copy)):
          put.bound.result(
            Nat.is_eq(U32.to_nat(actual_length),
              Nat.add(8n, Nat.add(U32.to_nat(key_check),
                U32.to_nat(value_check)))),
            payload, (key_length, key_offset), (value_length, value_copy))

def put.measure(
  pair: Bytes.Bytes & U32,
  key_lengths: U32 & U32 & U32,
  value_lengths: U32 & U32 & U32
) -> Decision:
  match pair:
    case (payload, actual_length):
      put.bound.checked(payload, actual_length, key_lengths, value_lengths)

def put.value.parsed(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  measure: Bytes.Bytes,
  key_length: U32
) -> Decision:
  match pair:
    case (_, Some{value_length}):
      put.measure(Bytes.length(measure),
        Protocol.u32.duplicate.triple(key_length),
        Protocol.u32.duplicate.triple(value_length))
    case _: MalformedArguments{}

def put.value.length.keyed(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  measure: Bytes.Bytes
) -> Decision:
  match pair:
    case (value_head, Some{key_length}):
      put.value.parsed(Bytes.get.u32be(value_head, 4), measure, key_length)
    case _: MalformedArguments{}

def put.decode.copies(copies: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes) -> Decision:
  match copies:
    case (key_head, (value_head, measure)):
      put.value.length.keyed(Bytes.get.u32be(key_head, 0), measure)

def put.decode(payload: Bytes.Bytes) -> Decision:
  put.decode.copies(bytes.triple(payload))

def empty.result(
  is_empty: Bool,
  operation: Operation
) -> Decision:
  match is_empty:
    case True{}: Decoded{operation}
    case False{}: MalformedArguments{}

def empty.operation(
  pair: Bytes.Bytes & U32,
  operation: Operation
) -> Decision:
  match pair:
    case (_, length): empty.result(U32.is_eq(length, 0), operation)

def batch.result(
  decoded: Result<&1, &1, Wal.Error, ByteWal.Batch>
) -> Decision:
  match decoded:
    case Fail{_}: MalformedArguments{}
    case Done{ByteWal.Batch{mutations}}:
      Decoded{WriteBatch{mutations}}

def decode.payload(
  operation_code: U32,
  payload: Bytes.Bytes
) -> Decision:
  match operation_code:
    case 1: Decoded{Get{payload}}
    case 2: put.decode(payload)
    case 3: Decoded{Delete{payload}}
    case 4: empty.operation(Bytes.length(payload), Flush{})
    case 5: empty.operation(Bytes.length(payload), Compact{})
    case 6: empty.operation(Bytes.length(payload), Stats{})
    case 9: empty.operation(Bytes.length(payload), SnapshotOpen{})
    case 8: batch.result(ByteWal.decode(payload))
    case _: UnsupportedOperation{}

# Decodes the tagged operation payload without interpreting keys as text.
def decode(request: Protocol.Request) -> Decision:
  match request:
    case Protocol.Request{_, _, _, operation, payload}:
      decode.payload(operation, payload)

def u32.bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

def encode.put.sized(
  key_pair: Bytes.Bytes & U32,
  value_pair: Bytes.Bytes & U32
) -> Bytes.Bytes:
  match key_pair:
    case (key, key_length):
      match value_pair:
        case (value, value_length):
          Bytes.concat([u32.bytes(key_length), u32.bytes(value_length), key, value])

def encode.put(key: Bytes.Bytes, value: Bytes.Bytes) -> Bytes.Bytes:
  encode.put.sized(Bytes.length(key), Bytes.length(value))
