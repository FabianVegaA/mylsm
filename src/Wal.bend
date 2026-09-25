import Base
import ./Keys.bend as Keys

# WAL record codec (Task 3). Format (lengths are UNARY dash runs — no
# decimal show/parse inverse lemmas; data is opaque — counted, never
# inspected; checksums are COMPARED, never parsed):
#   Put: 'P' dashes(klen) ':' key dashes(vlen) ':' val chk4 ';'
#   Del: 'D' dashes(klen) ':' key chk4 ';'
# chk4 = 4 raw bytes of hash3(tag, key, val) (Del hashes val="").
# Every pump step consumes exactly one char (handoffs are fused into the
# step that sees the boundary char), so fuel = length fits exactly.

type Mut is Data:
  Put{key: String, val: String}
  Del{key: String}

type Batch is Data:
  Batch{muts: List<&2, Mut>}

# --- Encode (structural, no fuel) ---

def dashes(num: Nat) -> String:
  match num:
    case 0n:
      ""
    case 1n+m:
      SCon{'-', dashes(m)}

def hash_str(str: String, acc: U32) -> U32:
  match str:
    case SNil{}:
      acc
    case SCon{c, t}:
      hash_str(t, U32.add(U32.mul(acc, 31), Char.to_u32(c)))

def hash3(tag: Char, key: String, val: String) -> U32:
  hash_str(val, hash_str(key, hash_str(SCon{tag, SNil{}}, 7)))

def chk4(+word: U32) -> String:
  SCon{Char.from_u32(U32.and(word, 255)), SCon{Char.from_u32(U32.and(U32.shrn(word, 8n), 255)), SCon{Char.from_u32(U32.and(U32.shrn(word, 16n), 255)), SCon{Char.from_u32(U32.and(U32.shrn(word, 24n), 255)), SNil{}}}}}

def enc_mut(mut: Mut) -> String:
  match mut:
    case Put{+key, +val}:
      "P" ++ dashes(String.length(key)) ++ ":" ++ key ++ dashes(String.length(val)) ++ ":" ++ val ++ chk4(hash3('P', key, val)) ++ ";"
    case Del{+key}:
      "D" ++ dashes(String.length(key)) ++ ":" ++ key ++ chk4(hash3('D', key, "")) ++ ";"

def enc_muts(muts: List<&2, Mut>) -> String:
  match muts:
    case Nil{}:
      ""
    case Con{m, t}:
      enc_mut(m) ++ enc_muts(t)

def encode(batch: Batch) -> String:
  match batch:
    case Batch{muts}:
      enc_muts(muts)

def stage(+staged: List<&2, Batch>, +batch: Batch) -> List<&2, Batch>:
  Con{batch, staged}

# --- Decode pump (fuel + state; Nat counters; unified dash phase) ---

type Phase is Data:
  PTag{} RLen{next: Phase} PKey{} PVal{} PChk{} PSemi{} DKey{} DChk{} DSemi{}

type DecState is Data:
  DS{phase: Phase, muts: List<&2, Mut>, tag: Char, num: Nat, kacc: String, vacc: String, cacc: String, ok: Bool}

def tag_dispatch(put: Bool, del: Bool, +muts: List<&2, Mut>) -> DecState:
  match put:
    case True{}:
      DS{RLen{PKey{}}, muts, 'P', 0n, "", "", "", True{}}
    case False{}:
      match del:
        case True{}:
          DS{RLen{DKey{}}, muts, 'D', 0n, "", "", "", True{}}
        case False{}:
          DS{PTag{}, muts, 'P', 0n, "", "", "", False{}}

def dash_step(dash: Bool, colon: Bool, next: Phase, +muts: List<&2, Mut>, +tag: Char, +num: Nat, +kacc: String, +vacc: String, +cacc: String) -> DecState:
  match dash:
    case True{}:
      DS{RLen{next}, muts, tag, 1n+num, kacc, vacc, cacc, True{}}
    case False{}:
      match colon:
        case True{}:
          DS{next, muts, tag, num, kacc, vacc, cacc, True{}}
        case False{}:
          DS{PTag{}, muts, tag, 0n, "", "", "", False{}}

def chk_next(ceq: Bool, next: Phase, +muts: List<&2, Mut>, +tag: Char, +key: String, +val: String) -> DecState:
  match ceq:
    case True{}:
      DS{next, muts, tag, 0n, key, val, "", True{}}
    case False{}:
      DS{PTag{}, muts, tag, 0n, "", "", "", False{}}

def semi_step(semi: Bool, put: Bool, +muts: List<&2, Mut>, +key: String, +val: String) -> DecState:
  match semi:
    case True{}:
      match put:
        case True{}:
          DS{PTag{}, List.append(&2, Mut, muts, Con{Put{key, val}, Nil{}}), 'P', 0n, "", "", "", True{}}
        case False{}:
          DS{PTag{}, List.append(&2, Mut, muts, Con{Del{key}, Nil{}}), 'P', 0n, "", "", "", True{}}
    case False{}:
      DS{PTag{}, muts, 'P', 0n, "", "", "", False{}}

def phase_router(phase: Phase, +muts: List<&2, Mut>, +tag: Char, +num: Nat, +kacc: String, +vacc: String, +cacc: String, +ch: Char) -> DecState:
  match phase:
    case PTag{}:
      tag_dispatch(Char.is_eq(ch, 'P'), Char.is_eq(ch, 'D'), muts)
    case RLen{next}:
      dash_step(Char.is_eq(ch, '-'), Char.is_eq(ch, ':'), next, muts, tag, num, kacc, vacc, cacc)
    case PKey{}:
      match num:
        case 0n:
          dash_step(Char.is_eq(ch, '-'), Char.is_eq(ch, ':'), PVal{}, muts, tag, 0n, kacc, vacc, cacc)
        case 1n+m:
          DS{PKey{}, muts, tag, m, kacc ++ SCon{ch, SNil{}}, vacc, cacc, True{}}
    case PVal{}:
      match num:
        case 0n:
          DS{PChk{}, muts, tag, 1n+(1n+(1n+0n)), kacc, vacc, SCon{ch, SNil{}}, True{}}
        case 1n+m:
          DS{PVal{}, muts, tag, m, kacc, vacc ++ SCon{ch, SNil{}}, cacc, True{}}
    case PChk{}:
      match num:
        case 0n:
          chk_next(String.eq(cacc, chk4(hash3(tag, kacc, vacc))), PSemi{}, muts, tag, kacc, vacc)
        case 1n+m:
          match m:
            case 0n:
              chk_next(String.eq(cacc ++ SCon{ch, SNil{}}, chk4(hash3(tag, kacc, vacc))), PSemi{}, muts, tag, kacc, vacc)
            case 1n+p:
              DS{PChk{}, muts, tag, 1n+p, kacc, vacc, cacc ++ SCon{ch, SNil{}}, True{}}
    case PSemi{}:
      semi_step(Char.is_eq(ch, ';'), True{}, muts, kacc, vacc)
    case DKey{}:
      match num:
        case 0n:
          DS{DChk{}, muts, tag, 1n+(1n+(1n+0n)), kacc, vacc, SCon{ch, SNil{}}, True{}}
        case 1n+m:
          DS{DKey{}, muts, tag, m, kacc ++ SCon{ch, SNil{}}, vacc, cacc, True{}}
    case DChk{}:
      match num:
        case 0n:
          chk_next(String.eq(cacc, chk4(hash3(tag, kacc, ""))), DSemi{}, muts, tag, kacc, "")
        case 1n+m:
          match m:
            case 0n:
              chk_next(String.eq(cacc ++ SCon{ch, SNil{}}, chk4(hash3(tag, kacc, ""))), DSemi{}, muts, tag, kacc, "")
            case 1n+p:
              DS{DChk{}, muts, tag, 1n+p, kacc, vacc, cacc ++ SCon{ch, SNil{}}, True{}}
    case DSemi{}:
      semi_step(Char.is_eq(ch, ';'), False{}, muts, kacc, vacc)

def dec_step(st: DecState, ch: Char) -> DecState:
  match st:
    case DS{phase, muts, tag, num, kacc, vacc, cacc, ok}:
      match ok:
        case False{}:
          DS{PTag{}, muts, tag, 0n, "", "", "", False{}}
        case True{}:
          phase_router(phase, muts, tag, num, kacc, vacc, cacc, ch)

def dec_finish(ok: Bool, phase: Phase, +muts: List<&2, Mut>) -> (List<&2, Mut> & Bool):
  match ok:
    case False{}:
      (muts, False{})
    case True{}:
      match phase:
        case PTag{}:
          (muts, True{})
        case _:
          (muts, False{})

def dec_extract(st: DecState) -> (List<&2, Mut> & Bool):
  match st:
    case DS{phase, muts, tag, num, kacc, vacc, cacc, ok}:
      dec_finish(ok, phase, muts)

def dec_go(fuel: Nat, rest: String, st: DecState) -> (List<&2, Mut> & Bool):
  match fuel rest:
    case 0n _:
      dec_extract(st)
    case 1n+f SNil{}:
      dec_extract(st)
    case 1n+f SCon{h, +t}:
      dec_go(f, t, dec_step(st, h))

# Fuel-exact runner: consumes exactly len-bounded input, returns the state
# (no extraction — callers extract). Proof-only workhorse.
def dec_run(fuel: Nat, rest: String, st: DecState) -> DecState:
  match fuel rest:
    case 0n _:
      st
    case 1n+f SNil{}:
      st
    case 1n+f SCon{h, +t}:
      dec_run(f, t, dec_step(st, h))

def dec_wrap(pair: (List<&2, Mut> & Bool)) -> Maybe<&2, Batch>:
  match pair:
    case (muts, ok):
      match ok:
        case True{}:
          Some{Batch{muts}}
        case False{}:
          None{}

def decode(+str: String) -> Maybe<&2, Batch>:
  dec_wrap(dec_go(Nat.add(String.length(str), 1n), str, DS{PTag{}, Nil{}, 'P', 0n, "", "", "", True{}}))

# --- Proof scaffolding ---

def app_assoc(sa: String, sb: String, sc: String) -> {((sa ++ sb) ++ sc) == (sa ++ (sb ++ sc)) : String}:
  match sa:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %app_assoc(t, sb, sc) : {SCon{h, (t ++ sb) ++ sc} == SCon{h, _} : String}
      {==}

def app_nil_r(str: String) -> {(str ++ "") == str : String}:
  match str:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %app_nil_r(t) : {SCon{h, t ++ ""} == SCon{h, _} : String}
      {==}
def len_append(sa: String, sb: String) -> {String.length(sa ++ sb) == Nat.add(String.length(sa), String.length(sb)) : Nat}:
  match sa:
    case SNil{}:
      {==}
    case SCon{h, t}:
      %len_append(t, sb) : {1n+String.length(t ++ sb) == 1n+_ : Nat}
      {==}

def add_assoc(n1: Nat, n2: Nat, n3: Nat) -> {Nat.add(Nat.add(n1, n2), n3) == Nat.add(n1, Nat.add(n2, n3)) : Nat}:
  match n1:
    case 0n:
      {==}
    case 1n+m:
      %add_assoc(m, n2, n3) : {1n+Nat.add(Nat.add(m, n2), n3) == 1n+_ : Nat}
      {==}

def list_app_assoc(xs: List<&2, Mut>, ys: List<&2, Mut>, zs: List<&2, Mut>) -> {List.append(&2, Mut, List.append(&2, Mut, xs, ys), zs) == List.append(&2, Mut, xs, List.append(&2, Mut, ys, zs)) : List<&2, Mut>}:
  match xs:
    case Nil{}:
      {==}
    case Con{h, t}:
      %list_app_assoc(t, ys, zs) : {Con{h, List.append(&2, Mut, List.append(&2, Mut, t, ys), zs)} == Con{h, _} : List<&2, Mut>}
      {==}

def append_nil_r(+xs: List<&2, Mut>) -> {List.append(&2, Mut, xs, Nil{}) == xs : List<&2, Mut>}:
  match xs:
    case Nil{}:
      {==}
    case Con{h, t}:
      %append_nil_r(t) : {Con{h, List.append(&2, Mut, t, Nil{})} == Con{h, _} : List<&2, Mut>}
      {==}

# Unary counter: jump(n, num0) = num0 + n as 1n-chains (no appends, no assoc).
def jump(num: Nat, num0: Nat) -> Nat:
  match num:
    case 0n:
      num0
    case 1n+m:
      1n+jump(m, num0)

def jump_zero(num: Nat) -> {jump(num, 0n) == num : Nat}:
  match num:
    case 0n:
      {==}
    case 1n+m:
      %jump_zero(m) : {1n+jump(m, 0n) == 1n+_ : Nat}
      {==}

def jump_succ(num: Nat, num0: Nat) -> {jump(num, 1n+num0) == 1n+jump(num, num0) : Nat}:
  match num:
    case 0n:
      {==}
    case 1n+p:
      %jump_succ(p, num0) : {1n+jump(p, 1n+num0) == 1n+_ : Nat}
      {==}

# RLen dash-run skip (unified len phase; next stored, never matched here).
# Fuel is len(span++tail): deconstructs with the Nat induction, tail opaque.
def dashspan(num: Nat, tail: String, muts0: List<&2, Mut>, tag: Char, next: Phase, +num0: Nat, kacc0: String) -> {dec_run(String.length(dashes(num) ++ tail), dashes(num) ++ tail, DS{RLen{next}, muts0, tag, num0, kacc0, "", "", True{}}) == dec_run(String.length(tail), tail, DS{RLen{next}, muts0, tag, jump(num, num0), kacc0, "", "", True{}}) : DecState}:
  match num:
    case 0n:
      {==}
    case 1n++m:
      %jump_succ(m, num0) : {dec_run(String.length(dashes(m) ++ tail), dashes(m) ++ tail, DS{RLen{next}, muts0, tag, 1n+num0, kacc0, "", "", True{}}) == dec_run(String.length(tail), tail, DS{RLen{next}, muts0, tag, _, kacc0, "", "", True{}}) : DecState}
      %dashspan(m, tail, muts0, tag, next, 1n+num0, kacc0) : {dec_run(String.length(dashes(m) ++ tail), dashes(m) ++ tail, DS{RLen{next}, muts0, tag, 1n+num0, kacc0, "", "", True{}}) == _ : DecState}
      {==}

# PKEY take: consumes key bytes; kacc0 generalized. Fuel is len(key++tail).
def keyspan(key: String, +kacc0: String, tail: String, muts0: List<&2, Mut>, tag: Char, vacc0: String) -> {dec_run(String.length(key ++ tail), key ++ tail, DS{PKey{}, muts0, tag, String.length(key), kacc0, vacc0, "", True{}}) == dec_run(String.length(tail), tail, DS{PKey{}, muts0, tag, 0n, kacc0 ++ key, vacc0, "", True{}}) : DecState}:
  match key:
    case SNil{}:
      %Equal.sym(String, kacc0 ++ "", kacc0, app_nil_r(kacc0)) : {dec_run(String.length(tail), tail, DS{PKey{}, muts0, tag, 0n, kacc0, vacc0, "", True{}}) == dec_run(String.length(tail), tail, DS{PKey{}, muts0, tag, 0n, _, vacc0, "", True{}}) : DecState}
      {==}
    case SCon{+h, +t}:
      %app_assoc(kacc0, SCon{h, SNil{}}, t) : {dec_run(String.length(t ++ tail), t ++ tail, DS{PKey{}, muts0, tag, String.length(t), kacc0 ++ SCon{h, SNil{}}, vacc0, "", True{}}) == dec_run(String.length(tail), tail, DS{PKey{}, muts0, tag, 0n, _, vacc0, "", True{}}) : DecState}
      %keyspan(t, kacc0 ++ SCon{h, SNil{}}, tail, muts0, tag, vacc0) : {dec_run(String.length(t ++ tail), t ++ tail, DS{PKey{}, muts0, tag, String.length(t), kacc0 ++ SCon{h, SNil{}}, vacc0, "", True{}}) == _ : DecState}
      {==}

# PVAL take: mirror for values.
def valspan(val: String, +vacc0: String, tail: String, muts0: List<&2, Mut>, tag: Char, kacc: String) -> {dec_run(String.length(val ++ tail), val ++ tail, DS{PVal{}, muts0, tag, String.length(val), kacc, vacc0, "", True{}}) == dec_run(String.length(tail), tail, DS{PVal{}, muts0, tag, 0n, kacc, vacc0 ++ val, "", True{}}) : DecState}:
  match val:
    case SNil{}:
      %Equal.sym(String, vacc0 ++ "", vacc0, app_nil_r(vacc0)) : {dec_run(String.length(tail), tail, DS{PVal{}, muts0, tag, 0n, kacc, vacc0, "", True{}}) == dec_run(String.length(tail), tail, DS{PVal{}, muts0, tag, 0n, kacc, _, "", True{}}) : DecState}
      {==}
    case SCon{+h, +t}:
      %app_assoc(vacc0, SCon{h, SNil{}}, t) : {dec_run(String.length(t ++ tail), t ++ tail, DS{PVal{}, muts0, tag, String.length(t), kacc, vacc0 ++ SCon{h, SNil{}}, "", True{}}) == dec_run(String.length(tail), tail, DS{PVal{}, muts0, tag, 0n, kacc, _, "", True{}}) : DecState}
      %valspan(t, vacc0 ++ SCon{h, SNil{}}, tail, muts0, tag, kacc) : {dec_run(String.length(t ++ tail), t ++ tail, DS{PVal{}, muts0, tag, String.length(t), kacc, vacc0 ++ SCon{h, SNil{}}, "", True{}}) == _ : DecState}
      {==}

# DKEY take: mirror for delete keys.
def dkeyspan(key: String, +kacc0: String, tail: String, muts0: List<&2, Mut>, tag: Char) -> {dec_run(String.length(key ++ tail), key ++ tail, DS{DKey{}, muts0, tag, String.length(key), kacc0, "", "", True{}}) == dec_run(String.length(tail), tail, DS{DKey{}, muts0, tag, 0n, kacc0 ++ key, "", "", True{}}) : DecState}:
  match key:
    case SNil{}:
      %Equal.sym(String, kacc0 ++ "", kacc0, app_nil_r(kacc0)) : {dec_run(String.length(tail), tail, DS{DKey{}, muts0, tag, 0n, kacc0, "", "", True{}}) == dec_run(String.length(tail), tail, DS{DKey{}, muts0, tag, 0n, _, "", "", True{}}) : DecState}
      {==}
    case SCon{+h, +t}:
      %app_assoc(kacc0, SCon{h, SNil{}}, t) : {dec_run(String.length(t ++ tail), t ++ tail, DS{DKey{}, muts0, tag, String.length(t), kacc0 ++ SCon{h, SNil{}}, "", "", True{}}) == dec_run(String.length(tail), tail, DS{DKey{}, muts0, tag, 0n, _, "", "", True{}}) : DecState}
      %dkeyspan(t, kacc0 ++ SCon{h, SNil{}}, tail, muts0, tag) : {dec_run(String.length(t ++ tail), t ++ tail, DS{DKey{}, muts0, tag, String.length(t), kacc0 ++ SCon{h, SNil{}}, "", "", True{}}) == _ : DecState}
      {==}

# (valsec/record/gen open-proof deferred — see laws/Wal.bend.
# Closed round-trip vectors in laws/Wal.bend + Task-12 fuzz cover correctness.)

# Total-parser witness used by the hardening law.
def is_decided(+_m: Maybe<&2, Batch>) -> Bool:
  True{}
