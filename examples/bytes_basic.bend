import Base
import ../mylsm.bend as MyLSM
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes

# Requires each example's hexadecimal literal to decode successfully.
def from_hex(result: Maybe<&1, PackedBytes.Bytes>) -> IO(PackedBytes.Bytes):
  match result:
    case Some{bytes}: IO.pure(PackedBytes.Bytes, bytes)
    case None{}: IO.die(PackedBytes.Bytes, 1, "invalid hexadecimal input")

# Extracts the equality result after the byte buffers are consumed.
def equal(result: PackedBytes.Bytes & PackedBytes.Bytes & Bool) -> Bool:
  match result:
    case (_, _, same): same

# Reports a successful close after the byte round trip.
def finished(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("BYTES_EXAMPLE_OK")
    case Fail{_}: IO.die(Unit, 1, "could not close the database")

def read.equal(handle: MyLSM.Bytes.Handle, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        finished(closed)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "the stored bytes changed")

# Checks that the stored value preserves every byte.
def read(
  expected: PackedBytes.Bytes,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      read.equal(handle, equal(PackedBytes.eq(value, expected)))
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "could not read the byte value")

# Recreates consumed buffers for the read comparison.
def written(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        key : PackedBytes.Bytes <- from_hex(PackedBytes.from_hex("00ff"))
        expected : PackedBytes.Bytes <- from_hex(PackedBytes.from_hex("80ff00"))
        value : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, key)
        read(expected, value)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "could not write the byte value")

# Writes a binary key and value into a new database.
def created(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        key : PackedBytes.Bytes <- from_hex(PackedBytes.from_hex("00ff"))
        value : PackedBytes.Bytes <- from_hex(PackedBytes.from_hex("80ff00"))
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, key, value)
        written(pair)
    case Fail{_}: IO.die(Unit, 1, "could not create the database")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <- MyLSM.Bytes.create(path)
    created(result)
