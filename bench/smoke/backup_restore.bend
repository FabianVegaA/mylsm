import Base
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/transfer/Backup.bend as Backup
import ../../src/transfer/Restore.bend as Restore
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Projects byte equality from the packed-byte comparison result.
def equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, same): same

# Unwraps a fixed hexadecimal test vector.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def empty.valid(result: Result<&1, &1, Restore.Error, Restore.Decoded>) -> Bool:
  match result:
    case Done{Restore.Decoded{Nil{}}}: True{}
    case _: False{}

# Accepts only the exporter's typed ordering rejection.
def source.order.result(
  result: Result<&1, &1, Backup.Error, Backup.Stream>
) -> Bool:
  match result:
    case Fail{Backup.InvalidOrder{}}: True{}
    case _: False{}

# Rejects a source list that repeats or reverses a byte key.
def source.order.rejected(entries: List<&1, ByteMemTable.Entry>) -> Bool:
  source.order.result(Backup.start(entries))

# Builds duplicate-key and descending-key source lists for export preflight.
def source.order.valid() -> Bool:
  Bool.and(
    source.order.rejected(Con{
      ByteMemTable.Entry{packed(Bytes.from_hex("01")),
        Some{packed(Bytes.from_hex("aa"))}},
      Con{ByteMemTable.Entry{packed(Bytes.from_hex("01")),
        Some{packed(Bytes.from_hex("bb"))}}, Nil{}}}),
    source.order.rejected(Con{
      ByteMemTable.Entry{packed(Bytes.from_hex("02")),
        Some{packed(Bytes.from_hex("aa"))}},
      Con{ByteMemTable.Entry{packed(Bytes.from_hex("01")),
        Some{packed(Bytes.from_hex("bb"))}}, Nil{}}}))

def backup.empty() -> Bytes.Bytes:
  Bytes.concat([
    packed(Bytes.from_hex("4d594c534d424b31000000010000000000000000")),
    packed(Bytes.from_hex("454e44310000000000000000cfc55748aa991c4fa010a2184ba9d5bffaacee95c64f7c510b106752d1f69742"))
  ])

def checksum.rejected(result: Result<&1, &1, Restore.Error, Restore.Decoded>) -> Bool:
  match result:
    case Fail{Restore.ChecksumMismatch{}}: True{}
    case _: False{}

def clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

def slice.bytes(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, result): result

# Removes the final byte from an exchange fixture.
def truncate.measured(pair: Bytes.Bytes & U32) -> Bytes.Bytes:
  match pair:
    case (input, size): slice.bytes(Bytes.slice(input, 0, U32.sub(size, 1)))

# Produces a structurally truncated exchange.
def truncate(input: Bytes.Bytes) -> Bytes.Bytes:
  truncate.measured(Bytes.length(input))

def format.rejected(result: Result<&1, &1, Restore.Error, Restore.Decoded>) -> Bool:
  match result:
    case Fail{Restore.InvalidFormat{}}: True{}
    case _: False{}

def count.rejected(result: Result<&1, &1, Restore.Error, Restore.Decoded>) -> Bool:
  match result:
    case Fail{Restore.CountMismatch{}}: True{}
    case _: False{}

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

def backup.started.stream(stream: Backup.Stream) -> Maybe<&1, Bytes.Bytes>:
  match stream:
    case Backup.Stream{phase, entries, entry_count, +block_count, block_index}:
      backup.collect(Nat.add(U32.to_nat(block_count), 3n),
        Backup.next(Backup.Stream{phase, entries, entry_count, block_count,
          block_index}), Bytes.new(0))

def backup.started(result: Result<&1, &1, Backup.Error, Backup.Stream>) -> Maybe<&1, Bytes.Bytes>:
  match result:
    case Fail{_}: None{}
    case Done{stream}: backup.started.stream(stream)

def backup.one() -> Maybe<&1, Bytes.Bytes>:
  backup.started(Backup.start([
    ByteMemTable.Entry{packed(Bytes.from_hex("61")), Some{packed(Bytes.from_hex("00ff"))}}
  ]))

def backup.many() -> Maybe<&1, Bytes.Bytes>:
  backup.started(Backup.start([
    ByteMemTable.Entry{packed(Bytes.from_hex("00000001")), Some{packed(Bytes.from_hex("00000001"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000002")), Some{packed(Bytes.from_hex("00000002"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000003")), Some{packed(Bytes.from_hex("00000003"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000004")), Some{packed(Bytes.from_hex("00000004"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000005")), Some{packed(Bytes.from_hex("00000005"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000006")), Some{packed(Bytes.from_hex("00000006"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000007")), Some{packed(Bytes.from_hex("00000007"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000008")), Some{packed(Bytes.from_hex("00000008"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000009")), Some{packed(Bytes.from_hex("00000009"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("0000000a")), Some{packed(Bytes.from_hex("0000000a"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("0000000b")), Some{packed(Bytes.from_hex("0000000b"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("0000000c")), Some{packed(Bytes.from_hex("0000000c"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("0000000d")), Some{packed(Bytes.from_hex("0000000d"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("0000000e")), Some{packed(Bytes.from_hex("0000000e"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("0000000f")), Some{packed(Bytes.from_hex("0000000f"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000010")), Some{packed(Bytes.from_hex("00000010"))}},
    ByteMemTable.Entry{packed(Bytes.from_hex("00000011")), Some{packed(Bytes.from_hex("00000011"))}}
  ]))

def many.valid.count(pair: List<&1, ByteMemTable.Entry> & Nat) -> Bool:
  match pair:
    case (_, count): Nat.is_eq(count, 17n)

def many.valid(result: Result<&1, &1, Restore.Error, Restore.Decoded>) -> Bool:
  match result:
    case Done{Restore.Decoded{entries}}:
      many.valid.count(ByteMemTable.count.keep(entries))
    case _: False{}

def one.valid(result: Result<&1, &1, Restore.Error, Restore.Decoded>) -> Bool:
  match result:
    case Done{Restore.Decoded{Con{ByteMemTable.Entry{key, Some{value}}, Nil{}}}}:
      equal(Bytes.eq(key, packed(Bytes.from_hex("61")))) &&
        equal(Bytes.eq(value, packed(Bytes.from_hex("00ff"))))
    case _: False{}

# Stops the fixture at the first failed restore expectation.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

# Checks empty restore and footer-integrity behavior.
def check.result(restored: Result<&1, &1, Restore.Error, Restore.Decoded>) -> IO(Unit):
  match restored:
    case Fail{Restore.InvalidFormat{}}: IO.die(Unit, 1, "restore rejected format")
    case Fail{Restore.ResourceLimit{}}: IO.die(Unit, 1, "restore exceeded a limit")
    case Fail{Restore.InvalidOrder{}}: IO.die(Unit, 1, "restore rejected key order")
    case Fail{Restore.ChecksumMismatch{}}: IO.die(Unit, 1, "restore rejected a checksum")
    case Fail{Restore.CountMismatch{}}: IO.die(Unit, 1, "restore rejected a count")
    case Done{_}:
      do IO<Unit>:
        require(one.valid(restored), "restored bytes differ from source")
        IO.print("BACKUP_RESTORE_PASSED")

def check.nonempty(value: Maybe<&1, Bytes.Bytes>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 1, "nonempty backup encoding should complete")
    case Some{bytes}:
      do IO<Unit>:
        restored : Result<&1, &1, Restore.Error, Restore.Decoded> = Restore.decode(bytes)
        check.result(restored)

def check.multiblock.result(
  restored: Result<&1, &1, Restore.Error, Restore.Decoded>
) -> IO(Unit):
  match restored:
    case Fail{Restore.InvalidFormat{}}: IO.die(Unit, 1, "multi-block restore: format")
    case Fail{Restore.ResourceLimit{}}: IO.die(Unit, 1, "multi-block restore: resource")
    case Fail{Restore.InvalidOrder{}}: IO.die(Unit, 1, "multi-block restore: order")
    case Fail{Restore.ChecksumMismatch{}}: IO.die(Unit, 1, "multi-block restore: checksum")
    case Fail{Restore.CountMismatch{}}: IO.die(Unit, 1, "multi-block restore: count")
    case Done{_}: require(many.valid(restored), "multi-block restore should preserve all records")

def check.multiblock(value: Maybe<&1, Bytes.Bytes>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 1, "multi-block backup encoding should complete")
    case Some{bytes}: check.multiblock.result(Restore.decode(bytes))

def corrupt.second.checksum(pair: Bytes.Bytes & Maybe<&2, U32>, +offset: Nat) -> Bytes.Bytes:
  match pair:
    case (input, None{}): input
    case (input, Some{frame_length}):
      Bytes.set.u32be(input, U32.from_nat(Nat.add(Nat.add(offset, 16n),
        U32.to_nat(frame_length))), 0)

def corrupt.second.offset(pair: Bytes.Bytes & Maybe<&2, U32>) -> Bytes.Bytes:
  match pair:
    case (input, None{}): input
    case (input, Some{frame_length}):
      +offset = Nat.add(68n, U32.to_nat(frame_length))
      corrupt.second.checksum(Bytes.get.u32be(input,
        U32.from_nat(Nat.add(offset, 12n))), offset)

def corrupt.second(input: Bytes.Bytes) -> Bytes.Bytes:
  corrupt.second.offset(Bytes.get.u32be(input, 32))

def check.multiblock.corrupt(value: Maybe<&1, Bytes.Bytes>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 1, "multi-block backup encoding should complete")
    case Some{bytes}:
      do IO<Unit>:
        corrupted : Bytes.Bytes = corrupt.second(bytes)
        result : Result<&1, &1, Restore.Error, Restore.Decoded> = Restore.decode(corrupted)
        require(checksum.rejected(result), "corrupt checksum in a later block should be rejected")

def check.corrupt.copies(copies: Bytes.Bytes & Bytes.Bytes) -> IO(Unit):
  match copies:
    case (for_corruption, for_truncation):
      do IO<Unit>:
        corrupted : Bytes.Bytes = Bytes.set.u32be(for_corruption, 40, 0)
        result : Result<&1, &1, Restore.Error, Restore.Decoded> = Restore.decode(corrupted)
        require(checksum.rejected(result), "corrupt data block checksum should be rejected")
        truncated : Bytes.Bytes = truncate(for_truncation)
        short_result : Result<&1, &1, Restore.Error, Restore.Decoded> = Restore.decode(truncated)
        require(format.rejected(short_result), "truncated backup should be rejected")

def check.corrupt.block(value: Maybe<&1, Bytes.Bytes>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 1, "nonempty backup encoding should complete")
    case Some{bytes}: check.corrupt.copies(clone.split(bytes))

def check.count.mismatch(value: Maybe<&1, Bytes.Bytes>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 1, "nonempty backup encoding should complete")
    case Some{bytes}:
      do IO<Unit>:
        changed : Bytes.Bytes = Bytes.set.u32be(bytes, 12, 2)
        result : Result<&1, &1, Restore.Error, Restore.Decoded> = Restore.decode(changed)
        require(count.rejected(result), "declared entry count mismatch should be classified")

def check.unknown.version(value: Maybe<&1, Bytes.Bytes>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 1, "nonempty backup encoding should complete")
    case Some{bytes}:
      do IO<Unit>:
        changed : Bytes.Bytes = Bytes.set.u32be(bytes, 8, 2)
        result : Result<&1, &1, Restore.Error, Restore.Decoded> = Restore.decode(changed)
        require(format.rejected(result), "unknown backup version should be rejected")

def check.block.index.copies(copies: Bytes.Bytes & Bytes.Bytes) -> IO(Unit):
  match copies:
    case (for_change, _) :
      do IO<Unit>:
        changed : Bytes.Bytes = Bytes.set.u32be(for_change, 24, 1)
        result : Result<&1, &1, Restore.Error, Restore.Decoded> = Restore.decode(changed)
        require(format.rejected(result), "unexpected block index should be rejected")

def check.block.index(value: Maybe<&1, Bytes.Bytes>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit, 1, "nonempty backup encoding should complete")
    case Some{bytes}: check.block.index.copies(clone.split(bytes))

def main() -> IO(Unit):
  do IO<Unit>:
    require(source.order.valid(),
      "backup source should reject duplicate and descending keys")
    valid : Result<&1, &1, Restore.Error, Restore.Decoded> = Restore.decode(backup.empty())
    require(empty.valid(valid), "empty backup should restore")
    corrupted : Bytes.Bytes = Bytes.set.u32be(backup.empty(), 32, 0)
    invalid : Result<&1, &1, Restore.Error, Restore.Decoded> = Restore.decode(corrupted)
    require(checksum.rejected(invalid), "corrupt footer checksum should be rejected")
    check.nonempty(backup.one())
    check.multiblock(backup.many())
    check.multiblock.corrupt(backup.many())
    check.corrupt.block(backup.one())
    check.count.mismatch(backup.one())
    check.unknown.version(backup.one())
    check.block.index(backup.one())
