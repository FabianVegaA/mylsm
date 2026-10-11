import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Ends the fixture after closing its public UTF-8 handle.
def closed(result: Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_UTF8_BACKUP_FILE_PASSED")
    case Fail{_}: IO.die(Unit, 1, "UTF-8 database did not close")

# Closes the database after publishing through the UTF-8 adapter.
def exported(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 backup publication failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        closed(result)

# Publishes a backup after one successful UTF-8 write.
def written(
  +destination: String,
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): IO.die(Unit, 1, "UTF-8 fixture write failed")
    case (handle, Done{_}):
      do IO<Unit>:
        result : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.backup_to(destination, handle)
        exported(result)

# Creates the database through only public UTF-8 operations.
def created(
  +destination: String,
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "UTF-8 database creation failed")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
          MyLSM.Utf8.put(handle, "café", "niño")
        written(destination, pair)

def main() -> IO(Unit):
  do IO<Unit>:
    database : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    destination : String <- IO.try(String, Console.get_env("MYLSM_BACKUP_PATH"))
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
      MyLSM.Utf8.create(database)
    created(destination, result)
