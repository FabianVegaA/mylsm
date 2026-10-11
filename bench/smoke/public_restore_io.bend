import Base
import ../../mylsm.bend as MyLsm
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/Console.bend as Console
import ../../src/transfer/Backup.bend as Backup
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Decodes a fixed hexadecimal smoke-fixture value.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def backup.collect(
  fuel: Nat,
  result: Result<&1, &1, Backup.Error, Backup.Step>,
  output: Bytes.Bytes
) -> Maybe<&1, Bytes.Bytes>:
  match fuel:
    case 0n: None{}
    case 1n+rest:
      match result:
        case Fail{_}: None{}
        case Done{Backup.End{}}: Some{output}
        case Done{Backup.Chunk{stream, bytes}}:
          backup.collect(rest, Backup.next(stream), Bytes.concat([output, bytes]))

def backup.started(
  result: Result<&1, &1, Backup.Error, Backup.Stream>
) -> Maybe<&1, Bytes.Bytes>:
  match result:
    case Fail{_}: None{}
    case Done{stream}:
      match stream:
        case Backup.Stream{phase, entries, entry_count, +block_count, block_index}:
          backup.collect(Nat.add(U32.to_nat(block_count), 3n),
            Backup.next(Backup.Stream{phase, entries, entry_count, block_count,
              block_index}), Bytes.new(0))

def backup.input() -> Maybe<&1, Bytes.Bytes>:
  backup.started(Backup.start([
    ByteMemTable.Entry{packed(Bytes.from_hex("006b")),
      Some{packed(Bytes.from_hex("00ff"))}}
  ]))

# Recognizes successful publication through the public restore API.
def restored(result: Result<&1, &1, MyLsm.Bytes.Error, Unit>) -> Bool:
  match result:
    case Done{Unit{}}: True{}
    case _: False{}

# Recognizes no-clobber rejection for an existing destination.
def already_exists(result: Result<&1, &1, MyLsm.Bytes.Error, Unit>) -> Bool:
  match result:
    case Fail{MyLsm.AlreadyExists{}}: True{}
    case _: False{}

def count.one(pair: MyLsm.Bytes.Handle & MyLsm.Bytes.Stats) -> Bool:
  match pair:
    case (_, MyLsm.ByteStats{entries, _}): Nat.is_eq(entries, 1n)

def bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

def error.message(error: MyLsm.Bytes.Error) -> String:
  match error:
    case MyLsm.AlreadyExists{}: "destination already exists"
    case MyLsm.Corruption{message}: message
    case MyLsm.Io{_, message}: message
    case MyLsm.ResourceLimit{}: "restore resource limit"
    case MyLsm.CommitUnknown{_, message}: message
    case MyLsm.NotFound{}: "restore not found"
    case MyLsm.Busy{}: "restore busy"
    case MyLsm.InvalidArgument{}: "restore invalid argument"
    case MyLsm.UnsupportedPlatform{}: "restore unsupported platform"
    case _: "restore failed with a different typed error"

# Stops the smoke fixture when an expectation fails.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def finish.closed(result: Result<&1, &1, MyLsm.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "restored database could not close")
    case Done{Unit{}}: IO.print("PUBLIC_RESTORE_IO_PASSED")

def finish.value(
  pair: MyLsm.Bytes.Handle & Result<&1, &1, MyLsm.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): IO.die(Unit, 1, "restored binary key could not be read")
    case (handle, Done{None{}}): IO.die(Unit, 1, "restored binary key is missing")
    case (handle, Done{Some{value}}):
      do IO<Unit>:
        require(bytes.equal(Bytes.eq(value, packed(Bytes.from_hex("00ff")))),
          "restored binary value differs from backup")
        closed : Result<&1, &1, MyLsm.Bytes.Error, Unit> <- MyLsm.Bytes.close(handle)
        finish.closed(closed)

def finish.stats(pair: MyLsm.Bytes.Handle & Result<&1, &1, MyLsm.Bytes.Error, MyLsm.Bytes.Stats>) -> IO(Unit):
  match pair:
    case (handle, Done{MyLsm.ByteStats{entries, _}}):
      do IO<Unit>:
        require(Nat.is_eq(entries, 1n), "restored database entry count differs")
        pair : MyLsm.Bytes.Handle & Result<&1, &1, MyLsm.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
          MyLsm.Bytes.get(handle, packed(Bytes.from_hex("006b")))
        finish.value(pair)
    case (handle, Fail{_}): IO.die(Unit, 1, "restored database stats failed")

def finish.opened(
  result: Result<&1, &1, MyLsm.Bytes.Error, MyLsm.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "restored database could not be reopened")
    case Done{handle}:
      do IO<Unit>:
        stats : MyLsm.Bytes.Handle & Result<&1, &1, MyLsm.Bytes.Error,
          MyLsm.Bytes.Stats> <- MyLsm.Bytes.stats(handle)
        finish.stats(stats)


def restored.once(
  +destination: String,
  result: Result<&1, &1, MyLsm.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, error.message(error))
    case Done{Unit{}}:
      do IO<Unit>:
        second : Result<&1, &1, MyLsm.Bytes.Error, Unit> <-
          MyLsm.Bytes.restore(destination, Bytes.new(0))
        require(already_exists(second), "restore replaced an existing database")
        opened : Result<&1, &1, MyLsm.Bytes.Error, MyLsm.Bytes.Handle> <-
          MyLsm.Bytes.open_existing(destination)
        finish.opened(opened)

def backup.ready(
  +destination: String,
  result: Maybe<&1, Bytes.Bytes>
) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "backup fixture did not encode")
    case Some{input}:
      do IO<Unit>:
        published : Result<&1, &1, MyLsm.Bytes.Error, Unit> <-
          MyLsm.Bytes.restore(destination, input)
        restored.once(destination, published)

def backup.invalid.checked(result: Result<&1, &1, MyLsm.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{MyLsm.Corruption{_}}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "invalid backup returned the wrong error")
    case Done{Unit{}}: IO.die(Unit, 1, "invalid backup was accepted")

def backup.invalid(destination: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLsm.Bytes.Error, Unit> <-
      MyLsm.Bytes.restore(destination ++ ".invalid", Bytes.new(0))
    backup.invalid.checked(result)

def backup.temp.checked(result: Result<&1, &1, MyLsm.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{MyLsm.AlreadyExists{}}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "preexisting staging path returned the wrong error")
    case Done{Unit{}}: IO.die(Unit, 1, "restore accepted a preexisting staging path")

def backup.temp(destination: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLsm.Bytes.Error, Unit> <-
      MyLsm.Bytes.restore(destination, Bytes.new(0))
    backup.temp.checked(result)

def main() -> IO(Unit):
  do IO<Unit>:
    destination : String <- IO.try(String, Console.get_env("MYLSM_RESTORE_DESTINATION"))
    invalid_destination : String <- IO.try(String,
      Console.get_env("MYLSM_RESTORE_INVALID_DESTINATION"))
    temporary : String <- IO.try(String, Console.get_env("MYLSM_RESTORE_TEMP_DESTINATION"))
    backup.invalid(invalid_destination)
    backup.temp(temporary)
    backup.ready(destination, backup.input())
