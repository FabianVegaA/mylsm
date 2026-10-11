import Base

# Preserves the first cleanup failure and otherwise returns the final result.
def combine(
  a,
  -E: Kind(a),
  first: Result<a, &1, E, Unit>,
  second: Result<a, &1, E, Unit>
) -> Result<a, &1, E, Unit>:
  match first:
    case Fail{error}: Fail{error}
    case Done{Unit{}}: second
