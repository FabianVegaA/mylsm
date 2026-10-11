import Base
import ../coordinator/QueuePolicy.bend as QueuePolicy
import ../Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Reports a validated frame count or a malformed legacy WAL.
type VerifyResult is Data:
  WalValid{frames: Nat}
  WalInvalid{}

# Returns all validated legacy WAL batches in their durable order.
type ReplayResult is Data:
  ReplayValid{batches: List<&2, Wal.Batch>}
  ReplayInvalid{}

# Carries bounded offsets and decoded batches through read-only replay.
type ReplayState is Type:
  ReplayNeed{bytes: Bytes.Bytes, offset: Nat, batches: List<&2, Wal.Batch>}
  ReplayMeasured{bytes: Bytes.Bytes, offset: Nat, batches: List<&2, Wal.Batch>,
    size: U32}
  ReplayBound{bytes: Bytes.Bytes, offset: Nat, batches: List<&2, Wal.Batch>,
    total: Nat, at_end: Bool, has_length: Bool}
  ReplayLength{bytes: Bytes.Bytes, next_offset: Nat, total: Nat,
    batches: List<&2, Wal.Batch>, length: Maybe<&2, U32>}
  ReplayFrame{bytes: Bytes.Bytes, next_offset: Nat, frame_end: Nat,
    batches: List<&2, Wal.Batch>, length: U32, fits: Bool}
  ReplayDecoded{bytes: Bytes.Bytes, next_offset: Nat,
    batches: List<&2, Wal.Batch>, result: Result<&1, &1, Wal.Error, Wal.Batch>}

# Carries the read-only legacy WAL parser across bounded pure transitions.
type WalkState is Type:
  Header{pair: Bytes.Bytes & Bytes.Bytes}
  HeaderDecoded{source: Bytes.Bytes, result: Result<&1, &1, Wal.Error, Unit>}
  HeaderMeasured{pair: Bytes.Bytes & U32}
  HeaderSeek{pair: Bytes.Cursor & Bool}
  Read{cursor: Bytes.Cursor, frames: Nat}
  Remaining{pair: Bytes.Cursor & U32, frames: Nat}
  Empty{cursor: Bytes.Cursor, remaining: Nat, frames: Nat}
  EmptyChecked{cursor: Bytes.Cursor, remaining: Nat, frames: Nat, empty: Bool}
  HasLength{cursor: Bytes.Cursor, remaining: Nat, frames: Nat, has_length: Bool}
  Length{pair: Bytes.Cursor & Maybe<&2, U32>, remaining: U32, frames: Nat}
  Bounds{cursor: Bytes.Cursor, length: U32, frames: Nat, valid: Bool}
  Position{cursor: Bytes.Cursor, positions: Nat & Nat,
    frame_bytes: U32, frame_length: U32, frames: Nat}
  Frame{pair: Bytes.Bytes & Bytes.Bytes, end: U32, frames: Nat}
  Decoded{result: Result<&1, &1, Wal.Error, Wal.Batch>, source: Bytes.Bytes, end: U32, frames: Nat}
  Seek{pair: Bytes.Cursor & Bool, frames: Nat}
  Finish{frames: Nat}
  Invalid{}

# Separates an empty log suffix from the next frame-length transition.
def walk.empty.checked(
  cursor: Bytes.Cursor,
  frames: Nat,
  copies: Nat & Nat
) -> WalkState:
  match copies:
    case (for_check, retained):
      EmptyChecked{cursor, retained, frames, Nat.is_eq(for_check, 0n)}

# Checks that a nonempty log suffix contains a complete frame-length word.
def walk.length.checked(
  cursor: Bytes.Cursor,
  frames: Nat,
  copies: Nat & Nat
) -> WalkState:
  match copies:
    case (for_check, retained):
      HasLength{cursor, retained, frames, Nat.is_le(4n, for_check)}

def walk.nat.clone.remainder(
  first: Nat,
  pair: Nat & Nat
) -> Nat & Nat & Nat:
  match pair:
    case (second, third): (first, second, third)

def walk.nat.clone.pair(pair: Nat & Nat) -> Nat & Nat & Nat:
  match pair:
    case (first, remainder):
      walk.nat.clone.remainder(first,
        QueuePolicy.nat.clone.pair(remainder))

def walk.nat.clone.triple(value: Nat) -> Nat & Nat & Nat:
  walk.nat.clone.pair(QueuePolicy.nat.clone.pair(value))

def walk.length.copies.for.cursor(
  cursor: Bytes.Cursor,
  remaining: U32,
  frames: Nat,
  pair: Nat & Nat & Nat
) -> WalkState:
  match pair:
    case (minimum_check, (limit_check, retained_length)):
      +valid = Nat.is_le(36n, minimum_check) &&
        Nat.is_le(limit_check, U32.to_nat(remaining))
      Bounds{cursor, U32.from_nat(retained_length), frames, valid}

def walk.length.validated(
  cursor: Bytes.Cursor,
  remaining: U32,
  frames: Nat,
  length: U32
) -> WalkState:
  walk.length.copies.for.cursor(cursor, remaining, frames,
    walk.nat.clone.triple(U32.to_nat(length)))

# Prepares independent frame-size and endpoint lengths for the cursor state.
def walk.position.measured(
  pair: Bytes.Cursor & U32,
  frames: Nat,
  lengths: Nat & Nat
) -> WalkState:
  match pair:
    case (cursor, position):
      match lengths:
        case (frame_length, endpoint_length):
          Position{cursor, QueuePolicy.nat.clone.pair(U32.to_nat(position)),
            U32.from_nat(Nat.add(frame_length, 4n)),
            U32.from_nat(endpoint_length), frames}

def walk.position.state(
  cursor: Bytes.Cursor,
  frames: Nat,
  lengths: Nat & Nat
) -> WalkState:
  walk.position.measured(Bytes.Cursor.position(cursor), frames, lengths)

# Applies one pure parser transition, rejecting malformed or truncated frames.
def walk(fuel: Nat, state: WalkState) -> VerifyResult:
  match fuel:
    case 0n: WalInvalid{}
    case 1n+rest:
      match state:
        case Header{pair}:
          match pair:
            case (source, header):
              walk(rest, HeaderDecoded{source, Wal.decode_header(header)})
        case HeaderDecoded{source, result}:
          match result:
            case Fail{_}: WalInvalid{}
            case Done{Unit{}}:
              walk(rest, HeaderMeasured{Bytes.length(source)})
        case HeaderMeasured{pair}:
          match pair:
            case (source, size):
              walk(rest, HeaderSeek{
                Bytes.Cursor.seek(Bytes.Cursor.new(source), 8)})
        case HeaderSeek{pair}:
          match pair:
            case (_, False{}): WalInvalid{}
            case (cursor, True{}): walk(rest, Read{cursor, 0n})
        case Read{cursor, frames}:
          walk(rest, Remaining{Bytes.Cursor.remaining(cursor), frames})
        case Remaining{pair, frames}:
          match pair:
            case (cursor, remaining):
              walk(rest, Empty{cursor, U32.to_nat(remaining), frames})
        case Empty{cursor, remaining, frames}:
          walk(rest, walk.empty.checked(cursor, frames,
            QueuePolicy.nat.clone.pair(remaining)))
        case EmptyChecked{cursor, remaining, frames, empty}:
          match empty:
            case True{}: walk(rest, Finish{frames})
            case False{}:
              walk(rest, walk.length.checked(cursor, frames,
                QueuePolicy.nat.clone.pair(remaining)))
        case HasLength{cursor, remaining, frames, has_length}:
          match has_length:
            case False{}: WalInvalid{}
            case True{}:
              walk(rest, Length{Bytes.Cursor.u32be(cursor),
                U32.from_nat(Nat.sub(remaining, 4n)), frames})
        case Length{pair, remaining, frames}:
          match pair:
            case (_, None{}): WalInvalid{}
            case (cursor, Some{length}):
              walk(rest, walk.length.validated(cursor, remaining, frames, length))
        case Bounds{cursor, length, frames, valid}:
          match valid:
            case False{}: WalInvalid{}
            case True{}:
              walk(rest, walk.position.state(cursor, frames,
                QueuePolicy.nat.clone.pair(U32.to_nat(length))))
        case Position{cursor, positions, frame_bytes, frame_length, frames}:
          match cursor:
            case Bytes.Cursor{bytes, _, _, _}:
              match positions:
                case (start_nat, end_nat):
                  +start = U32.from_nat(Nat.sub(start_nat, 4n))
                  +end = U32.add(U32.from_nat(end_nat), frame_length)
                  walk(rest, Frame{Bytes.slice(bytes, start, frame_bytes),
                    end, frames})
        case Frame{pair, end, frames}:
          match pair:
            case (source, frame):
              walk(rest, Decoded{Wal.decode_frame(frame), source, end, frames})
        case Decoded{result, source, end, frames}:
          match result:
            case Fail{_}: WalInvalid{}
            case Done{_}:
              walk(rest, Seek{Bytes.Cursor.seek(Bytes.Cursor.new(source), end),
                Nat.add(frames, 1n)})
        case Seek{pair, frames}:
          match pair:
            case (_, False{}): WalInvalid{}
            case (cursor, True{}): walk(rest, Read{cursor, frames})
        case Finish{frames}: WalValid{frames}
        case Invalid{}: WalInvalid{}

# Converts the file byte count into a finite transition bound.
def verify.measured(pair: Bytes.Bytes & U32) -> VerifyResult:
  match pair:
    case (bytes, size):
      walk(Nat.add(5n,
        Nat.mul(12n, Nat.add(Nat.div(U32.to_nat(size), 40n), 1n))),
        Header{Bytes.slice(bytes, 0, 8)})

# Validates a complete generation-three WAL without repairing its bytes.
def verify(bytes: Bytes.Bytes) -> VerifyResult:
  verify.measured(Bytes.length(bytes))

def replay.measure(
  measured: Bytes.Bytes & U32,
  offset: Nat,
  batches: List<&2, Wal.Batch>
) -> ReplayState:
  match measured:
    case (bytes, size): ReplayMeasured{bytes, offset, batches, size}

def replay.nat.clone.remainder(first: Nat, pair: Nat & Nat) -> Nat & Nat & Nat:
  match pair:
    case (second, third): (first, second, third)

def replay.nat.clone.pair(pair: Nat & Nat) -> Nat & Nat & Nat:
  match pair:
    case (first, remainder):
      replay.nat.clone.remainder(first, QueuePolicy.nat.clone.pair(remainder))

def replay.nat.clone.triple(value: Nat) -> Nat & Nat & Nat:
  replay.nat.clone.pair(QueuePolicy.nat.clone.pair(value))

def replay.bound.measured(
  bytes: Bytes.Bytes,
  batches: List<&2, Wal.Batch>,
  offsets: Nat & Nat & Nat,
  totals: Nat & Nat & Nat
) -> ReplayState:
  match offsets:
    case (retained_offset, (end_offset, length_offset)):
      match totals:
        case (retained_total, (end_total, length_total)):
          ReplayBound{bytes, retained_offset, batches, retained_total,
            Nat.is_eq(end_offset, end_total),
            Nat.is_le(Nat.add(length_offset, 4n), length_total)}

def replay.bound.state(
  bytes: Bytes.Bytes,
  offset: Nat,
  batches: List<&2, Wal.Batch>,
  total: Nat
) -> ReplayState:
  replay.bound.measured(bytes, batches,
    replay.nat.clone.triple(offset), replay.nat.clone.triple(total))

def replay.length.pair(
  measured: Bytes.Bytes & Maybe<&2, U32>,
  next_offset: Nat,
  total: Nat,
  batches: List<&2, Wal.Batch>
) -> ReplayState:
  match measured:
    case (bytes, length):
      ReplayLength{bytes, next_offset, total, batches, length}

def replay.length.indexed(
  bytes: Bytes.Bytes,
  offsets: Nat & Nat,
  total: Nat,
  batches: List<&2, Wal.Batch>
) -> ReplayState:
  match offsets:
    case (next_offset, read_offset):
      replay.length.pair(Bytes.get.u32be(bytes, U32.from_nat(read_offset)),
        Nat.add(next_offset, 4n), total, batches)

def replay.length.state(
  bytes: Bytes.Bytes,
  offset: Nat,
  total: Nat,
  batches: List<&2, Wal.Batch>
) -> ReplayState:
  replay.length.indexed(bytes, QueuePolicy.nat.clone.pair(offset),
    total, batches)

def replay.frame.measured(
  bytes: Bytes.Bytes,
  batches: List<&2, Wal.Batch>,
  total: Nat,
  offsets: Nat & Nat,
  lengths: Nat & Nat
) -> ReplayState:
  match offsets:
    case (slice_offset, end_offset):
      match lengths:
        case (end_length, slice_length):
          +frame_end = Nat.add(end_offset, end_length)
          +frame_start = Nat.sub(slice_offset, 4n)
          +serialized_length = Nat.add(slice_length, 4n)
          ReplayFrame{bytes, frame_start, frame_end, batches,
            U32.from_nat(serialized_length), Nat.is_le(frame_end, total)}

def replay.frame.state(
  bytes: Bytes.Bytes,
  next_offset: Nat,
  total: Nat,
  batches: List<&2, Wal.Batch>,
  length: U32
) -> ReplayState:
  replay.frame.measured(bytes, batches, total,
    QueuePolicy.nat.clone.pair(next_offset),
    QueuePolicy.nat.clone.pair(U32.to_nat(length)))

def replay.frame.decoded(
  pair: Bytes.Bytes & Bytes.Bytes,
  frame_end: Nat,
  batches: List<&2, Wal.Batch>
) -> ReplayState:
  match pair:
    case (bytes, frame):
      ReplayDecoded{bytes, frame_end, batches, Wal.decode_frame(frame)}

def replay.loop(fuel: Nat, state: ReplayState) -> ReplayResult:
  match fuel:
    case 0n: ReplayInvalid{}
    case 1n+rest:
      match state:
        case ReplayNeed{bytes, offset, batches}:
          replay.loop(rest, replay.measure(Bytes.length(bytes), offset, batches))
        case ReplayMeasured{bytes, offset, batches, size}:
          +total = U32.to_nat(size)
          replay.loop(rest, replay.bound.state(bytes, offset, batches, total))
        case ReplayBound{bytes, offset, batches, total, at_end, has_length}:
              match at_end:
                case True{}:
                  ReplayValid{batches}
                case False{}:
                  match has_length:
                    case True{}:
                      replay.loop(rest,
                        replay.length.state(bytes, offset, total, batches))
                    case False{}: ReplayInvalid{}
        case ReplayLength{bytes, next_offset, total, batches, length}:
          match length:
            case None{}: ReplayInvalid{}
            case Some{frame_length}:
              replay.loop(rest, replay.frame.state(bytes, next_offset,
                total, batches, frame_length))
        case ReplayFrame{bytes, next_offset, frame_end, batches, length, fits}:
              match fits:
                case True{}:
                  replay.loop(rest, replay.frame.decoded(Bytes.slice(bytes,
                    U32.from_nat(next_offset), length), frame_end, batches))
                case False{}: ReplayInvalid{}
        case ReplayDecoded{bytes, next_offset, batches, result}:
          match result:
            case Fail{_}: ReplayInvalid{}
            case Done{batch}:
              replay.loop(rest, ReplayNeed{bytes, next_offset,
                List.append(&2, Wal.Batch, batches, Con{batch, Nil{}})})

def replay.header.validated(
  source: Bytes.Bytes,
  fuel: Nat,
  validation: Result<&1, &1, Wal.Error, Unit>
) -> ReplayResult:
  match validation:
    case Fail{_}: ReplayInvalid{}
    case Done{Unit{}}: replay.loop(fuel, ReplayNeed{source, 8n, Nil{}})

def replay.header.pair(
  pair: Bytes.Bytes & Bytes.Bytes,
  fuel: Nat
) -> ReplayResult:
  match pair:
    case (source, header):
      replay.header.validated(source, fuel, Wal.decode_header(header))

# Derives replay fuel from the source size and validates the header before decoding frames.
def replay.measured(pair: Bytes.Bytes & U32) -> ReplayResult:
  match pair:
    case (bytes, size):
      replay.header.pair(Bytes.slice(bytes, 0, 8),
        Nat.add(3n, Nat.mul(6n, Nat.div(U32.to_nat(size), 40n))))

# Validates and replays all frames without repairing or truncating the source.
def replay(bytes: Bytes.Bytes) -> ReplayResult:
  replay.measured(Bytes.length(bytes))
