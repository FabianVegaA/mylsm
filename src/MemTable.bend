import Base
import ./Keys.bend as Keys

# MemTable: newest-first prepend log (NOT sorted — sorting happens once at
# flush). Rationale: put/del are O(1) with ZERO comparisons on the write
# path, the fastest possible shape; reads scan newest-first (fine at the
# 4096-entry cap); the scan state machine below is provable with only the
# Keys.str_eq_refl rewrite (no ordering lemmas needed until flush sorts).

type Entry is Data:
  Entry{key: String, val: Maybe<&2, String>}

type MemTable is Data:
  MT{entries: List<&2, Entry>}

def empty() -> MemTable:
  MT{Nil{}}

def put(tab: MemTable, key: String, val: String) -> MemTable:
  match tab:
    case MT{entries}:
      MT{Con{Entry{key, Some{val}}, entries}}

def del(tab: MemTable, key: String) -> MemTable:
  match tab:
    case MT{entries}:
      MT{Con{Entry{key, None{}}, entries}}

def count(tab: MemTable) -> Nat:
  match tab:
    case MT{entries}:
      List.length(&2, Entry, entries)

# Scan state machine (Base List.merge pattern): the driver matches fuel +
# structural state only; the leaf folds one entry (done-flag freezes the
# answer — including tombstone None, which hides older versions).
def scan_step(done: Bool, eq: Bool, hv: Maybe<&2, String>, ans: Maybe<&2, String>) -> (Bool & Maybe<&2, String>):
  match done:
    case True{}:
      (True{}, ans)
    case False{}:
      match eq:
        case True{}:
          (True{}, hv)
        case False{}:
          (False{}, ans)

def scan_go(fuel: Nat, +key: String, st: (Bool & Maybe<&2, String>), entries: List<&2, Entry>) -> Maybe<&2, String>:
  match fuel:
    case 0n:
      (done, ans) = st
      ans
    case 1n+f:
      (done, ans) = st
      match entries:
        case Nil{}:
          ans
        case Con{Entry{ekey, val}, t}:
          scan_go(f, key, scan_step(done, Keys.eq(ekey, key), val, ans), t)

def get(tab: MemTable, +key: String) -> Maybe<&2, String>:
  match tab:
    case MT{+entries}:
      scan_go(List.length(&2, Entry, entries), key, (False{}, None{}), entries)

# Hit-detecting scan: outer None = miss (keep searching older sources),
# Some{val} = hit (val may be the None{} tombstone — stop, it shadows).
def scan_hit_step(done: Bool, eq: Bool, hv: Maybe<&2, String>, ans: Maybe<&2, Maybe<&2, String>>) -> (Bool & Maybe<&2, Maybe<&2, String>>):
  match done:
    case True{}:
      (True{}, ans)
    case False{}:
      match eq:
        case True{}:
          (True{}, Some{hv})
        case False{}:
          (False{}, ans)

def scan_hit(fuel: Nat, +key: String, st: (Bool & Maybe<&2, Maybe<&2, String>>), entries: List<&2, Entry>) -> Maybe<&2, Maybe<&2, String>>:
  match fuel:
    case 0n:
      (done, ans) = st
      ans
    case 1n+f:
      (done, ans) = st
      match entries:
        case Nil{}:
          ans
        case Con{Entry{ekey, val}, t}:
          scan_hit(f, key, scan_hit_step(done, Keys.eq(ekey, key), val, ans), t)

def get_hit(tab: MemTable, +key: String) -> Maybe<&2, Maybe<&2, String>>:
  match tab:
    case MT{+entries}:
      scan_hit(List.length(&2, Entry, entries), key, (False{}, None{}), entries)

# Lemma: a frozen (done) scan always answers ans.
def frozen_lemma(fuel: Nat, key: String, ans: Maybe<&2, String>, entries: List<&2, Entry>) -> {scan_go(fuel, key, (True{}, ans), entries) == ans : Maybe<&2, String>}:
  match fuel:
    case 0n:
      {==}
    case 1n+f:
      match entries:
        case Nil{}:
          {==}
        case Con{Entry{ekey, val}, t}:
          %frozen_lemma(f, key, ans, t) : {scan_go(f, key, (True{}, ans), t) == _ : Maybe<&2, String>}
          {==}

# Lemma: reading a freshly-put key answers its value.
def ryw_core(
  +entries: List<&2, Entry>,
  +key: String,
  val: String,
) -> {scan_go(List.length(&2, Entry, Con{Entry{key, Some{val}}, entries}), key, (False{}, None{}), Con{Entry{key, Some{val}}, entries}) == Some{val} : Maybe<&2, String>}:
  %Equal.sym(Bool, Keys.eq(key, key), True{}, Keys.str_eq_refl(key)) : {scan_go(List.length(&2, Entry, entries), key, scan_step(False{}, _, Some{val}, None{}), entries) == Some{val} : Maybe<&2, String>}
  %frozen_lemma(List.length(&2, Entry, entries), key, Some{val}, entries) : {scan_go(List.length(&2, Entry, entries), key, (True{}, Some{val}), entries) == _ : Maybe<&2, String>}
  {==}

def ryw_bridge(tab: MemTable, +key: String, +val: String) -> {get(put(tab, key, val), key) == Some{val} : Maybe<&2, String>}:
  match tab:
    case MT{entries}:
      ryw_core(entries, key, val)

# Lemma: reading a freshly-deleted key answers None (tombstone freezes).
def del_core(
  +entries: List<&2, Entry>,
  +key: String,
) -> {scan_go(List.length(&2, Entry, Con{Entry{key, None{}}, entries}), key, (False{}, None{}), Con{Entry{key, None{}}, entries}) == None{} : Maybe<&2, String>}:
  %Equal.sym(Bool, Keys.eq(key, key), True{}, Keys.str_eq_refl(key)) : {scan_go(List.length(&2, Entry, entries), key, scan_step(False{}, _, None{}, None{}), entries) == None{} : Maybe<&2, String>}
  %frozen_lemma(List.length(&2, Entry, entries), key, None{}, entries) : {scan_go(List.length(&2, Entry, entries), key, (True{}, None{}), entries) == _ : Maybe<&2, String>}
  {==}

def del_bridge(tab: MemTable, +key: String, val: String) -> {get(del(put(tab, key, val), key), key) == None{} : Maybe<&2, String>}:
  match tab:
    case MT{entries}:
      del_core(Con{Entry{key, Some{val}}, entries}, key)

# Lemma: a frozen hit-scan always answers ans.
def frozen_hit_lemma(fuel: Nat, key: String, ans: Maybe<&2, Maybe<&2, String>>, entries: List<&2, Entry>) -> {scan_hit(fuel, key, (True{}, ans), entries) == ans : Maybe<&2, Maybe<&2, String>>}:
  match fuel:
    case 0n:
      {==}
    case 1n+f:
      match entries:
        case Nil{}:
          {==}
        case Con{Entry{ekey, val}, t}:
          %frozen_hit_lemma(f, key, ans, t) : {scan_hit(f, key, (True{}, ans), t) == _ : Maybe<&2, Maybe<&2, String>>}
          {==}

# Lemma: hit-reading a freshly-put key answers a value hit.
def ryw_hit_core(
  +entries: List<&2, Entry>,
  +key: String,
  val: String,
) -> {scan_hit(List.length(&2, Entry, Con{Entry{key, Some{val}}, entries}), key, (False{}, None{}), Con{Entry{key, Some{val}}, entries}) == Some{Some{val}} : Maybe<&2, Maybe<&2, String>>}:
  %Equal.sym(Bool, Keys.eq(key, key), True{}, Keys.str_eq_refl(key)) : {scan_hit(List.length(&2, Entry, entries), key, scan_hit_step(False{}, _, Some{val}, None{}), entries) == Some{Some{val}} : Maybe<&2, Maybe<&2, String>>}
  %frozen_hit_lemma(List.length(&2, Entry, entries), key, Some{Some{val}}, entries) : {scan_hit(List.length(&2, Entry, entries), key, (True{}, Some{Some{val}}), entries) == _ : Maybe<&2, Maybe<&2, String>>}
  {==}

def hit_ryw_bridge(tab: MemTable, +key: String, +val: String) -> {get_hit(put(tab, key, val), key) == Some{Some{val}} : Maybe<&2, Maybe<&2, String>>}:
  match tab:
    case MT{entries}:
      ryw_hit_core(entries, key, val)

# Lemma: hit-reading a freshly-deleted key answers a tombstone hit.
def del_hit_core(
  +entries: List<&2, Entry>,
  +key: String,
) -> {scan_hit(List.length(&2, Entry, Con{Entry{key, None{}}, entries}), key, (False{}, None{}), Con{Entry{key, None{}}, entries}) == Some{None{}} : Maybe<&2, Maybe<&2, String>>}:
  %Equal.sym(Bool, Keys.eq(key, key), True{}, Keys.str_eq_refl(key)) : {scan_hit(List.length(&2, Entry, entries), key, scan_hit_step(False{}, _, None{}, None{}), entries) == Some{None{}} : Maybe<&2, Maybe<&2, String>>}
  %frozen_hit_lemma(List.length(&2, Entry, entries), key, Some{None{}}, entries) : {scan_hit(List.length(&2, Entry, entries), key, (True{}, Some{None{}}), entries) == _ : Maybe<&2, Maybe<&2, String>>}
  {==}

def hit_del_bridge(tab: MemTable, +key: String, val: String) -> {get_hit(del(put(tab, key, val), key), key) == Some{None{}} : Maybe<&2, Maybe<&2, String>>}:
  match tab:
    case MT{entries}:
      del_hit_core(Con{Entry{key, Some{val}}, entries}, key)
