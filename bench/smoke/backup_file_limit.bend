import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Reads a fixture setting from the host environment.
def env(name: String) -> IO(String):
  IO.try(String, Console.get_env(name))

# Unwraps the fixed binary key used by the fixture.
def key.result(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Returns the binary database key used by the backup fixture.
def key() -> Bytes.Bytes:
  key.result(Bytes.from_hex("6b"))

def create.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("BACKUP_LIMIT_SOURCE_READY")
    case Fail{_}: IO.die(Unit, 1, "source database did not close")

def create.flushed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        create.closed(closed)
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "source database flush failed")

def create.flush.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, result): create.flushed(handle, result)

def create.written(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        create.flush.result(flushed)
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "source database write failed")

def create.write.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, result): create.written(handle, result)

def create.result(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "source database could not be created")
    case Done{handle}:
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, key(), Bytes.new(256))
        create.write.result(written)

def backup.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("BACKUP_FILE_LIMIT_HANDLED")
    case Fail{_}: IO.die(Unit, 1, "database lock did not close after backup failure")

def backup.result(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "backup unexpectedly succeeded under the file limit")
    case Fail{_}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        backup.closed(closed)

def backup.write.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, result): backup.result(handle, result)

def backup.opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>,
  destination: String
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "prepared source database could not be reopened")
    case Done{handle}:
      do IO<Unit>:
        backed_up : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.backup_to(destination, handle)
        backup.write.result(backed_up)

def main.mode(mode: String, database: String, destination: String) -> IO(Unit):
  match mode:
    case "create":
      do IO<Unit>:
        created : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.create(database)
        create.result(created)
    case "backup":
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(database)
        backup.opened(opened, destination)
    case _: IO.die(Unit, 1, "unknown backup file-limit mode")

def main() -> IO(Unit):
  do IO<Unit>:
    mode : String <- env("MYLSM_BACKUP_LIMIT_MODE")
    database : String <- env("MYLSM_DB_PATH")
    destination : String <- env("MYLSM_BACKUP_PATH")
    main.mode(mode, database, destination)
