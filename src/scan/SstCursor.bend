import Base
import ../ByteMemTable.bend as ByteMemTable
import ./ByteBlockReader.bend as ByteBlockReader
import ./ByteRange.bend as ByteRange
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries half-open byte bounds and an optional exact byte prefix.
type Bounds is Type:
  Bounds{lower: Maybe<&1, Bytes.Bytes>, upper: Maybe<&1, Bytes.Bytes>,
    prefix: Maybe<&1, Bytes.Bytes>}

# Owns one validated SST reader and the unread part of its current block.
type Cursor is Type:
  Active{inner: ByteBlockReader.EntryCursor, bounds: Bounds}
  Ended{}
  Closed{}
  Failed{error: U32 & String}

# Represents a streamed record, filtered entry, end, or terminal error.
type Step is Type:
  Item{entry: ByteMemTable.Entry, cursor: Cursor}
  Skip{cursor: Cursor}
  End{}
  Error{error: U32 & String}

# Carries each bounded block validation transition before cursor publication.
type VerifyState is Type:
  VerifyNeed{reader: ByteBlockReader.Reader, bounds: Bounds}
  VerifyRead{result: Result<&1, &1, U32 & String, ByteBlockReader.Step>,
    bounds: Bounds}

# Carries one block read or one current block during incremental scanning.
type ScanState is Type:
  ScanNeed{reader: ByteBlockReader.Reader, bounds: Bounds}
  ScanRead{result: Result<&1, &1, U32 & String, ByteBlockReader.Step>,
    bounds: Bounds}
  ScanBlock{reader: ByteBlockReader.Reader,
    entries: List<&1, ByteMemTable.Entry>, bounds: Bounds}

def bounds.copy.values(
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

def bounds.copy(bounds: Bounds) -> Bounds & Bounds:
  match bounds:
    case Bounds{lower, upper, prefix}:
      bounds.copy.values(ByteMemTable.value.clone(lower),
        ByteMemTable.value.clone(upper), ByteMemTable.value.clone(prefix))

def scan.prefix(key: Bytes.Bytes, prefix: Maybe<&1, Bytes.Bytes>) -> Bool:
  match prefix:
    case None{}: True{}
    case Some{bytes}: ByteRange.has_prefix(key, bytes)

def scan.entry.choose(
  valid: Bool,
  key: Bytes.Bytes,
  value: Bytes.Bytes,
  cursor: ByteBlockReader.EntryCursor,
  bounds: Bounds & Bounds
) -> IO(Step):
  match valid:
    case True{}:
      match bounds:
        case (item_bounds, _):
          IO.pure(Step, Item{ByteMemTable.Entry{key, Some{value}},
            Active{cursor, item_bounds}})
    case False{}:
      match bounds:
        case (_, skip_bounds): IO.pure(Step, Skip{Active{cursor, skip_bounds}})

def scan.entry.checked(
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  cursor: ByteBlockReader.EntryCursor,
  bounds: Bounds & Bounds,
  key_copies: Bytes.Bytes & Bytes.Bytes
) -> IO(Step):
  match value:
    case Some{bytes}:
      match bounds:
        case (checked, retained):
          match checked:
            case Bounds{lower, upper, prefix}:
              match key_copies:
                case (range_key, prefix_key):
                  scan.entry.choose(
                    ByteRange.in_range(range_key, lower, upper) &&
                      scan.prefix(prefix_key, prefix),
                    key, bytes, cursor, bounds.copy(retained))
    case None{}:
      match bounds:
        case (_, retained): IO.pure(Step, Skip{Active{cursor, retained}})

def scan.entry.upper.closed(
  closed: Result<&1, &1, U32 & String, Unit>
) -> Step:
  match closed:
    case Done{Unit{}}: End{}
    case Fail{error}: Error{error}

def scan.entry.upper.result(
  reached: Bool,
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  cursor: ByteBlockReader.EntryCursor,
  lower: Maybe<&1, Bytes.Bytes>,
  prefix: Maybe<&1, Bytes.Bytes>,
  retained: Bounds,
  upper_checked: Maybe<&1, Bytes.Bytes>,
  key_copies: Bytes.Bytes & Bytes.Bytes
) -> IO(Step):
  match reached:
    case True{}:
      do IO<Step>:
        closed : Result<&1, &1, U32 & String, Unit> <-
          ByteBlockReader.entry.close(cursor)
        return scan.entry.upper.closed(closed)
    case False{}:
      scan.entry.checked(key, value, cursor,
        (Bounds{lower, upper_checked, prefix}, retained), key_copies)

def scan.entry.upper.copies(
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  cursor: ByteBlockReader.EntryCursor,
  lower: Maybe<&1, Bytes.Bytes>,
  prefix: Maybe<&1, Bytes.Bytes>,
  retained: Bounds,
  upper: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>,
  key_copies: Bytes.Bytes & Bytes.Bytes
) -> IO(Step):
  match upper:
    case (upper_test, upper_checked):
      match key_copies:
        case (upper_key, filter_key):
          scan.entry.upper.result(
            ByteRange.at_or_after_upper(upper_key, upper_test),
            key, value, cursor, lower, prefix, retained,
            upper_checked,
            ByteMemTable.bytes.clone(filter_key))

def scan.entry.upper.fields(
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  cursor: ByteBlockReader.EntryCursor,
  lower: Maybe<&1, Bytes.Bytes>,
  upper: Maybe<&1, Bytes.Bytes>,
  prefix: Maybe<&1, Bytes.Bytes>,
  retained: Bounds,
  key_copies: Bytes.Bytes & Bytes.Bytes
) -> IO(Step):
  scan.entry.upper.copies(key, value, cursor, lower, prefix, retained,
    ByteMemTable.value.clone(upper), key_copies)

def scan.entry.upper.checked(
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  cursor: ByteBlockReader.EntryCursor,
  bounds: Bounds & Bounds,
  key_copies: Bytes.Bytes & Bytes.Bytes
) -> IO(Step):
  match bounds:
    case (checked, retained):
      match checked:
        case Bounds{lower, upper, prefix}:
          scan.entry.upper.fields(key, value, cursor, lower, upper, prefix,
            retained, key_copies)

def scan.entry.key.copied(
  value: Maybe<&1, Bytes.Bytes>,
  cursor: ByteBlockReader.EntryCursor,
  bounds: Bounds & Bounds,
  pair: Bytes.Bytes & Bytes.Bytes
) -> IO(Step):
  match pair:
    case (key, check_key):
      scan.entry.upper.checked(key, value, cursor, bounds,
        ByteMemTable.bytes.clone(check_key))

def scan.entry(
  entry: ByteMemTable.Entry,
  cursor: ByteBlockReader.EntryCursor,
  bounds: Bounds
) -> IO(Step):
  match entry:
    case ByteMemTable.Entry{key, value}:
      scan.entry.key.copied(value, cursor, bounds.copy(bounds),
        ByteMemTable.bytes.clone(key))

def scan.exhausted(state: ScanState) -> IO(Step):
  match state:
    case ScanNeed{reader, _}:
      do IO<Step>:
        _closed : Result<&1, &1, U32 & String, Unit> <- ByteBlockReader.close(reader)
        return Error{(7, "SST cursor exceeded its transition budget")}
    case ScanRead{result, _}:
      match result:
        case Done{ByteBlockReader.Block{reader, _}}:
          do IO<Step>:
            _closed : Result<&1, &1, U32 & String, Unit> <-
              ByteBlockReader.close(reader)
            return Error{(7, "SST cursor exceeded its transition budget")}
        case _:
          IO.pure(Step, Error{(7, "SST cursor exceeded its transition budget")})
    case ScanBlock{reader, _, _}:
      do IO<Step>:
        _closed : Result<&1, &1, U32 & String, Unit> <- ByteBlockReader.close(reader)
        return Error{(7, "SST cursor exceeded its transition budget")}

def scan.loop(fuel: Nat, state: ScanState) -> IO(Step):
  match fuel:
    case 0n: scan.exhausted(state)
    case 1n+rest:
      match state:
        case ScanNeed{reader, bounds}:
          do IO<Step>:
            result : Result<&1, &1, U32 & String, ByteBlockReader.Step> <-
              ByteBlockReader.next(reader)
            scan.loop(rest, ScanRead{result, bounds})
        case ScanRead{result, bounds}:
          match result:
            case Fail{error}:
              IO.pure(Step, Error{error})
            case Done{ByteBlockReader.End{}}:
              IO.pure(Step, End{})
            case Done{ByteBlockReader.Block{reader, entries}}:
              scan.loop(rest, ScanBlock{reader, entries, bounds})
        case ScanBlock{reader, entries, bounds}:
          match entries:
            case Nil{}:
              scan.loop(rest, ScanNeed{reader, bounds})
            case Con{entry, tail}:
              scan.entry(entry, ByteBlockReader.EntryReady{reader, tail}, bounds)

def verify.exhausted(state: VerifyState) -> IO(Result<&1, &1, U32 & String, Cursor>):
  match state:
    case VerifyNeed{reader, _}:
      do IO<Result<&1, &1, U32 & String, Cursor>>:
        _closed : Result<&1, &1, U32 & String, Unit> <- ByteBlockReader.close(reader)
        return Fail{(7, "SST validation exceeded its transition budget")}
    case VerifyRead{result, _}:
      match result:
        case Done{ByteBlockReader.Block{reader, _}}:
          do IO<Result<&1, &1, U32 & String, Cursor>>:
            _closed : Result<&1, &1, U32 & String, Unit> <-
              ByteBlockReader.close(reader)
            return Fail{(7, "SST validation exceeded its transition budget")}
        case _:
          IO.pure(Result<&1, &1, U32 & String, Cursor>,
            Fail{(7, "SST validation exceeded its transition budget")})

def verify.complete.routed.result(
  bounds: Bounds,
  result: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Result<&1, &1, U32 & String, Cursor>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Cursor>, Fail{error})
    case Done{reader}:
      IO.pure(Result<&1, &1, U32 & String, Cursor>,
        Done{Active{ByteBlockReader.entry.open(reader), bounds}})

def verify.complete.routed(
  bounds: Bounds,
  result: IO(Result<&1, &1, U32 & String, ByteBlockReader.Reader>)
) -> IO(Result<&1, &1, U32 & String, Cursor>):
  do IO<Result<&1, &1, U32 & String, Cursor>>:
    routed : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <- result
    verify.complete.routed.result(bounds, routed)

def verify.complete.copied(
  pair: Bounds & Bounds,
  reader: ByteBlockReader.Reader
) -> IO(Result<&1, &1, U32 & String, Cursor>):
  match pair:
    case (retained, seek_bounds):
      match seek_bounds:
        case Bounds{lower, _, _}:
          match lower:
            case None{}:
              IO.pure(Result<&1, &1, U32 & String, Cursor>,
                Done{Active{ByteBlockReader.entry.open(reader), retained}})
            case Some{key}:
              verify.complete.routed(retained,
                ByteBlockReader.seek_key_after_validation(reader, key))

def verify.complete(
  bounds: Bounds,
  result: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Result<&1, &1, U32 & String, Cursor>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, U32 & String, Cursor>, Fail{error})
    case Done{reader}:
      verify.complete.copied(bounds.copy(bounds), reader)

def verify.loop(
  fuel: Nat,
  path: String,
  state: VerifyState
) -> IO(Result<&1, &1, U32 & String, Cursor>):
  match fuel:
    case 0n: verify.exhausted(state)
    case 1n+rest:
      match state:
        case VerifyNeed{reader, bounds}:
          do IO<Result<&1, &1, U32 & String, Cursor>>:
            result : Result<&1, &1, U32 & String, ByteBlockReader.Step> <-
              ByteBlockReader.next(reader)
            verify.loop(rest, path, VerifyRead{result, bounds})
        case VerifyRead{result, bounds}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, Cursor>, Fail{error})
            case Done{ByteBlockReader.End{}}:
              do IO<Result<&1, &1, U32 & String, Cursor>>:
                reopened : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
                  ByteBlockReader.open(path)
                verify.complete(bounds, reopened)
            case Done{ByteBlockReader.Block{reader, _}}:
              verify.loop(rest, path, VerifyNeed{reader, bounds})

def open.budget(
  path: String,
  bounds: Bounds,
  pair: Nat & ByteBlockReader.Reader
) -> IO(Result<&1, &1, U32 & String, Cursor>):
  match pair:
    case (fuel, reader):
      verify.loop(fuel, path, VerifyNeed{reader, bounds})

def open.result(
  path: String,
  bounds: Bounds,
  opened: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Result<&1, &1, U32 & String, Cursor>):
  match opened:
    case Fail{error}: IO.pure(Result<&1, &1, U32 & String, Cursor>, Fail{error})
    case Done{reader}:
      open.budget(path, bounds, ByteBlockReader.transition_budget(reader))

def open.trusted.result(
  bounds: Bounds,
  opened: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Result<&1, &1, U32 & String, Cursor>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Cursor>, Fail{error})
    case Done{reader}:
      verify.complete(bounds, Done{reader})

# Reopens a previously validated generation without rescanning every block.
def open.trusted(
  +path: String,
  bounds: Bounds
) -> IO(Result<&1, &1, U32 & String, Cursor>):
  do IO<Result<&1, &1, U32 & String, Cursor>>:
    opened : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
      ByteBlockReader.open(path)
    open.trusted.result(bounds, opened)

# Validates the complete SST before opening a second bounded scan pass.
def open(
  +path: String,
  bounds: Bounds
) ->
  IO(Result<&1, &1, U32 & String, Cursor>):
  do IO<Result<&1, &1, U32 & String, Cursor>>:
    opened : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
      ByteBlockReader.open(path)
    open.result(path, bounds, opened)

def scan.start(pair: Nat & ByteBlockReader.Reader, bounds: Bounds) -> IO(Step):
  match pair:
    case (fuel, reader): scan.loop(fuel, ScanNeed{reader, bounds})

# Returns the next bounded record, range skip, end, or terminal read error.
def next(cursor: Cursor) -> IO(Step):
  match cursor:
    case Active{inner, bounds}:
      match inner:
        case ByteBlockReader.EntryReady{reader, entries}:
          match entries:
            case Con{entry, tail}:
              scan.entry(entry, ByteBlockReader.EntryReady{reader, tail}, bounds)
            case Nil{}:
              scan.start(ByteBlockReader.transition_budget(reader), bounds)
        case ByteBlockReader.EntryEnded{}:
          IO.pure(Step, End{})
        case ByteBlockReader.EntryClosed{}:
          IO.pure(Step, End{})
        case ByteBlockReader.EntryFailed{error}:
          IO.pure(Step, Error{error})
    case Ended{}: IO.pure(Step, End{})
    case Closed{}: IO.pure(Step, End{})
    case Failed{error}: IO.pure(Step, Error{error})

# Advances the remaining scan to an inclusive lower byte key.
def seek(cursor: Cursor, lower: Maybe<&1, Bytes.Bytes>) -> Cursor:
  match cursor:
    case Active{inner, bounds}:
      match bounds:
        case Bounds{_, upper, prefix}:
          Active{inner, Bounds{lower, upper, prefix}}
    case Ended{}: Ended{}
    case Closed{}: Closed{}
    case Failed{error}: Failed{error}

# Releases the active file reader, preserving terminal cursors.
def close(cursor: Cursor) -> IO(Result<&1, &1, U32 & String, Unit>):
  match cursor:
    case Active{inner, _}: ByteBlockReader.entry.close(inner)
    case _:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
