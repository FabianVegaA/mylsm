import Base
import ../../src/Console.bend as Console
import ../../src/Flush.bend as Flush
import ../../src/Fs.bend as Fs
import ../../src/Manifest.bend as Manifest
import ../../src/hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def fixture.hex(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Stops the fixture after a failed assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def u32.bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

def fixture.header() -> Bytes.Bytes:
  Bytes.concat([fixture.hex(Bytes.from_hex("4d594c534d335300")), u32.bytes(0),
    u32.bytes(2), u32.bytes(1)])

def fixture.payload() -> Bytes.Bytes:
  Bytes.concat([fixture.hex(Bytes.from_hex("0000000001610000000178")),
    fixture.hex(Bytes.from_hex("0000000001610000000179"))])

def fixture.block() -> Bytes.Bytes:
  digest = SHA.sha256_packed_bytes(Bytes.concat([
    Bytes.concat([u32.bytes(22), u32.bytes(2)]), fixture.payload()]))
  Bytes.concat([Bytes.concat([u32.bytes(22), u32.bytes(2)]),
    fixture.payload(), digest])

def fixture.block.digest(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, digest): digest

def fixture.file() -> Bytes.Bytes:
  digest = SHA.sha256_packed_bytes(Bytes.concat([fixture.header(),
    fixture.block.digest(Bytes.slice(fixture.block(), 30, 32))]))
  Bytes.concat([fixture.header(), fixture.block(),
    fixture.hex(Bytes.from_hex("454e4433")), u32.bytes(2), digest])

def write.result(
  result: Result<&1, &1, U32 & String, Unit>,
  message: String
) -> IO(Unit):
  match result:
    case Fail{_}: fail(message)
    case Done{Unit{}}: IO.pure(Unit, Unit{})

def write.closed(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  message: String
) -> IO(Unit):
  match pair:
    case (file, result):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        write.result(result, message)

def write.opened(
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match opened:
    case Fail{_}: fail("could not open duplicate legacy SST fixture")
    case Done{file}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        write.closed(pair, "could not write duplicate legacy SST fixture")

# Writes fixture bytes through the filesystem boundary.
def write(path: String, bytes: Bytes.Bytes) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    write.opened(bytes, opened)

def manifest.result(path: String, result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: fail("could not publish duplicate legacy SST manifest")
    case Done{Unit{}}: write(path ++ "/LOCK", Bytes.new(0))

def level.created(
  +path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("could not create duplicate legacy SST level")
    case Done{Unit{}}:
      do IO<Unit>:
        _table : Unit <- write(path ++ "/l0/0.tbl", fixture.file())
        manifest : Result<&1, &1, U32 & String, Unit> <-
          Flush.write_manifest(path ++ "/MANIFEST",
            Manifest.M{Con{Con{"0.tbl", Nil{}},
              Con{Nil{}, Con{Nil{}, Con{Nil{}, Nil{}}}}}})
        manifest.result(path, manifest)

def root.ready(
  +path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("could not create duplicate legacy SST source")
    case Done{Unit{}}:
      do IO<Unit>:
        level : Result<&1, &1, U32 & String, Unit> <- Fs.make_dir(path ++ "/l0")
        level.created(path, level)

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    created : Result<&1, &1, U32 & String, Unit> <- Flush.ensure_dir(path)
    root.ready(path, created)
