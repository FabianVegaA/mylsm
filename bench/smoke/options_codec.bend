import Base
import ../../src/ResourceOptions.bend as ResourceOptions
import ../../src/coordinator/OptionsCodec.bend as Codec
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Handles packed.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Handles expected.
def expected() -> Bytes.Bytes:
  Bytes.concat([
    packed(Bytes.from_hex("4d4c4f3600000001")),
    packed(Bytes.from_hex("000000400100000001000000010000000000753000007530")),
    packed(Bytes.from_hex("000000400100000000007530")),
    packed(Bytes.from_hex("0000004000001000000000400400000000000040000040000001000004000000"))
  ])

def equal.result(value: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match value:
    case (_, _, equal): equal

def default.options() -> ResourceOptions.Options:
  ResourceOptions.defaults()

def roundtrip.result(result: Codec.Decision) -> Bool:
  match result:
    case Codec.Parsed{options}:
      equal.result(Bytes.eq(Codec.encode(options), expected()))
    case _: False{}

# Handles roundtrip.
def roundtrip() -> Bool:
  roundtrip.result(Codec.decode(Codec.encode(default.options())))

def hex.roundtrip() -> Bool:
  roundtrip.result(Codec.decode.hex(
    Bytes.to_hex(Codec.encode(default.options()))))

def malformed.result(decision: Codec.Decision) -> Bool:
  match decision:
    case Codec.Malformed{}: True{}
    case _: False{}

def malformed.length(length: U32) -> Bool:
  malformed.result(Codec.decode(Bytes.new(length)))

def malformed.walk(remaining: Nat, +length: U32) -> Bool:
  match remaining:
    case 0n: malformed.length(0)
    case 1n+rest:
      malformed.length(length) &&
        malformed.walk(rest, U32.sub(length, 1))

def malformed.lengths() -> Bool:
  malformed.walk(75n, 75) && malformed.length(77)

def malformed.hex.result(decision: Codec.Decision) -> Bool:
  match decision:
    case Codec.Malformed{}: True{}
    case _: False{}

def malformed.hex.canonical(input: String) -> Bool:
  malformed.hex.result(Codec.decode.hex("4D" ++ String.drop(input, 2n)))

def malformed.hex.character(input: String) -> Bool:
  malformed.hex.result(Codec.decode.hex("g" ++ String.drop(input, 1n)))

def malformed.hex() -> Bool:
  malformed.hex.canonical(Bytes.to_hex(Codec.encode(default.options()))) &&
    malformed.hex.character(Bytes.to_hex(Codec.encode(default.options())))

def unknown.version.result(decision: Codec.Decision) -> Bool:
  match decision:
    case Codec.UnsupportedVersion{2}: True{}
    case _: False{}

def unknown.version() -> Bool:
  unknown.version.result(
    Codec.decode(Bytes.set.u32be(Codec.encode(default.options()), 4, 2)))

def invalid.options.result(decision: Codec.Decision) -> Bool:
  match decision:
    case Codec.InvalidOptions{}: True{}
    case _: False{}

def invalid.transport() -> Bool:
  invalid.options.result(Codec.decode(Codec.encode(ResourceOptions.Options{
    ResourceOptions.TransportLimits{0, 16777216, 16777216, 16777216,
      30000, 30000},
    ResourceOptions.QueueLimits{64, 16777216, 30000},
    ResourceOptions.ReaderLimits{64, 4096, 64, 67108864, 64,
      16384, 65536, 67108864}})))

def invalid.queue() -> Bool:
  invalid.options.result(Codec.decode(Codec.encode(ResourceOptions.Options{
    ResourceOptions.TransportLimits{64, 16777216, 16777216, 16777216,
      30000, 30000},
    ResourceOptions.QueueLimits{0, 16777216, 30000},
    ResourceOptions.ReaderLimits{64, 4096, 64, 67108864, 64,
      16384, 65536, 67108864}})))

def invalid.readers() -> Bool:
  invalid.options.result(Codec.decode(Codec.encode(ResourceOptions.Options{
    ResourceOptions.TransportLimits{64, 16777216, 16777216, 16777216,
      30000, 30000},
    ResourceOptions.QueueLimits{64, 16777216, 30000},
    ResourceOptions.ReaderLimits{0, 4096, 64, 67108864, 64,
      16384, 65536, 67108864}})))

# Handles success.
def success(result: Bool) -> IO(Unit):
  match result:
    case True{}: IO.print("OPTIONS_CODEC_PASSED")
    case False{}: IO.die(Unit, 1, "options codec fixture failed")

def main() -> IO(Unit):
  success(roundtrip() && hex.roundtrip() && malformed.lengths() &&
    malformed.hex() && unknown.version() &&
    invalid.transport() && invalid.queue() && invalid.readers())
