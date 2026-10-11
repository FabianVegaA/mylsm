import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Models one ordered row or the end of the reference map.
type Expected is Type:
  ExpectedEnd{}
  ExpectedRow{key: Bytes.Bytes, value: Bytes.Bytes, tail: Expected}

# Distinguishes the full, bounded-range, and prefix reference scans.
type ScanPhase is Data:
  FullScan{}
  RangeScan{}
  PrefixScan{}

# Carries one incremental public scan comparison transition.
type CompareState is Type:
  Opening{phase: ScanPhase, expected: Expected,
    pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>}
  Reading{handle: MyLSM.Bytes.Handle, phase: ScanPhase,
    expected: Expected, step: MyLSM.Bytes.StreamStep}
  CheckingRow{handle: MyLSM.Bytes.Handle, cursor: MyLSM.Bytes.Cursor,
    phase: ScanPhase, tail: Expected, key_valid: Bool, value_valid: Bool}
  Closing{handle: MyLSM.Bytes.Handle, phase: ScanPhase,
    result: Result<&1, &1, MyLSM.Bytes.Error, Unit>}

# Unwraps a valid byte vector from the fixed hexadecimal fixture.
def parsed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Decodes a closed hexadecimal key or value vector.
def bytes(hex: String) -> Bytes.Bytes:
  parsed(Bytes.from_hex(hex))

# Compares byte strings using the database key comparator.
def equal(left: Bytes.Bytes, right: Bytes.Bytes) -> Bool:
  Keys.Bytes.eq(left, right)

# Stops the integration fixture after a failed assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def expected.full() -> Expected:
  ExpectedRow{bytes("61"), bytes("31"),
    ExpectedRow{bytes("62"), bytes("3230"),
      ExpectedRow{bytes("64"), bytes("34"),
        ExpectedRow{bytes("65"), bytes("35"), ExpectedEnd{}}}}}

def expected.range() -> Expected:
  ExpectedRow{bytes("62"), bytes("3230"),
    ExpectedRow{bytes("64"), bytes("34"), ExpectedEnd{}}}

def expected.prefix() -> Expected:
  ExpectedRow{bytes("65"), bytes("35"), ExpectedEnd{}}

def database.closed(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_SCAN_REFERENCE_PASSED")
    case Fail{_}: fail("reference scan database did not close")

def scan.closed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        database.closed(closed)
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("reference scan cursor did not close")

def scan.failed(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  message: String
) -> IO(Unit):
  do IO<Unit>:
    _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
    _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
    fail(message)

# Checks every streamed row against the bounded visible-map reference.
def compare(fuel: Nat, state: CompareState) -> IO(Unit):
  match fuel:
    case 0n:
      match state:
        case Opening{_, _, pair}:
          match pair:
            case (handle, Done{cursor}):
              scan.failed(handle, cursor,
                "reference scan exceeded its bounded transition budget")
            case (handle, Fail{_}):
              do IO<Unit>:
                _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
                  MyLSM.Bytes.close(handle)
                fail("reference scan exceeded its bounded transition budget")
        case Reading{handle, _, _, step}:
          match step:
            case MyLSM.StreamItem{_, _, cursor}:
              scan.failed(handle, cursor,
                "reference scan exceeded its bounded transition budget")
            case MyLSM.StreamSkip{cursor}:
              scan.failed(handle, cursor,
                "reference scan exceeded its bounded transition budget")
            case MyLSM.StreamEnd{cursor}:
              scan.failed(handle, cursor,
                "reference scan exceeded its bounded transition budget")
            case MyLSM.StreamFailure{_, cursor}:
              scan.failed(handle, cursor,
                "reference scan exceeded its bounded transition budget")
        case CheckingRow{handle, cursor, _, _, _, _}:
          scan.failed(handle, cursor,
            "reference scan exceeded its bounded transition budget")
        case Closing{handle, _, result}:
          scan.closed(handle, result)
    case 1n+rest:
      match state:
        case Opening{phase, expected, pair}:
          match pair:
            case (handle, Done{cursor}):
              do IO<Unit>:
                first : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
                compare(rest, Reading{handle, phase, expected, first})
            case (handle, Fail{_}):
              do IO<Unit>:
                _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
                  MyLSM.Bytes.close(handle)
                fail("reference scan did not open")
        case Reading{handle, phase, expected, step}:
          match expected step:
            case ExpectedEnd{}, MyLSM.StreamEnd{cursor}:
              do IO<Unit>:
                closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
                  MyLSM.Bytes.scan_close(cursor)
                compare(rest, Closing{handle, phase, closed})
            case ExpectedEnd{}, MyLSM.StreamItem{_, _, next_cursor}:
              scan.failed(handle, next_cursor,
                "reference scan included an unexpected row")
            case ExpectedEnd{}, MyLSM.StreamSkip{next_cursor}:
              do IO<Unit>:
                next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(next_cursor)
                compare(rest, Reading{handle, phase, expected, next})
            case _, MyLSM.StreamFailure{_, cursor}:
              scan.failed(handle, cursor, "reference scan returned a read failure")
            case ExpectedRow{_, _, _}, MyLSM.StreamEnd{cursor}:
              scan.failed(handle, cursor, "reference scan omitted an expected row")
            case ExpectedRow{_, _, _}, MyLSM.StreamSkip{next_cursor}:
              do IO<Unit>:
                next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(next_cursor)
                compare(rest, Reading{handle, phase, expected, next})
            case ExpectedRow{expected_key, expected_value, tail},
                MyLSM.StreamItem{key, value, next_cursor}:
              compare(rest, CheckingRow{handle, next_cursor, phase, tail,
                equal(key, expected_key), equal(value, expected_value)})
        case CheckingRow{handle, cursor, phase, tail, key_valid, value_valid}:
          match key_valid:
            case False{}:
              scan.failed(handle, cursor,
                "reference scan key differs from the visible map")
            case True{}:
              match value_valid:
                case False{}:
                  scan.failed(handle, cursor,
                    "reference scan value differs from the visible map")
                case True{}:
                  do IO<Unit>:
                    next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
                    compare(rest, Reading{handle, phase, tail, next})
        case Closing{handle, phase, result}:
          match phase result:
            case FullScan{}, Done{Unit{}}:
              do IO<Unit>:
                pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
                  MyLSM.Bytes.Cursor> <- MyLSM.Bytes.scan_range(handle,
                    Some{bytes("62")}, Some{bytes("65")})
                compare(rest, Opening{RangeScan{}, expected.range(), pair})
            case RangeScan{}, Done{Unit{}}:
              do IO<Unit>:
                pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
                  MyLSM.Bytes.Cursor> <- MyLSM.Bytes.scan_prefix(handle, bytes("65"))
                compare(rest, Opening{PrefixScan{}, expected.prefix(), pair})
            case PrefixScan{}, Done{Unit{}}: scan.closed(handle, result)
            case _, Fail{_}: scan.closed(handle, result)

# Opens the recovered database before starting its three reference scans.
def reopened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
          MyLSM.Bytes.scan_range(handle, None{}, None{})
        compare(256n, Opening{FullScan{}, expected.full(), pair})
    case Fail{_}: fail("reference map database could not reopen")

def compacted.closed(
  path: String,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        reopened(opened)
    case Fail{_}: fail("reference map handle did not close after compaction")

# Closes the compacted writer and reopens its published generation.
def compacted(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
        compacted.closed(path, closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("reference map compaction failed")

def second.flushed(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        compacted_pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.compact(handle)
        compacted(compacted_pair)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("second reference map flush failed")

def updated.value.checked(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        second.flushed(flushed)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("reference map write did not replace key b")

# Verifies the newest batch value before publishing its SST state.
def updated.value(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      updated.value.checked(handle, equal(value, bytes("3230")))
    case (handle, Done{None{}}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("reference map update did not preserve key b")
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("reference map update could not be read")

# Reads the replaced key before flushing the mixed update batch.
def updated(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        read : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Maybe<&1, Bytes.Bytes>> <- MyLSM.Bytes.get(handle, bytes("62"))
        updated.value(read)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("reference map update batch failed")

# Applies replacement, tombstone, and insertion mutations as one batch.
def changed(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, Con{
            MyLSM.BytesPut{bytes("62"), bytes("3230")},
            Con{MyLSM.BytesDelete{bytes("63")},
              Con{MyLSM.BytesPut{bytes("65"), bytes("35")}, Nil{}}}})
        updated(written)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("initial reference map flush failed")

# Flushes the seed generation before applying the second batch.
def seeded(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        changed(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("reference map seed batch failed")

# Creates the database and seeds the initial ordered map.
def created(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, Con{
            MyLSM.BytesPut{bytes("61"), bytes("31")},
            Con{MyLSM.BytesPut{bytes("62"), bytes("32")},
              Con{MyLSM.BytesPut{bytes("63"), bytes("33")},
                Con{MyLSM.BytesPut{bytes("64"), bytes("34")}, Nil{}}}}})
        seeded(written)
    case Fail{_}: fail("reference map database could not be created")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.create(path)
    created(result)
