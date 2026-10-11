import Base
import ../ByteMemTable.bend as ByteMemTable
import ../Keys.bend as Keys
import ./ByteRange.bend as ByteRange
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries optional half-open range bounds and an optional byte prefix.
type Bounds is Type:
  Bounds{lower: Maybe<&1, Bytes.Bytes>, upper: Maybe<&1, Bytes.Bytes>, prefix: Maybe<&1, Bytes.Bytes>}

# Owns the unread suffix of one ordered byte-entry source.
type Cursor is Type:
  RangeReady{entries: List<&1, ByteMemTable.Entry>}
  RangeEnded{}
  RangeClosed{}

# Returns an item, a filtered skip, or terminal end with retained bounds.
type Step is Type:
  RangeItem{entry: ByteMemTable.Entry, cursor: Cursor, bounds: Bounds}
  RangeSkip{cursor: Cursor, bounds: Bounds}
  RangeEnd{cursor: Cursor, bounds: Bounds}

# Returns the first entry at or above a lower bound.
type SeekStep is Type:
  SeekSkip{entries: List<&1, ByteMemTable.Entry>, lower: Bytes.Bytes}
  SeekFound{entries: List<&1, ByteMemTable.Entry>}

def seek.order(
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, ByteMemTable.Entry>,
  lower: Bytes.Bytes,
  comparison: Bytes.Bytes & Bytes.Bytes & Cmp
) -> SeekStep:
  match comparison:
    case (_, _, LT{}): SeekSkip{tail, lower}
    case _ : SeekFound{Con{ByteMemTable.Entry{key, value}, tail}}

def seek.compared(
  key: Bytes.Bytes,
  key_check: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, ByteMemTable.Entry>,
  pair: Bytes.Bytes & Bytes.Bytes
) -> SeekStep:
  match pair:
    case (lower, lower_check):
      seek.order(key, value, tail, lower, Keys.Bytes.cmp.with_inputs(key_check, lower_check))

def seek.key.copies(
  key: Bytes.Bytes,
  key_check: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, ByteMemTable.Entry>,
  lower: Bytes.Bytes
) -> SeekStep:
  seek.compared(key, key_check, value, tail, ByteMemTable.bytes.clone(lower))

def seek.entry.cloned(
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, ByteMemTable.Entry>,
  lower: Bytes.Bytes,
  pair: Bytes.Bytes & Bytes.Bytes
) -> SeekStep:
  match pair:
    case (original_key, check_key):
      seek.key.copies(original_key, check_key, value, tail, lower)

def seek.entry(
  entry: ByteMemTable.Entry,
  tail: List<&1, ByteMemTable.Entry>,
  lower: Bytes.Bytes
) -> SeekStep:
  match entry:
    case ByteMemTable.Entry{key, value}:
      seek.entry.cloned(value, tail, lower, ByteMemTable.bytes.clone(key))

def seek.step(
  entry: ByteMemTable.Entry,
  tail: List<&1, ByteMemTable.Entry>,
  lower: Maybe<&1, Bytes.Bytes>
) -> SeekStep:
  match lower:
    case None{}: SeekFound{Con{entry, tail}}
    case Some{bound}: seek.entry(entry, tail, bound)

def seek.first(
  entries: List<&1, ByteMemTable.Entry>,
  lower: Maybe<&1, Bytes.Bytes>
) -> SeekStep:
  match entries:
    case Nil{}: SeekFound{Nil{}}
    case Con{entry, tail}: seek.step(entry, tail, lower)

def seek.go(fuel: Nat, result: SeekStep) -> List<&1, ByteMemTable.Entry>:
  match fuel:
    case 0n:
      match result:
        case SeekSkip{entries, _}: entries
        case SeekFound{found}: found
    case 1n+rest:
      match result:
        case SeekSkip{entries, lower}:
          seek.go(rest, seek.first(entries, Some{lower}))
        case SeekFound{found}: found

def seek.counted(
  entries: List<&1, ByteMemTable.Entry> & Nat,
  lower: Maybe<&1, Bytes.Bytes>
) -> List<&1, ByteMemTable.Entry>:
  match entries:
    case (source, count): seek.go(Nat.add(count, 1n), seek.first(source, lower))

# Drops ordered entries below the inclusive lower bound.
def seek(
  entries: List<&1, ByteMemTable.Entry>,
  lower: Maybe<&1, Bytes.Bytes>
) -> List<&1, ByteMemTable.Entry>:
  seek.counted(ByteMemTable.count.keep(entries), lower)

# Moves an active source forward to the first key at or above the lower bound.
def seek.cursor(cursor: Cursor, lower: Maybe<&1, Bytes.Bytes>) -> Cursor:
  match cursor:
    case RangeReady{entries}: RangeReady{seek(entries, lower)}
    case RangeEnded{}: RangeEnded{}
    case RangeClosed{}: RangeClosed{}

def bounds.clone.parts(
  lower: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>,
  upper: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>,
  prefix: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>
) -> Bounds & Bounds:
  match lower:
    case (lower_original, lower_copy):
      match upper:
        case (upper_original, upper_copy):
          match prefix:
            case (prefix_original, prefix_copy):
              (Bounds{lower_original, upper_original, prefix_original},
                Bounds{lower_copy, upper_copy, prefix_copy})

def bounds.clone(bounds: Bounds) -> Bounds & Bounds:
  match bounds:
    case Bounds{lower, upper, prefix}:
      bounds.clone.parts(ByteMemTable.value.clone(lower),
        ByteMemTable.value.clone(upper), ByteMemTable.value.clone(prefix))

def matches.prefix(key: Bytes.Bytes, prefix: Maybe<&1, Bytes.Bytes>) -> Bool:
  match prefix:
    case None{}: True{}
    case Some{value}: ByteRange.has_prefix(key, value)

def matches.key(pair: Bytes.Bytes & Bytes.Bytes, bounds: Bounds) -> Bool:
  match pair:
    case (range_key, prefix_key):
      match bounds:
        case Bounds{lower, upper, prefix}:
          Bool.and(ByteRange.in_range(range_key, lower, upper),
            matches.prefix(prefix_key, prefix))

def matches.bounds(pair: Bounds & Bounds, keys: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match pair:
    case (checked, _):
      matches.key(keys, checked)

def filtered.result(
  valid: Bool,
  key: Bytes.Bytes,
  value: Bytes.Bytes,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: Bounds
) -> Step:
  match valid:
    case True{}:
      RangeItem{ByteMemTable.Entry{key, Some{value}}, RangeReady{tail}, bounds}
    case False{}:
      RangeSkip{RangeReady{tail}, bounds}

def key.copies.pair(
  original: Bytes.Bytes,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match copies:
    case (range_key, prefix_key):
      (original, range_key, prefix_key)

def key.copies.first(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (original, check_key):
      key.copies.pair(original, ByteMemTable.bytes.clone(check_key))

def key.copies(key: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  key.copies.first(ByteMemTable.bytes.clone(key))

def filtered.bounds(
  value: Bytes.Bytes,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: Bounds & Bounds,
  keys: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes
) -> Step:
  match bounds:
    case (checked, retained):
      match keys:
        case (original_key, range_key, prefix_key):
          filtered.result(matches.key((range_key, prefix_key), checked),
            original_key, value, tail, retained)

def filtered.key(
  keys: Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: Bounds & Bounds
) -> Step:
  match keys:
    case (key, check_key):
      filtered.bounds(value, tail, bounds, key.copies(check_key))

def filtered.value(
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: Bounds & Bounds
) -> Step:
  match value:
    case None{}:
      match bounds:
        case (_, retained): RangeSkip{RangeReady{tail}, retained}
    case Some{bytes}:
      filtered.key(ByteMemTable.bytes.clone(key), bytes, tail, bounds)

# Opens an ordered source for range and prefix filtering.
def open(entries: List<&1, ByteMemTable.Entry>) -> Cursor:
  RangeReady{entries}

def next.pair.checked(
  reached_upper: Bool,
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: Bounds & Bounds
) -> Step:
  match reached_upper:
    case True{}:
      match bounds:
        case (_, retained): RangeEnd{RangeEnded{}, retained}
    case False{}:
      filtered.value(key, value, tail, bounds)

def next.upper.test.bytes(
  keys: Bytes.Bytes & Bytes.Bytes,
  upper: Maybe<&1, Bytes.Bytes>
) -> Bool:
  match keys:
    case (_, check_key): ByteRange.at_or_after_upper(check_key, upper)

def next.upper.test(
  key: Bytes.Bytes,
  bounds: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>
) -> Bool:
  match bounds:
    case (upper, _):
      next.upper.test.bytes(ByteMemTable.bytes.clone(key), upper)

def next.pair.upper(key: Bytes.Bytes, bounds: Bounds) -> Bool:
  match bounds:
    case Bounds{_, upper, _}:
      next.upper.test(key, ByteMemTable.value.clone(upper))

def next.pair.bounds.copied(
  key: Bytes.Bytes,
  check_key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: Bounds & Bounds,
  retained: Bounds
) -> Step:
  match bounds:
    case (upper_bounds, filter_bounds):
      next.pair.checked(next.pair.upper(check_key, upper_bounds), key,
        value, tail, (filter_bounds, retained))

def next.pair.bounds(
  key: Bytes.Bytes,
  check_key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: Bounds & Bounds
) -> Step:
  match bounds:
    case (checked, retained):
      next.pair.bounds.copied(key, check_key, value, tail,
        bounds.clone(checked), retained)

def next.pair.cloned(
  keys: Bytes.Bytes & Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: Bounds & Bounds
) -> Step:
  match keys:
    case (key, check_key):
      next.pair.bounds(key, check_key, value, tail, bounds)

def next.pair(
  entry: ByteMemTable.Entry,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: Bounds & Bounds
) -> Step:
  match entry:
    case ByteMemTable.Entry{key, value}:
      next.pair.cloned(ByteMemTable.bytes.clone(key), value, tail, bounds)

def next.ready(
  entries: List<&1, ByteMemTable.Entry>,
  bounds: Bounds & Bounds
) -> Step:
  match entries:
    case Nil{}:
      match bounds:
        case (_, retained): RangeEnd{RangeEnded{}, retained}
    case Con{entry, tail}:
      next.pair(entry, tail, bounds)

# Returns one match, a skip event, or end while returning the bounds.
def next(cursor: Cursor, bounds: Bounds & Bounds) -> Step:
  match cursor:
    case RangeReady{entries}:
      next.ready(entries, bounds)
    case RangeEnded{}:
      match bounds:
        case (_, retained): RangeEnd{RangeEnded{}, retained}
    case RangeClosed{}:
      match bounds:
        case (_, retained): RangeEnd{RangeClosed{}, retained}

# Closes an active byte range cursor.
def close(cursor: Cursor) -> Cursor:
  match cursor:
    case RangeReady{_}: RangeClosed{}
    case RangeEnded{}: RangeEnded{}
    case RangeClosed{}: RangeClosed{}
