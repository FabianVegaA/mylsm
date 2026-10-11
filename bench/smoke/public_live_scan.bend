import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Returns decoded fixture bytes or an empty fallback.
# Returns decoded fixture bytes or an empty fallback.
def bytes.from_hex.result(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Decodes one hexadecimal fixture.

# Decodes one hexadecimal fixture.

def bytes.from_hex(value: String) -> Bytes.Bytes:
  bytes.from_hex.result(Bytes.from_hex(value))

# Extracts equality from the bytes library result.

# Extracts equality from the bytes library result.

def bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, (_, equal)): equal

# Stops the fixture with its failure message.

# Stops the fixture with its failure message.

# Stops the fixture with its failure message.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Confirms the database handle closes after retention is released.

# Confirms the database handle closes after retention is released.

# Confirms the database handle closes after retention is released.
def finish(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_LIVE_BYTE_SCAN_PASSED")
    case Fail{_}: fail("live byte scan did not release its snapshot")

# Checks that all owner retention counters are zero.

# Checks that all owner retention counters are zero.

def stats.valid(snapshots: Nat, retained: Nat, cursors: Nat) -> Bool:
  Nat.is_eq(snapshots, 0n) && Nat.is_eq(retained, 0n) &&
    Nat.is_eq(cursors, 0n)

# Closes the database after verifying retention counters.

def stats.checked(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        finish(closed)
    case False{}: fail("live byte scan leaked owner retention")

# Reads owner retention metrics after the scan ends.

# Reads owner retention metrics after the scans end.
def stats(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>
) -> IO(Unit):
  match result:
    case Done{MyLSM.ByteStats{_, _, snapshots, retained, cursors}}:
      stats.checked(handle, stats.valid(snapshots, retained, cursors))
    case Fail{_}: fail("live byte scan stats failed")

# Preserves the handle returned by the stats request.

def ended.stats(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>) -> IO(Unit):
  match pair:
    case (next, stats_result): stats(next, stats_result)

# Requires the range cursor to produce its end marker.

def ended.prefix.closed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        stats_pair : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats> <-
            MyLSM.Bytes.stats(handle)
        ended.stats(stats_pair)
    case Fail{_}: fail("early live scan close failed")

# Closes a remote prefix cursor before requesting any item.

def ended.prefix.opened(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match result:
    case Done{cursor}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.scan_close(cursor)
        ended.prefix.closed(handle, closed)
    case Fail{_}: fail("early live prefix scan failed to open")

# Opens the prefix cursor used to verify early resource release.

def ended.prefix.result(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>) -> IO(Unit):
  match pair:
    case (handle, result): ended.prefix.opened(handle, result)

# Requires the range cursor to produce its end marker.

def ended.prefix(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    opened : MyLSM.Bytes.Handle &
      Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
        MyLSM.Bytes.scan_prefix(handle, bytes.from_hex("00"))
    ended.prefix.result(opened)

# Routes the prefix-open result while retaining its database handle.

# Checks terminal auto-release before checking early-close cleanup.
def ended(handle: MyLSM.Bytes.Handle, step: MyLSM.Bytes.StreamStep) -> IO(Unit):
  match step:
    case MyLSM.StreamEnd{_}: ended.prefix(handle)
    case _: fail("live byte scan did not reach its end marker")

# Checks the final binary key and reads the end marker.

# Checks the fourth key and then requires automatic terminal cleanup.

def fourth.checked(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        ended_step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        ended(handle, ended_step)
    case False{}: fail("live byte scan changed its fourth key")

# Validates the fourth ordered range item.

# Validates the fourth ordered range item.

def fourth.step(handle: MyLSM.Bytes.Handle, step: MyLSM.Bytes.StreamStep) -> IO(Unit):
  match step:
    case MyLSM.StreamItem{key, _, next}:
      fourth.checked(handle, next,
        bytes.equal(Bytes.eq(key, bytes.from_hex("02ff"))))
    case _: fail("live byte scan omitted its fourth key")

# Checks the middle binary key before continuing.

# Checks the third binary key before continuing.

def third.checked(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        fourth_step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        fourth.step(handle, fourth_step)
    case False{}: fail("live byte scan changed its third key")

# Validates the third ordered range item.

# Validates the third ordered range item.

def third.step(handle: MyLSM.Bytes.Handle, step: MyLSM.Bytes.StreamStep) -> IO(Unit):
  match step:
    case MyLSM.StreamItem{key, _, next}:
      third.checked(handle, next,
        bytes.equal(Bytes.eq(key, bytes.from_hex("0104"))))
    case _: fail("live byte scan omitted its third key")

# Reads the third range item.

# Reads the third range item.

# Reads the third range item.
def third(handle: MyLSM.Bytes.Handle, cursor: MyLSM.Bytes.Cursor) -> IO(Unit):
  do IO<Unit>:
    step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
    third.step(handle, step)

# Checks the fourth key and then requires automatic terminal cleanup.

# Checks the middle binary key before continuing.

def second.checked(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}: third(handle, cursor)
    case False{}: fail("live byte scan changed its second key")

# Validates the second ordered range item.

# Validates the second ordered range item.

def second.step(handle: MyLSM.Bytes.Handle, step: MyLSM.Bytes.StreamStep) -> IO(Unit):
  match step:
    case MyLSM.StreamItem{key, _, next}:
      second.checked(handle, next,
        bytes.equal(Bytes.eq(key, bytes.from_hex("0103"))))
    case _: fail("live byte scan omitted its second key")

# Reads the second range item.

# Reads the second range item.

# Reads the second range item.
def second(handle: MyLSM.Bytes.Handle, cursor: MyLSM.Bytes.Cursor) -> IO(Unit):
  do IO<Unit>:
    step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
    second.step(handle, step)

# Checks the first binary key in byte order.

# Checks the first binary key in byte order.

def first.checked(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}: second(handle, cursor)
    case False{}: fail("live byte scan changed its first key")

# Validates the first ordered range item.

# Validates the first ordered range item.

def first.step(handle: MyLSM.Bytes.Handle, step: MyLSM.Bytes.StreamStep) -> IO(Unit):
  match step:
    case MyLSM.StreamItem{key, _, next}:
      first.checked(handle, next,
        bytes.equal(Bytes.eq(key, bytes.from_hex("00ff"))))
    case _: fail("live byte scan omitted its first key")

# Reads the first range item.

# Reads the first range item.

# Reads the first range item.
def first(handle: MyLSM.Bytes.Handle, cursor: MyLSM.Bytes.Cursor) -> IO(Unit):
  do IO<Unit>:
    step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
    first.step(handle, step)

# Starts the scan only after cursor creation succeeds.

# Starts the scan only after cursor creation succeeds.

# Starts the scan only after cursor creation succeeds.
def opened(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match result:
    case Done{cursor}: first(handle, cursor)
    case Fail{_}: fail("public live byte range scan failed to open")

# Routes the cursor result into item validation.

# Routes the cursor result into item validation.

def main.cursor.opened(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>) -> IO(Unit):
  match pair:
    case (handle, result): opened(handle, result)

# Opens a range through the public owner-aware API.

# Opens a range through the public owner-aware API.

def main.opened(
  pair: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match pair:
    case Fail{_}: fail("public live byte scan could not open owner")
    case Done{handle}:
      do IO<Unit>:
        opened_pair : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
            MyLSM.Bytes.scan_range(handle, Some{bytes.from_hex("00ff")},
              Some{bytes.from_hex("0300")})
        main.cursor.opened(opened_pair)

# Runs an owner range scan through its end marker.

# Runs an owner range scan through its end marker.

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    pair : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing_wait(path, 1000, 10)
    main.opened(pair)

