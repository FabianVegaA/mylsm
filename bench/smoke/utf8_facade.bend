import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Reports the fixture result after closing the text handle.
def finish(result: Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      IO.print("UTF8_FACADE_PASSED")
    case Fail{_}:
      IO.die(Unit, 1, "UTF-8 facade close failed")

def verified.equal(handle: MyLSM.Utf8.Handle, equal: Bool) -> IO(Unit):
  match equal:
    case True{}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        finish(closed)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 facade changed text")

# Checks the recovered text value before closing the handle.
def verified(
  result: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>
) -> IO(Unit):
  match result:
    case (next_handle, Done{Some{value}}):
      verified.equal(next_handle, String.eq(value, "valor UTF-8"))
    case (next_handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(next_handle)
        IO.die(Unit, 1, "UTF-8 facade did not read its value")

def stats.valid(handle: MyLSM.Utf8.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        result : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <-
          MyLSM.Utf8.get(handle, "clave")
        verified(result)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 facade stats omitted the compacted table")

def stats.result(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Stats>) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.Utf8Stats{MyLSM.ByteStats{entries, _}}}):
      stats.valid(handle, Nat.is_eq(entries, 1n))
    case (handle, Fail{_}): stats.valid(handle, False{})

def compacted.result(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        observed : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error,
          MyLSM.Utf8.Stats> <- MyLSM.Utf8.stats(handle)
        stats.result(observed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 facade compaction failed")

# Compacts the committed text entry before recovery checks.
def written(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>
) -> IO(Unit):
  match pair:
    case (handle, Done{_}):
      do IO<Unit>:
        result : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.compact(handle)
        compacted.result(result)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 facade write failed")

# Creates a byte-backed database and writes a non-ASCII text value.
def created(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
          MyLSM.Utf8.put(handle, "clave", "valor UTF-8")
        written(pair)
    case Fail{_}:
      IO.die(Unit, 1, "UTF-8 facade create failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.create(path)
    created(result)
