import Base
import ./RangeCursor.bend as RangeCursor
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def seek.bounds(
  bounds: RangeCursor.Bounds,
  lower: Maybe<&1, Bytes.Bytes>
) -> RangeCursor.Bounds:
  match bounds:
    case RangeCursor.Bounds{_, upper, prefix}:
      RangeCursor.Bounds{lower, upper, prefix}
