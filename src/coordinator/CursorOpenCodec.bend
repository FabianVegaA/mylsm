import Base
import ./Protocol.bend as Protocol
import ../scan/RangeCursor.bend as RangeCursor
import ../ByteMemTable.bend as ByteMemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries one exact range or prefix request for an owner snapshot cursor.
type Request is Type:
  Request{snapshot_id: U32, bounds: RangeCursor.Bounds}

# Reports a decoded cursor-open request or malformed argument bytes.
type Decision is Type:
  Decoded{request: Request}
  Malformed{}

# Carries an input buffer, one parsed optional bound, and its next offset.
type BoundResult is Type:
  BoundParsed{source: Bytes.Bytes, value: Maybe<&1, Bytes.Bytes>, next: U32}
  BoundMalformed{}

# Carries both range bounds after parsing the lower bound.
type RangeResult is Type:
  RangeParsed{lower: Maybe<&1, Bytes.Bytes>,
    upper: Maybe<&1, Bytes.Bytes>, next: U32}
  RangeMalformed{}

# Encodes an absent bound with a reserved length outside the admitted frame cap.
def bound.absent() -> Bytes.Bytes:
  Protocol.u32.bytes(4294967295)

# Encodes one present bound as a length followed by its raw bytes.
def bound.present(measured: Bytes.Bytes & U32) -> Bytes.Bytes:
  match measured:
    case (value, length):
      Bytes.concat([Protocol.u32.bytes(length), value])

# Encodes an optional bound without interpreting or transforming its bytes.
def bound.encode(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case None{}: bound.absent()
    case Some{bytes}: bound.present(Bytes.length(bytes))

# Encodes one full range request with an owner snapshot token.
def encode.range(
  snapshot_id: U32,
  lower: Maybe<&1, Bytes.Bytes>,
  upper: Maybe<&1, Bytes.Bytes>
) -> Bytes.Bytes:
  Bytes.concat([Protocol.snapshot.id.bytes(snapshot_id),
    Protocol.u32.bytes(0), bound.encode(lower), bound.encode(upper)])

# Encodes one byte-prefix request with an owner snapshot token.
def encode.prefix(snapshot_id: U32, prefix: Bytes.Bytes) -> Bytes.Bytes:
  Bytes.concat([Protocol.snapshot.id.bytes(snapshot_id),
    Protocol.u32.bytes(1), bound.present(Bytes.length(prefix))])

# Copies a fixed-width word without recursion on its numeric value.
def u32.duplicate.triple(+value: U32) -> U32 & U32 & U32:
  (value, value, value)

# Duplicates one fixed-width word for two bounded offset calculations.
def u32.duplicate.pair(+value: U32) -> U32 & U32:
  (value, value)

# Retains the source buffer while storing one exact bound slice.
def field.sized.sliced(
  pair: Bytes.Bytes & Bytes.Bytes,
  next: U32
) -> BoundResult:
  match pair:
    case (source, value): BoundParsed{source, Some{value}, next}

# Slices a validated span using separate copies for its start and end offsets.
def field.sized.checked(
  payload: Bytes.Bytes,
  offsets: U32 & U32 & U32,
  lengths: U32 & U32,
  fits: Bool
) -> BoundResult:
  match offsets:
    case (slice_offset, (next_offset, _)):
      match lengths:
        case (slice_length, next_length):
          match fits:
            case True{}:
              field.sized.sliced(Bytes.slice(payload,
                U32.from_nat(Nat.add(U32.to_nat(slice_offset), 4n)),
                slice_length),
                U32.from_nat(Nat.add(Nat.add(U32.to_nat(next_offset), 4n),
                  U32.to_nat(next_length))))
            case False{}: BoundMalformed{}

# Selects a bounded raw-byte slice or rejects a span beyond the frame.
def field.sized.decision(
  payload: Bytes.Bytes,
  offset: U32,
  length: U32,
  fits: Bool
) -> BoundResult:
  field.sized.checked(payload,
    u32.duplicate.triple(offset), u32.duplicate.pair(length), fits)

# Separates validation inputs from the values passed to the slice decision.
def field.sized.inputs(
  payload: Bytes.Bytes,
  totals: U32 & U32,
  offsets: U32 & U32,
  lengths: U32 & U32
) -> BoundResult:
  match totals:
    case (_, check_total):
      match offsets:
        case (slice_offset, check_offset):
          match lengths:
            case (slice_length, check_length):
              field.sized.decision(payload, slice_offset, slice_length,
                Nat.is_le(Nat.add(Nat.add(U32.to_nat(check_offset), 4n),
                  U32.to_nat(check_length)), U32.to_nat(check_total)))

# Validates the payload span before slicing one present bound.
def field.sized(
  payload: Bytes.Bytes,
  total: U32,
  offset: U32,
  length: U32
) -> BoundResult:
  field.sized.inputs(payload, u32.duplicate.pair(total),
    u32.duplicate.pair(offset),
    u32.duplicate.pair(length))

# Selects the absent sentinel or a validated present bound.
def field.value.decision(
  payload: Bytes.Bytes,
  total: U32,
  offset: U32,
  length: U32,
  absent: Bool
) -> BoundResult:
  match absent:
    case True{}:
      BoundParsed{payload, None{}, U32.from_nat(
        Nat.add(U32.to_nat(offset), 4n))}
    case False{}:
      field.sized(payload, total, offset, length)

# Separates the sentinel check from the length passed to the bound parser.
def field.value.inputs(
  payload: Bytes.Bytes,
  total: U32,
  offset: U32,
  lengths: U32 & U32
) -> BoundResult:
  match lengths:
    case (bound_length, check_length):
      field.value.decision(payload, total, offset, bound_length,
        U32.is_eq(check_length, 4294967295))

# Converts one field length into a bounded slice or an absent bound.
def field.value(
  payload: Bytes.Bytes,
  total: U32,
  offset: U32,
  length: U32
) -> BoundResult:
  field.value.inputs(payload, total, offset, u32.duplicate.pair(length))

# Checks that one field's four-byte length is available at its offset.
def field.length(
  payload: Bytes.Bytes,
  total: U32,
  offset: U32,
  parsed: Maybe<&2, U32>
) -> BoundResult:
  match parsed:
    case None{}: BoundMalformed{}
    case Some{length}:
      field.value(payload, total, offset, length)

# Parses one optional bound length from the supplied offset.
def field.read.parsed(
  payload: Bytes.Bytes,
  total: U32,
  offset: U32,
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> BoundResult:
  match pair:
    case (_, parsed): field.length(payload, total, offset, parsed)

# Keeps one source for slicing while reading its fixed-width length field.
def field.read.copies(
  sources: Bytes.Bytes & Bytes.Bytes,
  total: U32,
  offsets: U32 & U32
) -> BoundResult:
  match sources:
    case (payload, measured):
      match offsets:
        case (slice_offset, read_offset):
          field.read.parsed(payload, total, slice_offset,
            Bytes.get.u32be(measured, read_offset))

# Parses one optional bound length from the supplied offset.
def field.read(
  payload: Bytes.Bytes,
  total: U32,
  offset: U32
) -> BoundResult:
  field.read.copies(ByteMemTable.bytes.clone(payload), total,
    u32.duplicate.pair(offset))

# Combines both successfully parsed range bounds.
def range.upper.result(
  result: BoundResult,
  lower: Maybe<&1, Bytes.Bytes>
) -> RangeResult:
  match result:
    case BoundMalformed{}: RangeMalformed{}
    case BoundParsed{_, upper, next}:
      RangeParsed{lower, upper, next}

# Reads the upper field from the source retained by lower-bound parsing.
def range.upper.read(
  source: Bytes.Bytes,
  total: U32,
  lower: Maybe<&1, Bytes.Bytes>,
  offset: U32
) -> RangeResult:
  range.upper.result(field.read(source, total, offset), lower)

# Parses the upper bound after preserving the lower-bound result.
def range.upper(
  lower_result: BoundResult,
  total: U32
) -> RangeResult:
  match lower_result:
    case BoundMalformed{}: RangeMalformed{}
    case BoundParsed{source, lower, next}:
      range.upper.read(source, total, lower, next)

# Rejects trailing bytes or returns the decoded range cursor request.
def range.finish.exact(
  exact: Bool,
  snapshot_id: U32,
  lower: Maybe<&1, Bytes.Bytes>,
  upper: Maybe<&1, Bytes.Bytes>
) -> Decision:
  match exact:
    case True{}:
      Decoded{Request{snapshot_id,
        RangeCursor.Bounds{lower, upper, None{}}}}
    case False{}: Malformed{}

# Builds a range request only when its fields consume the entire frame.
def range.finish(
  parsed: RangeResult,
  snapshot_id: U32,
  total: U32
) -> Decision:
  match parsed:
    case RangeMalformed{}: Malformed{}
    case RangeParsed{lower, upper, next}:
      range.finish.exact(U32.is_eq(next, total), snapshot_id, lower, upper)

# Parses range bounds with separate total lengths for IO-free validation.
def range.decode.totals(
  payload: Bytes.Bytes,
  snapshot_id: U32,
  totals: U32 & U32 & U32
) -> Decision:
  match totals:
    case (read_total, (upper_total, finish_total)):
      range.finish(range.upper(field.read(payload, read_total, 8), upper_total),
        snapshot_id, finish_total)

# Parses both optional bounds and requires an exact request boundary.
def range.decode(
  payload: Bytes.Bytes,
  snapshot_id: U32,
  total: U32
) -> Decision:
  range.decode.totals(payload, snapshot_id,
    u32.duplicate.triple(total))

# Rejects trailing bytes or returns the decoded prefix cursor request.
def prefix.finish.exact(
  exact: Bool,
  snapshot_id: U32,
  prefix: Bytes.Bytes
) -> Decision:
  match exact:
    case True{}:
      Decoded{Request{snapshot_id,
        RangeCursor.Bounds{None{}, None{}, Some{prefix}}}}
    case False{}: Malformed{}

# Builds a prefix request only when its field consumes the remaining frame.
def prefix.finish(
  parsed: BoundResult,
  snapshot_id: U32,
  total: U32
) -> Decision:
  match parsed:
    case BoundMalformed{}: Malformed{}
    case BoundParsed{_, Some{prefix}, next}:
      prefix.finish.exact(U32.is_eq(next, total), snapshot_id, prefix)
    case BoundParsed{_, None{}, _}: Malformed{}

# Parses prefix bounds with separate lengths for reading and validation.
def prefix.decode.totals(
  payload: Bytes.Bytes,
  snapshot_id: U32,
  totals: U32 & U32
) -> Decision:
  match totals:
    case (read_total, finish_total):
      prefix.finish(field.read(payload, read_total, 8), snapshot_id, finish_total)

# Parses one present prefix bound and requires an exact request boundary.
def prefix.decode(
  payload: Bytes.Bytes,
  snapshot_id: U32,
  total: U32
) -> Decision:
  prefix.decode.totals(payload, snapshot_id, u32.duplicate.pair(total))

# Selects range or prefix decoding from the exact mode word.
def mode(
  payload: Bytes.Bytes,
  snapshot_id: U32,
  total: U32,
  parsed: Maybe<&2, U32>
) -> Decision:
  match parsed:
    case Some{0}: range.decode(payload, snapshot_id, total)
    case Some{1}: prefix.decode(payload, snapshot_id, total)
    case _: Malformed{}

# Requires the mode field to exist before selecting a cursor-open shape.
def mode.read.parsed(
  payload: Bytes.Bytes,
  snapshot_id: U32,
  total: U32,
  parsed: Maybe<&2, U32>
) -> Decision:
  mode(payload, snapshot_id, total, parsed)

# Projects one fixed-width mode parse while retaining its request source.
def mode.read.field(
  payload: Bytes.Bytes,
  snapshot_id: U32,
  total: U32,
  field: Bytes.Bytes & Maybe<&2, U32>
) -> Decision:
  match field:
    case (_, parsed): mode.read.parsed(payload, snapshot_id, total, parsed)

# Reads the mode from a copy while retaining the request for bound slicing.
def mode.read.copies(
  sources: Bytes.Bytes & Bytes.Bytes,
  snapshot_id: U32,
  total: U32
) -> Decision:
  match sources:
    case (payload, reader):
      mode.read.field(payload, snapshot_id, total,
        Bytes.get.u32be(reader, 4))

# Requires the mode field to exist before selecting a cursor-open shape.
def mode.read(
  payload: Bytes.Bytes,
  snapshot_id: U32,
  total: U32,
  enough: Bool
) -> Decision:
  match enough:
    case True{}:
      mode.read.copies(ByteMemTable.bytes.clone(payload), snapshot_id, total)
    case False{}: Malformed{}

# Decodes an owner token followed by one supported cursor-open mode.
def decode.payload.inputs(
  payload: Bytes.Bytes,
  totals: U32 & U32,
  parsed: Maybe<&2, U32>
) -> Decision:
  match totals:
    case (mode_total, check_total):
      match parsed:
        case Some{snapshot_id}:
          mode.read(payload, snapshot_id, mode_total,
            U32.is_le(8, check_total))
        case None{}: Malformed{}

# Decodes an owner token followed by one supported cursor-open mode.
def decode.payload(
  payload: Bytes.Bytes,
  total: U32,
  parsed: Maybe<&2, U32>
) -> Decision:
  decode.payload.inputs(payload, u32.duplicate.pair(total), parsed)

# Projects one snapshot-token parse while retaining the full request.
def decode.payload.field(
  payload: Bytes.Bytes,
  total: U32,
  field: Bytes.Bytes & Maybe<&2, U32>
) -> Decision:
  match field:
    case (_, parsed): decode.payload(payload, total, parsed)

# Decodes an owner token from one input copy and retains another for mode parsing.
def decode.payload.copies(
  sources: Bytes.Bytes & Bytes.Bytes,
  total: U32
) -> Decision:
  match sources:
    case (payload, reader):
      decode.payload.field(payload, total, Bytes.get.u32be(reader, 0))

# Decodes one bounded cursor-open request without interpreting its bytes.
def decode.measured(measured: Bytes.Bytes & U32) -> Decision:
  match measured:
    case (payload, total):
      decode.payload.copies(ByteMemTable.bytes.clone(payload), total)

# Decodes a full-range or prefix request from its exact wire payload.
def decode(payload: Bytes.Bytes) -> Decision:
  decode.measured(Bytes.length(payload))
