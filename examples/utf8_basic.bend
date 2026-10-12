import Base
import ../mylsm.bend as MyLSM

# Reports a successful close after the text round trip.
def finished(result: Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("UTF8_EXAMPLE_OK")
    case Fail{_}: IO.die(Unit, 1, "could not close the database")

# Prints the stored value and releases the owned handle.
def read(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      do IO<Unit>:
        IO.print(value)
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        finished(closed)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "could not read the text value")

# Threads the returned handle into the next operation.
def written(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>) -> IO(Unit):
  match pair:
    case (handle, Done{_}):
      do IO<Unit>:
        value : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <-
          MyLSM.Utf8.get(handle, "saludo")
        read(value)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "could not write the text value")

# Writes a text key and value into a new database.
def created(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
          MyLSM.Utf8.put(handle, "saludo", "¡Hola, Bend!")
        written(pair)
    case Fail{_}: IO.die(Unit, 1, "could not create the database")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.create(path)
    created(result)
