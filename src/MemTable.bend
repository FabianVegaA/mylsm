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

def put(t: MemTable, k: String, v: String) -> MemTable:
  match t:
    case MT{entries}:
      MT{Con{Entry{k, Some{v}}, entries}}

def del(t: MemTable, k: String) -> MemTable:
  match t:
    case MT{entries}:
      MT{Con{Entry{k, None{}}, entries}}

def count(t: MemTable) -> Nat:
  match t:
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

def scan_go(fuel: Nat, +k: String, st: (Bool & Maybe<&2, String>), entries: List<&2, Entry>) -> Maybe<&2, String>:
  match fuel:
    case 0n:
      (done, ans) = st
      ans
    case 1n+f:
      (done, ans) = st
      match entries:
        case Nil{}:
          ans
        case Con{Entry{key, val}, t}:
          scan_go(f, k, scan_step(done, Keys.eq(key, k), val, ans), t)

def get(t: MemTable, +k: String) -> Maybe<&2, String>:
  match t:
    case MT{+entries}:
      scan_go(List.length(&2, Entry, entries), k, (False{}, None{}), entries)

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

def scan_hit(fuel: Nat, +k: String, st: (Bool & Maybe<&2, Maybe<&2, String>>), entries: List<&2, Entry>) -> Maybe<&2, Maybe<&2, String>>:
  match fuel:
    case 0n:
      (done, ans) = st
      ans
    case 1n+f:
      (done, ans) = st
      match entries:
        case Nil{}:
          ans
        case Con{Entry{key, val}, t}:
          scan_hit(f, k, scan_hit_step(done, Keys.eq(key, k), val, ans), t)

def get_hit(t: MemTable, +k: String) -> Maybe<&2, Maybe<&2, String>>:
  match t:
    case MT{+entries}:
      scan_hit(List.length(&2, Entry, entries), k, (False{}, None{}), entries)

# Lemma: a frozen (done) scan always answers ans.
def frozen_lemma(fuel: Nat, k: String, ans: Maybe<&2, String>, entries: List<&2, Entry>) -> {scan_go(fuel, k, (True{}, ans), entries) == ans : Maybe<&2, String>}:
  match fuel:
    case 0n:
      {==}
    case 1n+f:
      match entries:
        case Nil{}:
          {==}
        case Con{Entry{key, val}, t}:
          %frozen_lemma(f, k, ans, t) : {scan_go(f, k, (True{}, ans), t) == _ : Maybe<&2, String>}
          {==}

# Lemma: reading a freshly-put key answers its value.
def ryw_core(+entries: List<&2, Entry>, +k: String, v: String) -> {scan_go(List.length(&2, Entry, Con{Entry{k, Some{v}}, entries}), k, (False{}, None{}), Con{Entry{k, Some{v}}, entries}) == Some{v} : Maybe<&2, String>}:
  %Equal.sym(Bool, Keys.eq(k, k), True{}, Keys.str_eq_refl(k)) : {scan_go(List.length(&2, Entry, entries), k, scan_step(False{}, _, Some{v}, None{}), entries) == Some{v} : Maybe<&2, String>}
  %frozen_lemma(List.length(&2, Entry, entries), k, Some{v}, entries) : {scan_go(List.length(&2, Entry, entries), k, (True{}, Some{v}), entries) == _ : Maybe<&2, String>}
  {==}

def ryw_bridge(t: MemTable, +k: String, +v: String) -> {get(put(t, k, v), k) == Some{v} : Maybe<&2, String>}:
  match t:
    case MT{entries}:
      ryw_core(entries, k, v)

# Lemma: reading a freshly-deleted key answers None (tombstone freezes).
def del_core(+entries: List<&2, Entry>, +k: String) -> {scan_go(List.length(&2, Entry, Con{Entry{k, None{}}, entries}), k, (False{}, None{}), Con{Entry{k, None{}}, entries}) == None{} : Maybe<&2, String>}:
  %Equal.sym(Bool, Keys.eq(k, k), True{}, Keys.str_eq_refl(k)) : {scan_go(List.length(&2, Entry, entries), k, scan_step(False{}, _, None{}, None{}), entries) == None{} : Maybe<&2, String>}
  %frozen_lemma(List.length(&2, Entry, entries), k, None{}, entries) : {scan_go(List.length(&2, Entry, entries), k, (True{}, None{}), entries) == _ : Maybe<&2, String>}
  {==}

def del_bridge(t: MemTable, +k: String, v: String) -> {get(del(put(t, k, v), k), k) == None{} : Maybe<&2, String>}:
  match t:
    case MT{entries}:
      del_core(Con{Entry{k, Some{v}}, entries}, k)

# Lemma: a frozen hit-scan always answers ans.
def frozen_hit_lemma(fuel: Nat, k: String, ans: Maybe<&2, Maybe<&2, String>>, entries: List<&2, Entry>) -> {scan_hit(fuel, k, (True{}, ans), entries) == ans : Maybe<&2, Maybe<&2, String>>}:
  match fuel:
    case 0n:
      {==}
    case 1n+f:
      match entries:
        case Nil{}:
          {==}
        case Con{Entry{key, val}, t}:
          %frozen_hit_lemma(f, k, ans, t) : {scan_hit(f, k, (True{}, ans), t) == _ : Maybe<&2, Maybe<&2, String>>}
          {==}

# Lemma: hit-reading a freshly-put key answers a value hit.
def ryw_hit_core(+entries: List<&2, Entry>, +k: String, v: String) -> {scan_hit(List.length(&2, Entry, Con{Entry{k, Some{v}}, entries}), k, (False{}, None{}), Con{Entry{k, Some{v}}, entries}) == Some{Some{v}} : Maybe<&2, Maybe<&2, String>>}:
  %Equal.sym(Bool, Keys.eq(k, k), True{}, Keys.str_eq_refl(k)) : {scan_hit(List.length(&2, Entry, entries), k, scan_hit_step(False{}, _, Some{v}, None{}), entries) == Some{Some{v}} : Maybe<&2, Maybe<&2, String>>}
  %frozen_hit_lemma(List.length(&2, Entry, entries), k, Some{Some{v}}, entries) : {scan_hit(List.length(&2, Entry, entries), k, (True{}, Some{Some{v}}), entries) == _ : Maybe<&2, Maybe<&2, String>>}
  {==}

def hit_ryw_bridge(t: MemTable, +k: String, +v: String) -> {get_hit(put(t, k, v), k) == Some{Some{v}} : Maybe<&2, Maybe<&2, String>>}:
  match t:
    case MT{entries}:
      ryw_hit_core(entries, k, v)

# Lemma: hit-reading a freshly-deleted key answers a tombstone hit.
def del_hit_core(+entries: List<&2, Entry>, +k: String) -> {scan_hit(List.length(&2, Entry, Con{Entry{k, None{}}, entries}), k, (False{}, None{}), Con{Entry{k, None{}}, entries}) == Some{None{}} : Maybe<&2, Maybe<&2, String>>}:
  %Equal.sym(Bool, Keys.eq(k, k), True{}, Keys.str_eq_refl(k)) : {scan_hit(List.length(&2, Entry, entries), k, scan_hit_step(False{}, _, None{}, None{}), entries) == Some{None{}} : Maybe<&2, Maybe<&2, String>>}
  %frozen_hit_lemma(List.length(&2, Entry, entries), k, Some{None{}}, entries) : {scan_hit(List.length(&2, Entry, entries), k, (True{}, Some{None{}}), entries) == _ : Maybe<&2, Maybe<&2, String>>}
  {==}

def hit_del_bridge(t: MemTable, +k: String, v: String) -> {get_hit(del(put(t, k, v), k), k) == Some{None{}} : Maybe<&2, Maybe<&2, String>>}:
  match t:
    case MT{entries}:
      del_hit_core(Con{Entry{k, Some{v}}, entries}, k)
