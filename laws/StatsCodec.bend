import Base
import ../src/coordinator/StatsCodec.bend as StatsCodec
import ../src/StorageBytes.bend as StorageBytes
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.text.result(
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> Bytes.Bytes:
  match result:
    case Done{bytes}: bytes
    case Fail{_}: Bytes.new(0)

def bytes.text(text: String) -> Bytes.Bytes:
  bytes.text.result(StorageBytes.from_string(text))

def malformed.result(decision: StatsCodec.Decision) -> Bool:
  match decision:
    case StatsCodec.Malformed{}: True{}
    case _: False{}

# Reports whether a text fixture is rejected by the statistics parser.
def malformed(text: String) -> Bool:
  malformed.result(StatsCodec.parse(bytes.text(text)))

# Parses decimal entry and payload counts from a valid owner stats frame.
law parses_stats_counts:
  {StatsCodec.parse(bytes.text("12:34")) ==
    StatsCodec.Parsed{StatsCodec.ByteStats{12n, 34n}} : StatsCodec.Decision}

# Accepts zero counts without treating either field as missing.
law parses_zero_stats_counts:
  {StatsCodec.parse(bytes.text("0:0")) ==
    StatsCodec.Parsed{StatsCodec.ByteStats{0n, 0n}} : StatsCodec.Decision}

# Rejects non-decimal and incomplete stats payloads.
law rejects_malformed_stats_text:
  {(malformed("1:x") && malformed("1:") && malformed("1:2:3")) ==
    True{} : Bool}
