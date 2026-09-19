import Base
import ../src/Keys.bend as Keys

# Trust root (read before the laws below): Bend Base primitives —
# arithmetic, comparison, String/Char ops — are the trusted kernel. They
# ship precompiled with Bend and are NOT re-proven here: reproving
# Word.cmp reflexivity from bit axioms would burn the project proving the
# compiler's own prelude. Instead, selected primitive behavior is pinned by
# closed normalization fixtures and exercised empirically by the fuzz harness.
# The laws below deliberately distinguish quantified general theorems from
# closed regression fixtures. Closed fixtures provide executable evidence for
# concrete cases; they are not complete proofs for arbitrary inputs.

# LAW: comparison unpacking is wired correctly (reflexive case)
law cmp_refl_a:
  {Keys.cmp("a", "a") == EQ{} : Cmp}

# LAW: comparison unpacking is wired correctly (ordered case)
law cmp_order_ab:
  {Keys.cmp("a", "b") == LT{} : Cmp}

law key_cmp_refl:
  for +key: String
  {Keys.cmp(key, key) == EQ{} : Cmp}

law key_cmp_eq_bridge:
  for +a: String
  for +b: String
  {Keys.cmp_is_eq(Keys.cmp(a, b)) == Keys.eq(a, b) : Bool}

law key_cmp_trichotomy:
  for +a: String
  for +b: String
  {Keys.cmp_one_hot(Keys.cmp(a, b)) == True{} : Bool}
