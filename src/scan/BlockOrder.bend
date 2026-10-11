import Base
import ../ByteMemTable.bend as ByteMemTable
import ../Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Tracks strict ordering and the last key across decoded SST blocks.
type State is Type:
  State{valid: Bool, last_key: Maybe<&1, Bytes.Bytes>, count: Nat}

# Starts a block-order check with the preceding block's last key.
def empty(previous: Maybe<&1, Bytes.Bytes>) -> State:
  State{True{}, previous, 0n}

def compare.result(comparison: Bytes.Bytes & Bytes.Bytes & Cmp) -> Bool:
  match comparison:
    case (_, _, LT{}): True{}
    case _: False{}

# Requires each new key to sort strictly after the preceding key.
def compare(previous: Maybe<&1, Bytes.Bytes>, key: Bytes.Bytes) -> Bool:
  match previous:
    case None{}: True{}
    case Some{last}:
      compare.result(Keys.Bytes.cmp.with_inputs(last, key))

def advance.state(
  previous: Maybe<&1, Bytes.Bytes>,
  +count: Nat,
  valid: Bool,
  copies: Bytes.Bytes & Bytes.Bytes
) -> State:
  match copies:
    case (for_compare, retained):
      State{valid && compare(previous, for_compare), Some{retained},
        Nat.add(count, 1n)}

# Validates one entry and retains its key as the next comparison boundary.
def advance(entry: ByteMemTable.Entry, state: State) -> State:
  match entry:
    case ByteMemTable.Entry{key, _}:
      match state:
        case State{valid, previous, count}:
          advance.state(previous, count, valid,
            ByteMemTable.bytes.clone(key))

# Checks every ordered entry in a block and carries the final key forward.
def go(entries: List<&1, ByteMemTable.Entry>, state: State) -> State:
  match entries:
    case Nil{}: state
    case Con{entry, tail}:
      go(tail, advance(entry, state))

# Reports whether all keys seen so far were strictly ascending.
def accepted(state: State) -> Bool:
  match state:
    case State{valid, _, _}: valid
