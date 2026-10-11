import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Closes the UTF-8 handle after one raw backup chunk is observed.
def closed(result: Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_UTF8_BACKUP_PASSED")
    case Fail{_}: IO.die(Unit, 1, "UTF-8 backup handle did not close")

# Closes the database after confirming the UTF-8 backup emits its header.
def close(handle: MyLSM.Utf8.Handle) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
    closed(result)

def backup.header.bound(handle: MyLSM.Utf8.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}: close(handle)
    case False{}: IO.die(Unit, 1, "UTF-8 backup header is truncated")

def backup.header.length(
  handle: MyLSM.Utf8.Handle,
  result: Bytes.Bytes & U32
) -> IO(Unit):
  match result:
    case (_, +length): backup.header.bound(handle, U32.is_le(20, length))
    case _: IO.die(Unit, 1, "UTF-8 backup header length is invalid")

# Checks a backup step returned through the UTF-8 public namespace.
def backup.next.result(
  handle: MyLSM.Utf8.Handle,
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.BackupStep>
) -> IO(Unit):
  match result:
    case Done{MyLSM.Utf8BackupChunk{_, bytes}}:
      backup.header.length(handle, Bytes.length(bytes))
    case _: IO.die(Unit, 1, "UTF-8 backup omitted its first chunk")

# Opens the next header chunk through the UTF-8 public namespace.
def backup.started(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.BackupStream>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): IO.die(Unit, 1, "UTF-8 backup could not open a snapshot")
    case (handle, Done{stream}):
      backup.next.result(handle, MyLSM.Utf8.backup_next(stream))

# Starts a UTF-8 backup after a successful text write.
def written(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): IO.die(Unit, 1, "UTF-8 fixture write failed")
    case (handle, Done{_}):
      do IO<Unit>:
        result : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error,
          MyLSM.Utf8.BackupStream> <- MyLSM.Utf8.backup(handle)
        backup.started(result)

# Creates a database using only public UTF-8 operations.
def created(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "UTF-8 database creation failed")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
          MyLSM.Utf8.put(handle, "key", "value")
        written(pair)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
      MyLSM.Utf8.create(path)
    created(result)
