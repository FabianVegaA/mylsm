import Base
import ../Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Reifies two independently owned copies of a byte buffer.
def clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

# Clones a byte buffer when range checks need both bounds.
def clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

# Returns whether a key satisfies an optional inclusive lower bound.
def lower.result(comparison: Bytes.Bytes & Bytes.Bytes & Cmp) -> Bool:
  match comparison:
    case (_, _, LT{}):
      False{}
    case _:
      True{}

# Checks an optional lower bound using the canonical byte comparator.
def lower(key: Bytes.Bytes, bound: Maybe<&1, Bytes.Bytes>) -> Bool:
  match bound:
    case None{}:
      True{}
    case Some{value}:
      lower.result(Keys.Bytes.cmp.with_inputs(key, value))

# Returns whether a key sorts strictly below an optional upper bound.
def upper.result(comparison: Bytes.Bytes & Bytes.Bytes & Cmp) -> Bool:
  match comparison:
    case (_, _, LT{}):
      True{}
    case _:
      False{}

# Checks an optional exclusive upper bound using byte order.
def upper(key: Bytes.Bytes, bound: Maybe<&1, Bytes.Bytes>) -> Bool:
  match bound:
    case None{}:
      True{}
    case Some{value}:
      upper.result(Keys.Bytes.cmp.with_inputs(key, value))

def at_or_after_upper.result(comparison: Bytes.Bytes & Bytes.Bytes & Cmp) -> Bool:
  match comparison:
    case (_, _, LT{}): False{}
    case _: True{}

# Detects the first ordered key that cannot belong to a half-open range.
def at_or_after_upper(key: Bytes.Bytes, bound: Maybe<&1, Bytes.Bytes>) -> Bool:
  match bound:
    case None{}: False{}
    case Some{value}:
      at_or_after_upper.result(Keys.Bytes.cmp.with_inputs(key, value))

# Combines the lower and upper checks for a half-open range.
def in_range.checked(lower_ok: Bool, upper_ok: Bool) -> Bool:
  match lower_ok:
    case True{}:
      upper_ok
    case False{}:
      False{}

# Checks a byte key against optional [lower, upper) bounds.
def in_range.copies(
  copies: Bytes.Bytes & Bytes.Bytes,
  lower_bound: Maybe<&1, Bytes.Bytes>,
  upper_bound: Maybe<&1, Bytes.Bytes>
) -> Bool:
  match copies:
    case (lower_key, upper_key):
      in_range.checked(lower(lower_key, lower_bound), upper(upper_key, upper_bound))

# Checks a byte key against optional [lower, upper) bounds.
def in_range(
  key: Bytes.Bytes,
  lower_bound: Maybe<&1, Bytes.Bytes>,
  upper_bound: Maybe<&1, Bytes.Bytes>
) -> Bool:
  in_range.copies(clone.split(key), lower_bound, upper_bound)

# Returns the equality component while consuming both preserved buffers.
def prefix.equal(result: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match result:
    case (_, _, equal):
      equal

# Compares a bounded key prefix with the requested bytes.
def prefix.slice.result(
  prefix: Bytes.Bytes,
  pair: Bytes.Bytes & Bytes.Bytes
) -> Bool:
  match pair:
    case (_, sliced):
      prefix.equal(Bytes.eq(sliced, prefix))

# Slices exactly the requested prefix length and compares the resulting bytes.
def prefix.slice(key: Bytes.Bytes, prefix: Bytes.Bytes, +prefix_len: U32) -> Bool:
  prefix.slice.result(prefix, Bytes.slice(key, 0, prefix_len))

# Rejects prefixes longer than the key before slicing.
def prefix.length.checked(
  key: Bytes.Bytes,
  prefix: Bytes.Bytes,
  +prefix_len: U32,
  +key_len: U32
) -> Bool:
  Bool.pick(Bool, U32.is_le(prefix_len, key_len),
    prefix.slice(key, prefix, prefix_len), False{})

# Unpacks measured key and prefix lengths before comparison.
def prefix.lengths(
  key_pair: Bytes.Bytes & U32,
  prefix_pair: Bytes.Bytes & U32
) -> Bool:
  match key_pair:
    case (key, key_len):
      match prefix_pair:
        case (prefix, prefix_len):
          prefix.length.checked(key, prefix, prefix_len, key_len)

# Checks whether a byte key begins with the exact byte prefix.
def has_prefix(key: Bytes.Bytes, prefix: Bytes.Bytes) -> Bool:
  prefix.lengths(Bytes.length(key), Bytes.length(prefix))
