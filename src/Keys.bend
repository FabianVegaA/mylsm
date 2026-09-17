import Base

# Total-order comparison for keys. Base's String.cmp hands the strings back
# beside the verdict ((s1, s2), c); we take reusable copies and unpack via a
# helper (a match cannot scrutinize the computed call directly).
def unpack(p: (String & String) & Cmp) -> Cmp:
  match p:
    case ((_, _), c):
      c

def cmp(+a: String, +b: String) -> Cmp:
  unpack(String.cmp(a, b))

def eq(+a: String, +b: String) -> Bool:
  String.eq(a, b)

# Reflexivity chain for open keys. Every product law about keyed lookup
# rewrites with str_eq_refl; it rests on the layers below, down to bits.
# (Proving Base's own primitives is the one exception to the trust-root
# rule: without open-key comparison facts, NO keyed law is provable.)

def bool_refl(+b: Bool) -> {Bool.cmp(b, b) == EQ{} : Cmp}:
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

def word_refl(n: Nat, +w: Word(n)) -> {Word.cmp(n, w, w) == EQ{} : Cmp}:
  match n w:
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

def u32_refl(+x: U32) -> {U32.cmp(x, x) == EQ{} : Cmp}:
  match x:
    case U32{w}:
      %Equal.sym(Cmp, Word.cmp(32n, w, w), EQ{}, word_refl(32n, w)) : {_ == EQ{} : Cmp}
      {==}

def char_refl(+c: Char) -> {Char.cmp(c, c) == ((c, c), EQ{}) : (Char & Char) & Cmp}:
  match c:
    case Chr{x}:
      %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, u32_refl(x)) : {((Chr{x}, Chr{x}), _) == ((Chr{x}, Chr{x}), EQ{}) : (Char & Char) & Cmp}
      {==}

def s_cmp_pair_refl(+s: String) -> {String.cmp(s, s) == ((s, s), EQ{}) : (String & String) & Cmp}:
  match s:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %Equal.sym((Char & Char) & Cmp, Char.cmp(h, h), ((h, h), EQ{}), char_refl(h)) : {String.cmp.fin(t, t, _) == ((SCon{h, t}, SCon{h, t}), EQ{}) : (String & String) & Cmp}
      %Equal.sym((String & String) & Cmp, String.cmp(t, t), ((t, t), EQ{}), s_cmp_pair_refl(t)) : {String.cmp.rec(h, h, _) == ((SCon{h, t}, SCon{h, t}), EQ{}) : (String & String) & Cmp}
      {==}

def str_refl(+s: String) -> {cmp(s, s) == EQ{} : Cmp}:
  %Equal.sym((String & String) & Cmp, String.cmp(s, s), ((s, s), EQ{}), s_cmp_pair_refl(s)) : {unpack(_) == EQ{} : Cmp}
  {==}

def str_eq_refl(+s: String) -> {eq(s, s) == True{} : Bool}:
  match s:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %Equal.sym((Char & Char) & Cmp, Char.cmp(h, h), ((h, h), EQ{}), char_refl(h)) : {String.eq.fin(String.cmp.fin(t, t, _)) == True{} : Bool}
      %Equal.sym((String & String) & Cmp, String.cmp(t, t), ((t, t), EQ{}), s_cmp_pair_refl(t)) : {String.eq.fin(String.cmp.rec(h, h, _)) == True{} : Bool}
      {==}
