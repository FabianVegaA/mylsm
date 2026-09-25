import Base

# Total-order comparison for keys. Base's String.cmp hands the strings back
# beside the verdict ((s1, s2), c); we take reusable copies and unpack via a
# helper (a match cannot scrutinize the computed call directly).
def unpack(pair: (String & String) & Cmp) -> Cmp:
  match pair:
    case ((_, _), c):
      c

def cmp(+s1: String, +s2: String) -> Cmp:
  unpack(String.cmp(s1, s2))

def eq(+s1: String, +s2: String) -> Bool:
  String.eq(s1, s2)

# Small, coherent views of Cmp used by key-order laws and sorted-run code.
def cmp_is_lt(ord: Cmp) -> Bool:
  Cmp.is_lt(ord)

def cmp_is_eq(ord: Cmp) -> Bool:
  Cmp.is_eq(ord)

def cmp_is_gt(ord: Cmp) -> Bool:
  Cmp.is_gt(ord)

def cmp_is_le(ord: Cmp) -> Bool:
  Cmp.is_le(ord)

def lt(+s1: String, +s2: String) -> Bool:
  cmp_is_lt(cmp(s1, s2))

def le(+s1: String, +s2: String) -> Bool:
  cmp_is_le(cmp(s1, s2))

def cmp_reverse(ord: Cmp) -> Cmp:
  match ord:
    case LT{}:
      GT{}
    case EQ{}:
      EQ{}
    case GT{}:
      LT{}

def implies(s1: Bool, s2: Bool) -> Bool:
  match s1:
    case False{}:
      True{}
    case True{}:
      s2

def iff(+s1: Bool, +s2: Bool) -> Bool:
  Bool.and(implies(s1, s2), implies(s2, s1))

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

def cmp_one_hot_proof(+ord: Cmp) -> {cmp_one_hot(ord) == True{} : Bool}:
  match ord:
    case LT{}:
      {==}
    case EQ{}:
      {==}
    case GT{}:
      {==}

# `String.eq` is defined by the EQ projection of `String.cmp`; matching the
# handed-back comparison pair exposes that definitional correspondence.
def cmp_eq_pair(pair: (String & String) & Cmp) -> {cmp_is_eq(unpack(pair)) == String.eq.fin(pair) : Bool}:
  match pair:
    case ((a, b), c):
      match c:
        case LT{}:
          {==}
        case EQ{}:
          {==}
        case GT{}:
          {==}

def cmp_eq_bridge(+s1: String, +s2: String) -> {cmp_is_eq(cmp(s1, s2)) == eq(s1, s2) : Bool}:
  cmp_eq_pair(String.cmp(s1, s2))

# Reflexivity chain for open keys. Every product law about keyed lookup
# rewrites with str_eq_refl; it rests on the layers below, down to bits.
# (Proving Base's own primitives is the one exception to the trust-root
# rule: without open-key comparison facts, NO keyed law is provable.)

def bool_refl(+flag: Bool) -> {Bool.cmp(flag, flag) == EQ{} : Cmp}:
  match flag:
    case False{}:
      {==}
    case True{}:
      {==}

def word_refl(width: Nat, +word: Word(width)) -> {Word.cmp(width, word, word) == EQ{} : Cmp}:
  match width word:
    case 0n WNil{}:
      {==}
    case 1n+p WCon{ab, at}:
      match ab:
        case False{}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, word_refl(p, at)) : {Word.cmp.fin(False{}, False{}, _) == EQ{} : Cmp}
          {==}
        case True{}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, word_refl(p, at)) : {Word.cmp.fin(True{}, True{}, _) == EQ{} : Cmp}
          {==}

def u32_refl(+val: U32) -> {U32.cmp(val, val) == EQ{} : Cmp}:
  match val:
    case U32{w}:
      %Equal.sym(Cmp, Word.cmp(32n, w, w), EQ{}, word_refl(32n, w)) : {_ == EQ{} : Cmp}
      {==}

def char_refl(+ch: Char) -> {Char.cmp(ch, ch) == ((ch, ch), EQ{}) : (Char & Char) & Cmp}:
  match ch:
    case Chr{x}:
      %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, u32_refl(x)) : {((Chr{x}, Chr{x}), _) == ((Chr{x}, Chr{x}), EQ{}) : (Char & Char) & Cmp}
      {==}

def s_cmp_pair_refl(+str: String) -> {String.cmp(str, str) == ((str, str), EQ{}) : (String & String) & Cmp}:
  match str:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %Equal.sym((Char & Char) & Cmp, Char.cmp(h, h), ((h, h), EQ{}), char_refl(h)) : {String.cmp.fin(t, t, _) == ((SCon{h, t}, SCon{h, t}), EQ{}) : (String & String) & Cmp}
      %Equal.sym((String & String) & Cmp, String.cmp(t, t), ((t, t), EQ{}), s_cmp_pair_refl(t)) : {String.cmp.rec(h, h, _) == ((SCon{h, t}, SCon{h, t}), EQ{}) : (String & String) & Cmp}
      {==}

def str_refl(+str: String) -> {cmp(str, str) == EQ{} : Cmp}:
  %Equal.sym((String & String) & Cmp, String.cmp(str, str), ((str, str), EQ{}), s_cmp_pair_refl(str)) : {unpack(_) == EQ{} : Cmp}
  {==}

def str_eq_refl(+str: String) -> {eq(str, str) == True{} : Bool}:
  match str:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %Equal.sym((Char & Char) & Cmp, Char.cmp(h, h), ((h, h), EQ{}), char_refl(h)) : {String.eq.fin(String.cmp.fin(t, t, _)) == True{} : Bool}
      %Equal.sym((String & String) & Cmp, String.cmp(t, t), ((t, t), EQ{}), s_cmp_pair_refl(t)) : {String.eq.fin(String.cmp.rec(h, h, _)) == True{} : Bool}
      {==}
