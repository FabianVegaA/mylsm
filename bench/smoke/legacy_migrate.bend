import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/Console.bend as Console
import ../../src/Keys.bend as Keys
import ../../mylsm.bend as MyLSM
import ../../src/transfer/MigrateRunIo.bend as MigrateRunIo
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the migration fixture after a failed assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def fixture.bytes(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def closed.failed(handle: ByteDb.Handle, message: String) -> IO(Unit):
  do IO<Unit>:
    _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    fail(message)

def handle.closed(result: Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: fail("migrated database handle close failed")
    case Done{Unit{}}: IO.print("LEGACY_MIGRATION_PASSED")

def handle.close.ok(handle: ByteDb.Handle) -> IO(Unit):
  do IO<Unit>:
    closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    handle.closed(closed)

def legacy.value.checked(handle: ByteDb.Handle, equal: Bool) -> IO(Unit):
  match equal:
    case False{}: closed.failed(handle, "migrated WAL value did not match")
    case True{}: handle.close.ok(handle)

def legacy.value.result(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}): closed.failed(handle, "migrated WAL read failed")
    case (handle, Done{None{}}): closed.failed(handle, "migrated WAL key missing")
    case (handle, Done{Some{value}}):
      legacy.value.checked(handle, Keys.Bytes.eq(value,
        fixture.bytes(Bytes.from_hex("76616c7565"))))

def legacy.value.read(handle: ByteDb.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>> <-
      ByteDb.get(handle, fixture.bytes(Bytes.from_hex("6c6567616379")))
    legacy.value.result(pair)

def empty.sst.checked(handle: ByteDb.Handle, empty: Bool) -> IO(Unit):
  match empty:
    case False{}: closed.failed(handle, "migrated empty SST value changed")
    case True{}: legacy.value.read(handle)

def empty.sst.length(handle: ByteDb.Handle, pair: Bytes.Bytes & U32) -> IO(Unit):
  match pair:
    case (_, length): empty.sst.checked(handle, U32.is_eq(length, 0))

def empty.sst.result(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}): closed.failed(handle, "migrated empty SST read failed")
    case (handle, Done{None{}}): closed.failed(handle, "migrated empty SST key missing")
    case (handle, Done{Some{value}}):
      empty.sst.length(handle, Bytes.length(value))

def empty.sst.read(handle: ByteDb.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>> <-
      ByteDb.get(handle, fixture.bytes(Bytes.from_hex("63")))
    empty.sst.result(pair)

def second.sst.checked(handle: ByteDb.Handle, equal: Bool) -> IO(Unit):
  match equal:
    case False{}: closed.failed(handle, "migrated SST value did not match")
    case True{}: empty.sst.read(handle)

def second.sst.result(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}): closed.failed(handle, "second migrated SST read failed")
    case (handle, Done{None{}}): closed.failed(handle, "second migrated SST key missing")
    case (handle, Done{Some{value}}):
      second.sst.checked(handle, Keys.Bytes.eq(value,
        fixture.bytes(Bytes.from_hex("74776f"))))

def second.sst.read(handle: ByteDb.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>> <-
      ByteDb.get(handle, fixture.bytes(Bytes.from_hex("62")))
    second.sst.result(pair)

def first.sst.checked(handle: ByteDb.Handle, equal: Bool) -> IO(Unit):
  match equal:
    case False{}: closed.failed(handle, "first migrated SST value did not match")
    case True{}: second.sst.read(handle)

def first.sst.result(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}): closed.failed(handle, "first migrated SST read failed")
    case (handle, Done{None{}}): closed.failed(handle, "first migrated SST key missing")
    case (handle, Done{Some{value}}):
      first.sst.checked(handle, Keys.Bytes.eq(value,
        fixture.bytes(Bytes.from_hex("6f6e65"))))

def first.sst.read(handle: ByteDb.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>> <-
      ByteDb.get(handle, fixture.bytes(Bytes.from_hex("61")))
    first.sst.result(pair)

# Continues the destination data check with the reopened raw byte handle.
def opened(result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: fail("migrated database could not be reopened")
    case Done{handle}: first.sst.read(handle)

def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

# Reopens the destination and checks values from both legacy sources.
def migrated(
  destination: String,
  result: Result<&1, &1, MigrateRunIo.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("legacy migration rejected its valid fixture")
    case Done{Unit{}}:
      do IO<Unit>:
        opened_result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <-
          ByteDb.open_existing(destination)
        opened(opened_result)

def migrate.destination.paths(source: String, destinations: String & String) -> IO(Unit):
  match destinations:
    case (migration_destination, verification_destination):
      do IO<Unit>:
        result : Result<&1, &1, MigrateRunIo.Error, Unit> <-
          MyLSM.migrate_legacy(source, migration_destination)
        migrated(verification_destination, result)

def migrate.paths(source: String, destination: String) -> IO(Unit):
  migrate.destination.paths(source, path.clone.pair(destination))

def main() -> IO(Unit):
  do IO<Unit>:
    source : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    destination : String <- IO.try(String, Console.get_env("MYLSM_MIGRATE_DEST"))
    migrate.paths(source, destination)
