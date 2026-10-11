import Base
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/transfer/Backup.bend as Backup
import ../../src/hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the backup stream fixture at its first failed contract.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

# Unwraps a closed hexadecimal fixture into packed bytes.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Extracts equality from the byte library's preserved-input result.
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

# Checks the fixed data-block marker.
def prefix(pair: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match pair:
    case (_, bytes): equal(Bytes.eq(bytes, packed(Bytes.from_hex("424c4b31"))))

def check.finished(result: Result<&1, &1, Backup.Error, Backup.Step>) -> IO(Unit):
  match result:
    case Done{Backup.End{}}: IO.print("BACKUP_STREAM_PASSED")
    case _: IO.die(Unit, 1, "backup stream must end after its footer")

def check.footer(
  result: Result<&1, &1, Backup.Error, Backup.Step>,
  expected: Bytes.Bytes
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "backup stream failed before its footer")
    case Done{Backup.End{}}: IO.die(Unit, 1, "backup stream ended before its footer")
    case Done{Backup.Chunk{stream, bytes}}:
      do IO<Unit>:
        require(equal(Bytes.eq(bytes, expected)), "footer counts must match the header")
        check.finished(Backup.next(stream))

def check.block(
  result: Result<&1, &1, Backup.Error, Backup.Step>,
  expected_footer: Bytes.Bytes
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "backup stream failed before its data block")
    case Done{Backup.End{}}: IO.die(Unit, 1, "backup stream omitted its data block")
    case Done{Backup.Chunk{stream, bytes}}:
      do IO<Unit>:
        require(prefix(Bytes.slice(bytes, 0, 4)), "data block marker must be present")
        check.footer(Backup.next(stream), expected_footer)

def check.header(
  result: Result<&1, &1, Backup.Error, Backup.Step>,
  expected_header: Bytes.Bytes,
  expected_footer: Bytes.Bytes
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "backup stream could not encode its header")
    case Done{Backup.End{}}: IO.die(Unit, 1, "backup stream omitted its header")
    case Done{Backup.Chunk{stream, bytes}}:
      do IO<Unit>:
        require(equal(Bytes.eq(bytes, expected_header)),
          "backup header must declare the format and logical entry counts")
        check.block(Backup.next(stream), expected_footer)

def check.started(
  result: Result<&1, &1, Backup.Error, Backup.Stream>,
  expected_header: Bytes.Bytes,
  expected_footer: Bytes.Bytes
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "backup stream rejected the sorted snapshot")
    case Done{stream}:
      check.header(Backup.next(stream), expected_header, expected_footer)

def main() -> IO(Unit):
  do IO<Unit>:
    entries : List<&1, ByteMemTable.Entry> = [
      ByteMemTable.Entry{packed(Bytes.from_hex("61")), Some{packed(Bytes.from_hex("00ff"))}},
      ByteMemTable.Entry{packed(Bytes.from_hex("62")), None{}},
      ByteMemTable.Entry{packed(Bytes.from_hex("63")), Some{packed(Bytes.from_hex("76"))}}
    ]
    expected_header : Bytes.Bytes = Bytes.concat([
      packed(Bytes.from_hex("4d594c534d424b31")),
      Bytes.set.u32be(Bytes.new(4), 0, 1),
      Bytes.set.u32be(Bytes.new(4), 0, 2),
      Bytes.set.u32be(Bytes.new(4), 0, 1)
    ])
    footer : Bytes.Bytes = Bytes.concat([
      packed(Bytes.from_hex("454e4431")),
      Bytes.set.u32be(Bytes.new(4), 0, 2),
      Bytes.set.u32be(Bytes.new(4), 0, 1)
    ])
    expected_footer : Bytes.Bytes = footer.expected(clone.split(footer))
    check.started(Backup.start(entries), expected_header, expected_footer)
