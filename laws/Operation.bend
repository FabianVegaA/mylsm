import Base
import ../src/coordinator/Operation.bend as Operation
import ../src/ByteWal.bend as ByteWal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

def bytes.fixture(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def put.roundtrips(
  key: Bytes.Bytes,
  value: Bytes.Bytes,
  decision: Operation.Decision
) -> Bool:
  match decision:
    case Operation.Decoded{Operation.Put{decoded_key, decoded_value}}:
      bytes.equal(Bytes.eq(key, decoded_key)) &&
        bytes.equal(Bytes.eq(value, decoded_value))
    case _: False{}

def get.roundtrips(key: Bytes.Bytes, decision: Operation.Decision) -> Bool:
  match decision:
    case Operation.Decoded{Operation.Get{decoded_key}}:
      bytes.equal(Bytes.eq(key, decoded_key))
    case _: False{}

def delete.roundtrips(key: Bytes.Bytes, decision: Operation.Decision) -> Bool:
  match decision:
    case Operation.Decoded{Operation.Delete{decoded_key}}:
      bytes.equal(Bytes.eq(key, decoded_key))
    case _: False{}

# Decodes the argument-free flush operation.
law empty_flush_is_decoded:
  {Operation.decode.payload(4, Bytes.new(0)) == Operation.Decoded{Operation.Flush{}} : Operation.Decision}

# Rejects flush arguments instead of silently ignoring trailing bytes.
law nonempty_flush_is_rejected:
  {Operation.decode.payload(4, Bytes.new(1)) == Operation.MalformedArguments{} : Operation.Decision}

# Reports unknown operation tags without dispatching them.
law unknown_operation_is_reported:
  {Operation.decode.payload(99, Bytes.new(0)) == Operation.UnsupportedOperation{} : Operation.Decision}

# Preserves the complete binary key and value in a put payload.
law put_payload_roundtrips:
  {put.roundtrips(bytes.fixture(Bytes.from_hex("00ff")), bytes.fixture(Bytes.from_hex("807f00")),
    Operation.decode.payload(2, Operation.encode.put(bytes.fixture(Bytes.from_hex("00ff")), bytes.fixture(Bytes.from_hex("807f00"))))) == True{} : Bool}

# Decodes get keys without UTF-8 conversion.
law get_keeps_raw_key_bytes:
  {get.roundtrips(bytes.fixture(Bytes.from_hex("00ff")),
    Operation.decode.payload(1, bytes.fixture(Bytes.from_hex("00ff")))) == True{} : Bool}

# Decodes delete keys without UTF-8 conversion.
law delete_keeps_raw_key_bytes:
  {delete.roundtrips(bytes.fixture(Bytes.from_hex("00ff")),
    Operation.decode.payload(3, bytes.fixture(Bytes.from_hex("00ff")))) == True{} : Bool}

# Rejects a put frame that omits required length fields.
law incomplete_put_header_is_rejected:
  {Operation.decode.payload(2, Bytes.new(7)) == Operation.MalformedArguments{} : Operation.Decision}

# Rejects a put frame whose declared lengths do not match its payload.
law mismatched_put_length_is_rejected:
  {Operation.decode.payload(2, Bytes.concat([
    Operation.u32.bytes(1), Operation.u32.bytes(1), bytes.fixture(Bytes.from_hex("41"))])) ==
    Operation.MalformedArguments{} : Operation.Decision}

# Rejects a batch payload that is not a checksummed byte WAL frame.
law malformed_write_batch_is_rejected:
  {Operation.decode.payload(8, Bytes.new(0)) ==
    Operation.MalformedArguments{} : Operation.Decision}

# Retains decoded byte mutations as one atomic owner operation.
law decoded_batch_keeps_mutation_list:
  {Operation.batch.result(Done{ByteWal.Batch{Nil{}}}) ==
    Operation.Decoded{Operation.WriteBatch{Nil{}}} : Operation.Decision}
