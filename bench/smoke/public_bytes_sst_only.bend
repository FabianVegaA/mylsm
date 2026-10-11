import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes

def bytes.parsed(result: Maybe<&1, PackedBytes.Bytes>) -> PackedBytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: PackedBytes.new(0)

# Decodes a fixed hexadecimal value for the recovery assertion.
def bytes(hex: String) -> PackedBytes.Bytes:
  bytes.parsed(PackedBytes.from_hex(hex))

def equal.result(pair: PackedBytes.Bytes & PackedBytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

# Releases the test handle after the SST value check.
def closed(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.print("PUBLIC_BYTES_SST_RECOVERED")
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte SST snapshot did not recover invalid UTF-8 bytes")

# Checks that the SST contains the binary value.
def checked(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      closed(handle, equal.result(PackedBytes.eq(value, bytes("80ff00"))))
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte SST snapshot did not recover its key")

# Reads the SST-only database through the public facade.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, bytes("610062"))
        checked(pair)
    case Fail{_}: IO.die(Unit, 1, "byte SST database open failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing_wait(path, 1000, 10)
    opened(result)
