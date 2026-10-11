import Base
import ../StorageBytes.bend as StorageBytes
import ./Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries visible data and live owner-retention counters.
type Stats is Data:
  ByteStats{entries: Nat, payload_bytes: Nat, snapshots: Nat, retained_bytes: Nat, cursors: Nat}

# Distinguishes a decoded statistics payload from malformed bytes.
type Decision is Data:
  Parsed{stats: Stats}
  Malformed{}

# Tracks decimal fields while parsing the bounded owner counter payload.
type State is Data:
  EntryDigits{entries: Nat, seen: Bool}
  PayloadDigits{entries: Nat, payload_bytes: Nat, seen: Bool}
  SnapshotDigits{entries: Nat, payload_bytes: Nat, snapshots: Nat, seen: Bool}
  RetainedDigits{entries: Nat, payload_bytes: Nat, snapshots: Nat,
    retained_bytes: Nat, seen: Bool}
  CursorDigits{entries: Nat, payload_bytes: Nat, snapshots: Nat,
    retained_bytes: Nat, cursors: Nat, seen: Bool}
  Invalid{}

def digit.value(scalar: U32) -> Nat:
  Nat.sub(U32.to_nat(scalar), 48n)

def digit.valid.checked(copies: U32 & U32) -> Bool:
  match copies:
    case (lower, upper): U32.is_le(48, lower) && U32.is_le(upper, 57)

def digit.valid.copies(copies: U32 & U32 & U32) -> Bool:
  match copies:
    case (_, (lower, upper)): digit.valid.checked((lower, upper))

def digit.valid(scalar: U32) -> Bool:
  digit.valid.copies(Protocol.u32.duplicate.triple(scalar))

def separator.character(parser: State, scalar: U32) -> State:
  match parser:
    case EntryDigits{entries, _}:
      match scalar:
        case 58: PayloadDigits{entries, 0n, False{}}
        case _: Invalid{}
    case PayloadDigits{entries, payload_bytes, _}:
      match scalar:
        case 58: SnapshotDigits{entries, payload_bytes, 0n, False{}}
        case _: Invalid{}
    case SnapshotDigits{entries, payload_bytes, snapshots, _}:
      match scalar:
        case 58: RetainedDigits{entries, payload_bytes, snapshots, 0n, False{}}
        case _: Invalid{}
    case RetainedDigits{entries, payload_bytes, snapshots, retained_bytes, _}:
      match scalar:
        case 58:
          CursorDigits{entries, payload_bytes, snapshots, retained_bytes, 0n,
            False{}}
        case _: Invalid{}
    case _: Invalid{}

# Advances to a new stats field only after the current field has digits.
def separator(parser: State, seen: Bool, scalar: U32) -> State:
  match seen:
    case False{}: Invalid{}
    case True{}: separator.character(parser, scalar)

def entry.step(
  entries: Nat,
  scalar: U32,
  is_digit: Bool,
  seen: Bool
) -> State:
  match is_digit:
    case True{}:
      EntryDigits{Nat.add(Nat.mul(entries, 10n), digit.value(scalar)), True{}}
    case False{}:
      match seen:
        case False{}: Invalid{}
        case True{}: separator(EntryDigits{entries, True{}}, True{}, scalar)

def payload.step(
  entries: Nat,
  payload_bytes: Nat,
  scalar: U32,
  is_digit: Bool,
  seen: Bool
) -> State:
  match is_digit:
    case True{}:
      PayloadDigits{entries,
        Nat.add(Nat.mul(payload_bytes, 10n), digit.value(scalar)), True{}}
    case False{}:
      match seen:
        case False{}: Invalid{}
        case True{}:
          separator(PayloadDigits{entries, payload_bytes, True{}}, True{},
            scalar)

def snapshot.step(
  entries: Nat,
  payload_bytes: Nat,
  snapshots: Nat,
  scalar: U32,
  is_digit: Bool,
  seen: Bool
) -> State:
  match is_digit:
    case True{}:
      SnapshotDigits{entries, payload_bytes,
        Nat.add(Nat.mul(snapshots, 10n), digit.value(scalar)), True{}}
    case False{}:
      match seen:
        case False{}: Invalid{}
        case True{}:
          separator(SnapshotDigits{entries, payload_bytes, snapshots, True{}},
            True{}, scalar)

def retained.step(
  entries: Nat,
  payload_bytes: Nat,
  snapshots: Nat,
  retained_bytes: Nat,
  scalar: U32,
  is_digit: Bool,
  seen: Bool
) -> State:
  match is_digit:
    case True{}:
      RetainedDigits{entries, payload_bytes, snapshots,
        Nat.add(Nat.mul(retained_bytes, 10n), digit.value(scalar)), True{}}
    case False{}:
      match seen:
        case False{}: Invalid{}
        case True{}:
          separator(RetainedDigits{entries, payload_bytes, snapshots,
            retained_bytes, True{}}, True{}, scalar)

def cursor.step(
  entries: Nat,
  payload_bytes: Nat,
  snapshots: Nat,
  retained_bytes: Nat,
  cursors: Nat,
  scalar: U32,
  is_digit: Bool
) -> State:
  match is_digit:
    case True{}:
      CursorDigits{entries, payload_bytes, snapshots, retained_bytes,
        Nat.add(Nat.mul(cursors, 10n), digit.value(scalar)), True{}}
    case False{}: Invalid{}

def parse.step(state: State, scalar: U32, is_digit: Bool) -> State:
  match state:
    case EntryDigits{entries, seen}:
      entry.step(entries, scalar, is_digit, seen)
    case PayloadDigits{entries, payload_bytes, seen}:
      payload.step(entries, payload_bytes, scalar, is_digit, seen)
    case SnapshotDigits{entries, payload_bytes, snapshots, seen}:
      snapshot.step(entries, payload_bytes, snapshots, scalar, is_digit, seen)
    case RetainedDigits{entries, payload_bytes, snapshots, retained_bytes, seen}:
      retained.step(entries, payload_bytes, snapshots, retained_bytes,
        scalar, is_digit, seen)
    case CursorDigits{entries, payload_bytes, snapshots, retained_bytes,
        cursors, seen}:
      cursor.step(entries, payload_bytes, snapshots, retained_bytes, cursors,
        scalar, is_digit)
    case Invalid{}: Invalid{}

def parse.step.copies(
  state: State,
  copies: U32 & U32 & U32
) -> State:
  match copies:
    case (scalar, (checked_scalar, _)):
      parse.step(state, scalar, digit.valid(checked_scalar))

def parse.go(text: String, state: State) -> State:
  match text:
    case SNil{}: state
    case SCon{Chr{scalar}, rest}:
      parse.go(rest, parse.step.copies(state,
        Protocol.u32.duplicate.triple(scalar)))

# Completes parsing only when the payload byte field contains digits.
def finish(state: State) -> Decision:
  match state:
    case CursorDigits{entries, payload_bytes, snapshots, retained_bytes,
        cursors, True{}}:
      Parsed{ByteStats{entries, payload_bytes, snapshots, retained_bytes,
        cursors}}
    case _: Malformed{}

def parse.text(text: String) -> Decision:
  finish(parse.go(text, EntryDigits{0n, False{}}))

def parse.result(
  result: Result<&1, &1, U32 & String, String>
) -> Decision:
  match result:
    case Done{text}: parse.text(text)
    case Fail{_}: Malformed{}

# Parses a strict UTF-8 decimal pair from the owner response bytes.
def parse(input: Bytes.Bytes) -> Decision:
  parse.result(StorageBytes.to_string_strict(input))
