import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Converts a checked hexadecimal fixture into its byte representation.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Extracts the equality result from the byte comparison witness.
def equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, same): same

def clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

def footer.expected(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (output, hash_input):
      Bytes.concat([output, SHA.sha256_packed_bytes(hash_input)])

# Stops the smoke test when an exported chunk violates its expected shape.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def close.result(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_BACKUP_STREAM_PASSED")
    case Fail{_}: IO.die(Unit, 1, "database lock did not close after backup")

# Closes the database after the backup reaches its terminal state.
def close(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
    close.result(result)

def backup.ended(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.BackupStep>
) -> IO(Unit):
  match result:
    case Done{MyLSM.BackupEnd{}}: close(handle)
    case _: IO.die(Unit, 1, "backup stream must end after one footer")

def backup.footer(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.BackupStep>
) -> IO(Unit):
  match result:
    case Done{MyLSM.BackupChunk{stream, bytes}}:
      do IO<Unit>:
        footer : Bytes.Bytes = Bytes.concat([
          packed(Bytes.from_hex("454e4431")),
          Bytes.set.u32be(Bytes.new(4), 0, 2),
          Bytes.set.u32be(Bytes.new(4), 0, 1)
        ])
        expected : Bytes.Bytes = footer.expected(clone.split(footer))
        require(equal(Bytes.eq(bytes, expected)),
          "footer must preserve the snapshot totals")
        backup.ended(handle, MyLSM.Bytes.backup_next(stream))
    case _: IO.die(Unit, 1, "backup stream omitted its footer")

def backup.block.marker(pair: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match pair:
    case (_, value): equal(Bytes.eq(value, packed(Bytes.from_hex("424c4b31"))))

def backup.block(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.BackupStep>
) -> IO(Unit):
  match result:
    case Done{MyLSM.BackupChunk{stream, bytes}}:
      do IO<Unit>:
        marker : Bytes.Bytes & Bytes.Bytes = Bytes.slice(bytes, 0, 4)
        require(backup.block.marker(marker), "backup data page marker is invalid")
        backup.footer(handle, MyLSM.Bytes.backup_next(stream))
    case _: IO.die(Unit, 1, "backup stream omitted its data page")

def backup.header(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.BackupStep>
) -> IO(Unit):
  match result:
    case Done{MyLSM.BackupChunk{stream, bytes}}:
      do IO<Unit>:
        expected : Bytes.Bytes = Bytes.concat([
          packed(Bytes.from_hex("4d594c534d424b31")),
          Bytes.set.u32be(Bytes.new(4), 0, 1),
          Bytes.set.u32be(Bytes.new(4), 0, 2),
          Bytes.set.u32be(Bytes.new(4), 0, 1)
        ])
        require(equal(Bytes.eq(bytes, expected)),
          "backup header must describe the stable pre-write snapshot")
        backup.block(handle, MyLSM.Bytes.backup_next(stream))
    case _: IO.die(Unit, 1, "backup stream omitted its header")

def backup.created.write(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  stream: MyLSM.Bytes.BackupStream
) -> IO(Unit):
  match pair:
    case (updated, Done{Unit{}}):
      backup.header(updated, MyLSM.Bytes.backup_next(stream))
    case _: IO.die(Unit, 1, "write after snapshot creation failed")

def backup.created(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.BackupStream>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "backup could not retain a stable snapshot")
    case Done{stream}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, packed(Bytes.from_hex("63")),
            packed(Bytes.from_hex("6e")))
        backup.created.write(pair, stream)

def backup.opened(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.BackupStream>
) -> IO(Unit):
  match pair:
    case (handle, result): backup.created(handle, result)

# Starts the stable backup after the input rows have been flushed to SST.
def backup.flushed(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          MyLSM.Bytes.BackupStream> <- MyLSM.Bytes.backup(handle)
        backup.opened(result)
    case _: IO.die(Unit, 1, "flush before backup failed")

def put.second(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        backup.flushed(flushed)
    case _: IO.die(Unit, 1, "second fixture write failed")

def put.first(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, packed(Bytes.from_hex("62")),
            packed(Bytes.from_hex("32")))
        put.second(result)
    case _: IO.die(Unit, 1, "first fixture write failed")

# Creates a database and the two records retained by the exported snapshot.
def created(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, packed(Bytes.from_hex("61")),
            packed(Bytes.from_hex("31")))
        put.first(pair)
    case _: IO.die(Unit, 1, "public byte database creation failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.create(path)
    created(result)
