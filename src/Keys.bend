import Base
import bend-mathlib@0.7.5.0/string.bend as MString
import bend-mathlib@0.7.5.0/bool.bend as MBool
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes

def Bytes.cmp.order(pair: PackedBytes.Bytes & PackedBytes.Bytes & Cmp) -> Cmp:
  match pair:
    case (_, _, order):
      order

def Bytes.cmp.with_inputs(
  left: PackedBytes.Bytes,
  right: PackedBytes.Bytes
) -> PackedBytes.Bytes & PackedBytes.Bytes & Cmp:
  PackedBytes.cmp(left, right)

def Bytes.cmp(left: PackedBytes.Bytes, right: PackedBytes.Bytes) -> Cmp:
  Bytes.cmp.order(Bytes.cmp.with_inputs(left, right))

def Bytes.eq(left: PackedBytes.Bytes, right: PackedBytes.Bytes) -> Bool:
  Cmp.is_eq(Bytes.cmp(left, right))

# Total-order comparison for keys. Base's String.cmp hands the strings back
# beside the verdict ((s1, s2), c); we take reusable copies and unpack via a
# helper (a match cannot scrutinize the computed call directly).
def unpack(pair: (String & String) & Cmp) -> Cmp:
  match pair:
    case ((_, _), c):
      c

# Handle cmp in the key ordering and comparison.
def cmp(+s1: String, +s2: String) -> Cmp:
  unpack(String.cmp(s1, s2))

# Handle eq in the key ordering and comparison.
def eq(+s1: String, +s2: String) -> Bool:
  String.eq(s1, s2)

# Small, coherent views of Cmp used by key-order laws and sorted-run code.
def cmp_is_lt(ord: Cmp) -> Bool:
  Cmp.is_lt(ord)

# Compare whether is eq holds for the key ordering and comparison.
def cmp_is_eq(ord: Cmp) -> Bool:
  Cmp.is_eq(ord)

# Compare whether is gt holds for the key ordering and comparison.
def cmp_is_gt(ord: Cmp) -> Bool:
  Cmp.is_gt(ord)

# Compare whether is le holds for the key ordering and comparison.
def cmp_is_le(ord: Cmp) -> Bool:
  Cmp.is_le(ord)

# Handle lt in the key ordering and comparison.
def lt(+s1: String, +s2: String) -> Bool:
  cmp_is_lt(cmp(s1, s2))

# Handle le in the key ordering and comparison.
def le(+s1: String, +s2: String) -> Bool:
  cmp_is_le(cmp(s1, s2))

# Handle implies in the key ordering and comparison.
def implies(s1: Bool, s2: Bool) -> Bool:
  match s1:
    case False{}:
      True{}
    case True{}:
      s2

# True exactly when one of three arbitrary predicates is true.
def one_hot3(first: Bool, second: Bool, third: Bool) -> Bool:
  match first second third:
    case True{} False{} False{}:
      True{}
    case False{} True{} False{}:
      True{}
    case False{} False{} True{}:
      True{}
    case _ _ _:
      False{}

# Cmp is intrinsically one-hot; this predicate gives K6 a reusable statement.
def cmp_one_hot(+ord: Cmp) -> Bool:
  one_hot3(cmp_is_lt(ord), cmp_is_eq(ord), cmp_is_gt(ord))

# Compare whether one hot proof holds for the key ordering and comparison.
def cmp_one_hot_proof(+ord: Cmp) -> {cmp_one_hot(ord) == True{} : Bool}:
  match ord:
    case LT{}:
      {==}
    case EQ{}:
      {==}
    case GT{}:
      {==}

# `String.eq` is defined by the EQ projection of `String.cmp` (Cmp.is_eq of
# Pair.snd since bend 2.0.33); matching the handed-back comparison pair
# exposes that definitional correspondence.
def cmp_eq_pair(
  pair: (String & String) & Cmp
) -> {cmp_is_eq(unpack(pair)) == Cmp.is_eq(Pair.snd(String & String, Cmp, pair)) : Bool}:
  match pair:
    case ((a, b), c):
      match c:
        case LT{}:
          {==}
        case EQ{}:
          {==}
        case GT{}:
          {==}

# Compare whether eq bridge holds for the key ordering and comparison.
def cmp_eq_bridge(+s1: String, +s2: String) -> {cmp_is_eq(cmp(s1, s2)) == eq(s1, s2) : Bool}:
  %MString.internal_order_cmp(s1, s2) : {cmp_is_eq(cmp(s1, s2)) == Cmp.is_eq(_) : Bool}
  cmp_eq_pair(String.cmp(s1, s2))

# Reflexivity chain for open keys. Every product law about keyed lookup
# rewrites with str_eq_refl; it rests on the layers below, down to bits,
# proved in bend-mathlib's bool and string modules (hash-pinned by version).
# (Proving Base's own primitives is the one exception to the trust-root
# rule: without open-key comparison facts, NO keyed law is provable.)

# Handle s cmp pair refl in the key ordering and comparison.
def s_cmp_pair_refl(+str: String) -> {String.cmp(str, str) == ((str, str), EQ{}) : (String & String) & Cmp}:
  MString.cmp_refl(str)

# Handle str refl in the key ordering and comparison.
def str_refl(+str: String) -> {cmp(str, str) == EQ{} : Cmp}:
  %Equal.sym((String & String) & Cmp, String.cmp(str, str), ((str, str), EQ{}), s_cmp_pair_refl(str)) : {unpack(_) == EQ{} : Cmp}
  {==}

# Handle str eq refl in the key ordering and comparison.
def str_eq_refl(+str: String) -> {eq(str, str) == True{} : Bool}:
  MString.eq_refl(str)
