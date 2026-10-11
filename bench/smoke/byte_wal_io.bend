import Base
import ../../src/ByteWal.bend as ByteWal
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/ByteWalIo.bend as ByteWalIo
import ../../src/Fs.bend as Fs
import ../../src/Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def equal.result(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal):
      equal

# Unwraps a known successful hex fixture decode.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Builds the raw-byte mutation batch used by the file smoke.
def batch() -> ByteWal.Batch:
  ByteWal.Batch{Con{
    ByteWal.Put{packed(Bytes.from_hex("610062")), packed(Bytes.from_hex("80ff00"))},
    Con{ByteWal.Delete{Bytes.new(0)}, Nil{}}}}

def recovered.value(pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>) -> Bool:
  match pair:
    case (_, Some{value}):
      equal.result(Bytes.eq(value, packed(Bytes.from_hex("80ff00"))))
    case _:
      False{}

def recovered.deleted(pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>) -> Bool:
  match pair:
    case (_, None{}):
      True{}
    case _:
      False{}

def recovered.finish(
  pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>,
  value_ok: Bool
) -> Bool:
  match pair:
    case (table, deleted):
      value_ok && recovered.deleted((table, deleted))

def recovered.value.deleted(
  pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>
) -> Bool:
  match pair:
    case (table, value):
      recovered.finish(ByteMemTable.get(table, Bytes.new(0)),
        recovered.value((ByteMemTable.empty(), value)))

def recovered.matches(table: ByteMemTable.Table) -> Bool:
  recovered.value.deleted(ByteMemTable.get(table, packed(Bytes.from_hex("610062"))))

def check.matches(ok: Bool, path: String) -> IO(Unit):
  match ok:
    case False{}:
      IO.die(Unit, 1, "recovered byte WAL differs from appended batches")
    case True{}:
      do IO<Unit>:
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(path)
        IO.print("byte WAL file append/recovery passed")

# Confirms that recovery already truncated a final incomplete frame.
def check.second(
  result: Result<&1, &1, U32 & String, ByteMemTable.Table>,
  path: String
) -> IO(Unit):
  match result:
    case Fail{(_, message)}:
      IO.die(Unit, 1, message)
    case Done{table}:
      check.matches(recovered.matches(table), path)

# Dispatches the verification result without consuming the recovered table.
def check.first.matches(ok: Bool, +path: String) -> IO(Unit):
  match ok:
    case False{}:
      IO.die(Unit, 1, "recovered byte WAL differs from appended batches")
    case True{}:
      do IO<Unit>:
        second : Result<&1, &1, U32 & String, ByteMemTable.Table> <- ByteWalIo.recover(path)
        check.second(second, path)

# Reopens the WAL after recovery so an untruncated partial tail would fail.
def check.first(
  result: Result<&1, &1, U32 & String, ByteMemTable.Table>,
  path: String
) -> IO(Unit):
  match result:
    case Fail{(_, message)}:
      IO.die(Unit, 1, message)
    case Done{table}:
      check.first.matches(recovered.matches(table), path)

# Closes the append handle after writing the incomplete length.
def partial.written(
  pair: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match pair:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        return result

# Appends an incomplete four-byte frame length to simulate a torn final write.
def partial.opened(
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{failure})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        pair : File & Result<&1, &1, U32 & String, Unit> <-
          Fs.write_bytes(file, packed(Bytes.from_hex("0000")))
        partial.written(pair)

# Writes the torn-tail fixture bytes at the end of the WAL.
def partial.append(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "a")
    partial.opened(opened)

# Flips one checksum bit without changing the valid frame's declared length.
def corrupt.changed(pair: Bytes.Bytes & Maybe<&2, U32>, +offset: U32) -> Bytes.Bytes:
  match pair:
    case (frame, Some{byte}):
      Bytes.set(frame, offset, U32.xor(byte, 1))
    case (frame, None{}):
      frame

# Returns a frame with its last checksum byte changed.
def corrupt.frame(pair: Bytes.Bytes & U32) -> Bytes.Bytes:
  match pair:
    case (frame, +length):
      corrupt.changed(Bytes.get(frame, (length - 1 : U32)), (length - 1 : U32))

# Writes the checksum-corrupted frame through the file API.
def corrupt.written(
  pair: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match pair:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        return result

# Opens the second WAL and appends a complete frame with a damaged checksum.
def corrupt.opened(
  opened: Result<&1, &1, U32 & String, File>,
  frame: Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{failure})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, frame)
        corrupt.written(pair)

# Reaches the checksum corruption test after encoding a valid fixture frame.
def corrupt.encoded(
  +path: String,
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, Unit>,
        Fail{(1, "could not encode corruption fixture")})
    case Done{frame}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path, "a")
        corrupt.opened(opened, corrupt.frame(Bytes.length(frame)))

# Requires file recovery to reject a complete frame with invalid checksum.
def corrupt.recovered(
  result: Result<&1, &1, U32 & String, ByteMemTable.Table>,
  path: String
) -> IO(Unit):
  match result:
    case Fail{_}:
      do IO<Unit>:
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(path)
        IO.print("byte WAL file corruption check passed")
    case Done{_}:
      IO.die(Unit, 1, "byte WAL file recovery accepted a corrupt checksum")

# Creates a corrupt WAL and verifies recovery rejects it without truncation.
def corrupt.check(+path: String) -> IO(Unit):
  do IO<Unit>:
    _created : Unit <- IO.try(Unit, ByteWalIo.create(path))
    _appended : Unit <- IO.try(Unit, corrupt.encoded(path, ByteWal.encode(batch())))
    result : Result<&1, &1, U32 & String, ByteMemTable.Table> <- ByteWalIo.recover(path)
    corrupt.recovered(result, path)

# Verifies recovery and removes the temporary WAL after success.
def check(result: Result<&1, &1, U32 & String, ByteMemTable.Table>, path: String) -> IO(Unit):
  match result:
    case Fail{(_, message)}:
      IO.die(Unit, 1, message)
    case Done{table}:
      check.matches(recovered.matches(table), path)

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String = ".mylsm-byte-wal-io-smoke.wal"
    _created : Unit <- IO.try(Unit, ByteWalIo.create(path))
    _first : Unit <- IO.try(Unit, ByteWalIo.append(path, batch()))
    _second : Unit <- IO.try(Unit, ByteWalIo.append(path, batch()))
    _partial : Unit <- IO.try(Unit, partial.append(path))
    result : Result<&1, &1, U32 & String, ByteMemTable.Table> <- ByteWalIo.recover(path)
    check.first(result, path)
    corrupt.check(".mylsm-byte-wal-corrupt-smoke.wal")
