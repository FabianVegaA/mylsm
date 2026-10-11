import Base
import ../../src/Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Fails the fixture at the first violated byte-order expectation.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

# Converts the vector decoder result into an owned byte buffer.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Tests strict ordering under the canonical key comparator.
def less(left: Bytes.Bytes, right: Bytes.Bytes) -> Bool:
  Cmp.is_lt(Keys.Bytes.cmp(left, right))

# Tests equality under the canonical key comparator.
def same(left: Bytes.Bytes, right: Bytes.Bytes) -> Bool:
  Cmp.is_eq(Keys.Bytes.cmp(left, right))

def main() -> IO(Unit):
  do IO<Unit>:
    empty : Bytes.Bytes = packed(Bytes.from_hex(""))
    zero_zero : Bytes.Bytes = packed(Bytes.from_hex("0000"))
    seven_f : Bytes.Bytes = packed(Bytes.from_hex("7f"))
    eight_zero : Bytes.Bytes = packed(Bytes.from_hex("80"))
    with_zero : Bytes.Bytes = packed(Bytes.from_hex("610062"))
    require(less(empty, packed(Bytes.from_hex("00"))), "empty key must sort before zero byte")
    require(less(packed(Bytes.from_hex("00")), zero_zero), "a byte prefix must sort before its extension")
    require(less(seven_f, eight_zero), "bytes must compare as unsigned values")
    require(same(with_zero, packed(Bytes.from_hex("610062"))), "embedded zero must be preserved")
    IO.print("0.6 byte-order vectors passed")
