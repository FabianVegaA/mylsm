import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/Fs.bend as Fs
import ../../src/transfer/Restore.bend as Restore
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Encodes an integer key using the canonical four-byte big-endian form.
def key(index: Nat) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, U32.from_nat(index))

# Builds one binary key with a fixed-size value for a multi-block export.
def mutation(index: Nat) -> MyLSM.Bytes.Mutation:
  MyLSM.BytesPut{key(index), Bytes.new(512)}

def mutations.loop(
  fuel: Nat,
  +index: Nat,
  acc: List<&1, MyLSM.Bytes.Mutation>
) -> List<&1, MyLSM.Bytes.Mutation>:
  match fuel:
    case 0n: List.reverse(&1, MyLSM.Bytes.Mutation, acc)
    case 1n+rest:
      +current = index
      +next = Nat.add(index, 1n)
      mutations.loop(rest, next, Con{mutation(current), acc})

# Builds an ordered fixture batch using its declared record count as fuel.
def mutations(count: Nat) -> List<&1, MyLSM.Bytes.Mutation>:
  mutations.loop(count, 0n, Nil{})

# Unwraps a fixed byte fixture.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Stops the fixture at the first failed expectation.
def require(valid: Bool, message: String) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def backup.file.decoded(result: Result<&1, &1, Restore.Error, Restore.Decoded>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "published backup failed exchange validation")
    case Done{Restore.Decoded{entries}}:
      do IO<Unit>:
        require(Nat.is_eq(List.length(&1, ByteMemTable.Entry, entries), 255n),
          "published backup lost source records")
        IO.print("PUBLIC_BACKUP_FILE_PASSED")

def backup.file.read(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Unit):
  match pair:
    case (file, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        IO.die(Unit, 1, "published backup bytes could not be read")
    case (file, Done{bytes}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        backup.file.decoded(Restore.decode(bytes))

def backup.file.opened(opened: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match opened:
    case Fail{_}: IO.die(Unit, 1, "published backup file could not be opened")
    case Done{file}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_bytes(file, 1048576)
        backup.file.read(pair)

def backup.file.closed(
  +path: String,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "database did not close after backup")
    case Done{Unit{}}:
      do IO<Unit>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path ++ "/BACKUP", "r")
        backup.file.opened(opened)

def backup.permission.checked(
  +path: String,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.Io{_, _}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        backup.file.closed(path, closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "backup permission failure was misclassified")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "backup was written into a directory without write permission")


def backup.duplicate.checked(
  +path: String,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.AlreadyExists{}}):
      do IO<Unit>:
        blocked : String <- IO.try(String, Console.get_env("MYLSM_BACKUP_BLOCKED_PATH"))
        failed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.backup_to(blocked, handle)
        backup.permission.checked(path, failed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "existing backup destination was misclassified")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "backup replaced an existing destination")

def backup.exported.exists(
  +path: String,
  handle: MyLSM.Bytes.Handle,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(Unit):
  match exists:
    case Done{True{}}:
      do IO<Unit>:
        duplicate : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.backup_to(path, handle)
        backup.duplicate.checked(path, duplicate)
    case Done{False{}}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "published backup destination is missing")
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "published backup destination cannot be inspected")


def backup.exported(
  +path: String,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.AlreadyExists{}}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "backup destination or staging path already exists")
    case (handle, Fail{MyLSM.Io{_, message}}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, message)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "snapshot backup file publication failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path)
        backup.exported.exists(path, handle, exists)

def backup.deleted(
  +path: String,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "backup tombstone write failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        exported : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.backup_to(path, handle)
        backup.exported(path, exported)


def backup.flushed(
  +path: String,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "backup source flush failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        deleted : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.delete(handle, key(7n))
        backup.deleted(path, deleted)

def backup.written.result(
  +path: String,
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "backup fixture write failed")
    case Done{Unit{}}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        backup.flushed(path, pair)

def backup.written(
  +path: String,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, result): backup.written.result(path, handle, result)

def backup.created(
  +path: String,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "backup fixture database could not be created")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, mutations(256n))
        backup.written(path, pair)

def main() -> IO(Unit):
  do IO<Unit>:
    database : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    destination : String <- IO.try(String, Console.get_env("MYLSM_BACKUP_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.create(database)
    backup.created(destination, result)
