import Base
import ../../src/scan/ByteRange.bend as ByteRange
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Unwraps fixed hexadecimal bytes for the range fixture.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Fails the fixture when range or prefix semantics differ from byte ordering.
def require(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "byte range or prefix semantics are incorrect")

def main() -> IO(Unit):
  do IO<Unit>:
    require(ByteRange.has_prefix(packed(Bytes.from_hex("610062")),
      packed(Bytes.from_hex("6100"))))
    require(Bool.not(ByteRange.has_prefix(packed(Bytes.from_hex("610062")),
      packed(Bytes.from_hex("6101")))))
    require(ByteRange.in_range(packed(Bytes.from_hex("62")),
      Some{packed(Bytes.from_hex("61"))}, Some{packed(Bytes.from_hex("63"))}))
    require(Bool.not(ByteRange.in_range(packed(Bytes.from_hex("63")),
      Some{packed(Bytes.from_hex("61"))}, Some{packed(Bytes.from_hex("63"))})))
    require(Bool.not(ByteRange.in_range(packed(Bytes.from_hex("62")),
      Some{packed(Bytes.from_hex("62"))}, Some{packed(Bytes.from_hex("62"))})))
    require(ByteRange.in_range(Bytes.new(0), None{}, Some{packed(Bytes.from_hex("00"))}))
    require(ByteRange.in_range(packed(Bytes.from_hex("62")),
      Some{packed(Bytes.from_hex("62"))}, None{}))
    IO.print("byte range and prefix smoke passed")
