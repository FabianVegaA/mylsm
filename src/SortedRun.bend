import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable

# Pure reference semantics and stable sorted-run merging. This module stays
# independent of Sstable so table construction can depend on it later.

def bool_not(b: Bool) -> Bool:
  match b:
    case False{}:
      True{}
    case True{}:
      False{}

def bool_and(a: Bool, b: Bool) -> Bool:
  match a:
    case False{}:
      False{}
    case True{}:
      b

def bool_or(a: Bool, b: Bool) -> Bool:
  match a:
    case False{}:
      b
    case True{}:
      True{}

def entry_cmp(e1: MemTable.Entry, e2: MemTable.Entry) -> Cmp:
  match e1:
    case MemTable.Entry{k1, v1}:
      match e2:
        case MemTable.Entry{k2, v2}:
          Keys.cmp(k1, k2)

def entry_key_eq(e: MemTable.Entry, +key: String) -> Bool:
  match e:
    case MemTable.Entry{k, v}:
      Keys.eq(k, key)

# --- Reference predicates and observable model ---

def contains_key(+entry: MemTable.Entry, entries: List<&2, MemTable.Entry>) -> Bool:
  match entry:
    case MemTable.Entry{+key, val}:
      match entries:
        case Nil{}:
          False{}
        case Con{h, t}:
          bool_or(entry_key_eq(h, key), contains_key(MemTable.Entry{key, val}, t))

def is_unique(entries: List<&2, MemTable.Entry>) -> Bool:
  match entries:
    case Nil{}:
      True{}
    case Con{+h, +t}:
      bool_and(bool_not(contains_key(h, t)), is_unique(t))

def is_strict(entries: List<&2, MemTable.Entry>) -> Bool:
  match entries:
    case Nil{}:
      True{}
    case Con{h, Nil{}}:
      True{}
    case Con{+h, Con{+next, +rest}}:
      bool_and(Keys.cmp_is_lt(entry_cmp(h, next)), is_strict(Con{next, rest}))

def resolve_step(done: Bool, hit: Bool, val: Maybe<&2, String>, ans: Maybe<&2, Maybe<&2, String>>) -> Bool & Maybe<&2, Maybe<&2, String>>:
  match done:
    case True{}:
      (True{}, ans)
    case False{}:
      match hit:
        case True{}:
          (True{}, Some{val})
        case False{}:
          (False{}, ans)

def resolve_state(entries: List<&2, MemTable.Entry>, +key: String, state: Bool & Maybe<&2, Maybe<&2, String>>) -> Bool & Maybe<&2, Maybe<&2, String>>:
  match entries:
    case Nil{}:
      state
    case Con{MemTable.Entry{k, val}, t}:
      (done, ans) = state
      resolve_state(t, key, resolve_step(done, Keys.eq(k, key), val, ans))

def resolve_answer(state: Bool & Maybe<&2, Maybe<&2, String>>) -> Maybe<&2, Maybe<&2, String>>:
  match state:
    case (done, ans):
      ans

def resolve(entries: List<&2, MemTable.Entry>, key: String) -> Maybe<&2, Maybe<&2, String>>:
  resolve_answer(resolve_state(entries, key, (False{}, None{})))

def resolve_newest_go(runs: List<&2, List<&2, MemTable.Entry>>, +key: String, state: Bool & Maybe<&2, Maybe<&2, String>>) -> Bool & Maybe<&2, Maybe<&2, String>>:
  match runs:
    case Nil{}:
      state
    case Con{run, rest}:
      resolve_newest_go(rest, key, resolve_state(run, key, state))

def resolve_newest(runs: List<&2, List<&2, MemTable.Entry>>, key: String) -> Maybe<&2, Maybe<&2, String>>:
  resolve_answer(resolve_newest_go(runs, key, (False{}, None{})))

# Deliberately quadratic reference canonicalization. Input is newest-first;
# keeping an existing EQ entry therefore preserves newest-version precedence.
def reference_insert_done(c: Cmp) -> Bool:
  match c:
    case LT{}:
      True{}
    case EQ{}:
      True{}
    case GT{}:
      False{}

def reference_insert_acc(c: Cmp, +entry: MemTable.Entry, +h: MemTable.Entry, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match c:
    case LT{}:
      List.append(&2, MemTable.Entry, acc, Con{entry, Con{h, Nil{}}})
    case EQ{}:
      List.append(&2, MemTable.Entry, acc, Con{h, Nil{}})
    case GT{}:
      List.append(&2, MemTable.Entry, acc, Con{h, Nil{}})

def reference_insert_go(rest: List<&2, MemTable.Entry>, +entry: MemTable.Entry, done: Bool, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match rest:
    case Nil{}:
      match done:
        case True{}:
          acc
        case False{}:
          List.append(&2, MemTable.Entry, acc, Con{entry, Nil{}})
    case Con{+h, t}:
      match done:
        case True{}:
          List.append(&2, MemTable.Entry, acc, Con{h, t})
        case False{}:
          +order = entry_cmp(entry, h)
          reference_insert_go(t, entry, reference_insert_done(order), reference_insert_acc(order, entry, h, acc))

def reference_insert(entry: MemTable.Entry, sorted: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  reference_insert_go(sorted, entry, False{}, Nil{})

def reference_fold(entries: List<&2, MemTable.Entry>, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match entries:
    case Nil{}:
      acc
    case Con{e, t}:
      reference_fold(t, reference_insert(e, acc))

def reference_canonicalize(runs: List<&2, List<&2, MemTable.Entry>>, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match runs:
    case Nil{}:
      acc
    case Con{run, rest}:
      reference_canonicalize(rest, reference_fold(run, acc))

def scan_keep_dec(in_range: Bool, key: String, val: Maybe<&2, String>, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match in_range:
    case False{}:
      acc
    case True{}:
      match val:
        case None{}:
          acc
        case Some{v}:
          Con{MemTable.Entry{key, Some{v}}, acc}

def scan_keep(+key: String, val: Maybe<&2, String>, +lo: String, +hi: String, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  scan_keep_dec(bool_and(Keys.le(lo, key), Keys.lt(key, hi)), key, val, acc)

def reference_scan_go(+entries: List<&2, MemTable.Entry>, +lo: String, +hi: String, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match entries:
    case Nil{}:
      List.reverse(&2, MemTable.Entry, acc)
    case Con{MemTable.Entry{+key, val}, t}:
      reference_scan_go(t, lo, hi, scan_keep(key, val, lo, hi, acc))

def reference_scan(runs: List<&2, List<&2, MemTable.Entry>>, +lo: String, +hi: String) -> List<&2, MemTable.Entry>:
  reference_scan_go(reference_canonicalize(runs, Nil{}), lo, hi, Nil{})

def runs_well_formed(runs: List<&2, List<&2, MemTable.Entry>>) -> Bool:
  match runs:
    case Nil{}:
      True{}
    case Con{+run, rest}:
      bool_and(bool_and(is_strict(run), is_unique(run)), runs_well_formed(rest))

# L1 helpers operate on entry runs to avoid a SortedRun <-> Sstable cycle.
def first_key(entries: List<&2, MemTable.Entry>) -> Maybe<&2, String>:
  match entries:
    case Nil{}:
      None{}
    case Con{MemTable.Entry{key, val}, t}:
      Some{key}

def last_key_go(entries: List<&2, MemTable.Entry>, last: String) -> Maybe<&2, String>:
  match entries:
    case Nil{}:
      Some{last}
    case Con{MemTable.Entry{key, val}, t}:
      last_key_go(t, key)

def last_key(entries: List<&2, MemTable.Entry>) -> Maybe<&2, String>:
  match entries:
    case Nil{}:
      None{}
    case Con{MemTable.Entry{key, val}, t}:
      last_key_go(t, key)

def range_disjoint_bounds(
  af: Maybe<&2, String>,
  al: Maybe<&2, String>,
  bf: Maybe<&2, String>,
  bl: Maybe<&2, String>
) -> Bool:
  match af al bf bl:
    case None{} _ _ _:
      True{}
    case _ None{} _ _:
      True{}
    case _ _ None{} _:
      True{}
    case _ _ _ None{}:
      True{}
    case Some{a_first} Some{a_last} Some{b_first} Some{b_last}:
      bool_or(Keys.lt(a_last, b_first), Keys.lt(b_last, a_first))

def range_disjoint(+a: List<&2, MemTable.Entry>, +b: List<&2, MemTable.Entry>) -> Bool:
  range_disjoint_bounds(first_key(a), last_key(a), first_key(b), last_key(b))

def disjoint_with(+run: List<&2, MemTable.Entry>, runs: List<&2, List<&2, MemTable.Entry>>) -> Bool:
  match runs:
    case Nil{}:
      True{}
    case Con{+h, t}:
      bool_and(range_disjoint(run, h), disjoint_with(run, t))

def pairwise_disjoint(runs: List<&2, List<&2, MemTable.Entry>>) -> Bool:
  match runs:
    case Nil{}:
      True{}
    case Con{+h, +t}:
      bool_and(disjoint_with(h, t), pairwise_disjoint(t))

def level_disjoint(+runs: List<&2, List<&2, MemTable.Entry>>) -> Bool:
  bool_and(runs_well_formed(runs), pairwise_disjoint(runs))

def levels_well_formed(levels: List<&2, List<&2, List<&2, MemTable.Entry>>>) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{+level, rest}:
      bool_and(level_disjoint(level), levels_well_formed(rest))

# Expressible prerequisite for lower-shadow reasoning: every supplied level
# strictly below target is itself well formed and pairwise range-disjoint.
def lower_levels_well_formed(levels: List<&2, List<&2, List<&2, MemTable.Entry>>>, target: Nat) -> Bool:
  match levels target:
    case Nil{} _:
      True{}
    case Con{level, below} 0n:
      levels_well_formed(below)
    case Con{level, rest} 1n+n:
      lower_levels_well_formed(rest, n)

# --- Fuel-bounded stable two-run linear merge ---

def merge_step(
  order: Cmp,
  +newer_head: MemTable.Entry,
  newer_tail: List<&2, MemTable.Entry>,
  +older_head: MemTable.Entry,
  older_tail: List<&2, MemTable.Entry>,
  acc: List<&2, MemTable.Entry>
) -> List<&2, MemTable.Entry> & List<&2, MemTable.Entry> & List<&2, MemTable.Entry>:
  match order:
    case LT{}:
      (Con{newer_head, acc}, newer_tail, Con{older_head, older_tail})
    case EQ{}:
      (Con{newer_head, acc}, newer_tail, older_tail)
    case GT{}:
      (Con{older_head, acc}, Con{newer_head, newer_tail}, older_tail)

def merge_go(
  fuel: Nat,
  state: List<&2, MemTable.Entry> & List<&2, MemTable.Entry> & List<&2, MemTable.Entry>
) -> List<&2, MemTable.Entry>:
  match fuel:
    case 0n:
      (acc, newer, older) = state
      List.reverse.go(&2, MemTable.Entry, acc, List.append(&2, MemTable.Entry, newer, older))
    case 1n+f:
      (acc, newer, older) = state
      match newer older:
        case Nil{} Nil{}:
          List.reverse(&2, MemTable.Entry, acc)
        case Nil{} rest:
          List.reverse.go(&2, MemTable.Entry, acc, rest)
        case rest Nil{}:
          List.reverse.go(&2, MemTable.Entry, acc, rest)
        case Con{+nh, nt} Con{+oh, ot}:
          merge_go(f, merge_step(entry_cmp(nh, oh), nh, nt, oh, ot, acc))

def merge_newer(+newer: List<&2, MemTable.Entry>, +older: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  fuel = Nat.add(Nat.add(List.length(&2, MemTable.Entry, newer), List.length(&2, MemTable.Entry, older)), 1n)
  merge_go(fuel, (Nil{}, newer, older))

# --- Precedence-preserving balanced multi-run merge ---

type RunGroup is Data:
  RunGroup{
    newest_rank: Nat,
    oldest_rank: Nat,
    entries: List<&2, MemTable.Entry>
  }

def rank_runs(runs: List<&2, List<&2, MemTable.Entry>>, +rank: Nat) -> List<&2, RunGroup>:
  match runs:
    case Nil{}:
      Nil{}
    case Con{entries, rest}:
      Con{RunGroup{rank, rank, entries}, rank_runs(rest, 1n+rank)}

def merge_groups(newer: RunGroup, older: RunGroup) -> RunGroup:
  match newer:
    case RunGroup{newest_rank, oldest_rank, newer_entries}:
      match older:
        case RunGroup{older_newest, older_oldest, older_entries}:
          RunGroup{newest_rank, older_oldest, merge_newer(newer_entries, older_entries)}

def merge_round(groups: List<&2, RunGroup>) -> List<&2, RunGroup>:
  match groups:
    case Nil{}:
      Nil{}
    case Con{group, Nil{}}:
      Con{group, Nil{}}
    case Con{newer, Con{older, rest}}:
      merged tail = merge_groups(newer, older) merge_round(rest)
      Con{merged, tail}

def group_entries(groups: List<&2, RunGroup>) -> List<&2, MemTable.Entry>:
  match groups:
    case Nil{}:
      Nil{}
    case Con{RunGroup{newest_rank, oldest_rank, entries}, rest}:
      entries

def merge_many_go(fuel: Nat, groups: List<&2, RunGroup>) -> List<&2, MemTable.Entry>:
  match fuel:
    case 0n:
      group_entries(groups)
    case 1n+f:
      merge_many_go(f, merge_round(groups))

def merge_many_newest(+runs: List<&2, List<&2, MemTable.Entry>>) -> List<&2, MemTable.Entry>:
  fuel = Nat.add(List.length(&2, List<&2, MemTable.Entry>, runs), 1n)
  merge_many_go(fuel, rank_runs(runs, 0n))

# Canonicalize raw newest-first entries in O(N log N): each entry starts as one
# already-sorted run, and stable EQ selection preserves the earlier/newer entry.
def singleton_runs(entries: List<&2, MemTable.Entry>) -> List<&2, List<&2, MemTable.Entry>>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{entry, rest}:
      Con{Con{entry, Nil{}}, singleton_runs(rest)}

def sort_newest(entries: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  merge_many_newest(singleton_runs(entries))

def merge_disjoint_dec(ok: Bool, runs: List<&2, List<&2, MemTable.Entry>>) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{merge_many_newest(runs)}

# L1 has no age tie-breaker. Reject malformed overlapping/duplicate ranges;
# for accepted disjoint runs, balanced merge order is observationally irrelevant.
def merge_many_disjoint(+runs: List<&2, List<&2, MemTable.Entry>>) -> Maybe<&2, List<&2, MemTable.Entry>>:
  merge_disjoint_dec(level_disjoint(runs), runs)

# --- Pure bounded output partitioning ---

# A zero target cannot bound a non-empty partition, so the public partitioning
# API and its bound predicate consistently interpret it as the smallest safe
# target: one entry per chunk.
def partition_target(target: Nat) -> Nat:
  match target:
    case 0n:
      1n
    case 1n+n:
      1n+n

def partition_finish(
  current_rev: List<&2, MemTable.Entry>,
  chunks_rev: List<&2, List<&2, MemTable.Entry>>
) -> List<&2, List<&2, MemTable.Entry>>:
  match current_rev:
    case Nil{}:
      List.reverse(&2, List<&2, MemTable.Entry>, chunks_rev)
    case Con{entry, rest}:
      chunk = List.reverse(&2, MemTable.Entry, Con{entry, rest})
      List.reverse(&2, List<&2, MemTable.Entry>, Con{chunk, chunks_rev})

type PartitionState is Data:
  PartitionState{
    room: Nat,
    entries: List<&2, MemTable.Entry>,
    current_rev: List<&2, MemTable.Entry>,
    chunks_rev: List<&2, List<&2, MemTable.Entry>>
  }

def partition_step(
  full: Bool,
  target: Nat,
  room_after: Nat,
  entry: MemTable.Entry,
  rest: List<&2, MemTable.Entry>,
  current_rev: List<&2, MemTable.Entry>,
  chunks_rev: List<&2, List<&2, MemTable.Entry>>
) -> PartitionState:
  match full:
    case False{}:
      PartitionState{room_after, rest, Con{entry, current_rev}, chunks_rev}
    case True{}:
      chunk = List.reverse(&2, MemTable.Entry, Con{entry, current_rev})
      PartitionState{target, rest, Nil{}, Con{chunk, chunks_rev}}

def partition_go(
  fuel: Nat,
  +target: Nat,
  state: PartitionState
) -> List<&2, List<&2, MemTable.Entry>>:
  match fuel state:
    case 0n PartitionState{room, entries, current_rev, chunks_rev}:
      partition_finish(current_rev, chunks_rev)
    case 1n+f PartitionState{0n, entries, current_rev, chunks_rev}:
      partition_finish(current_rev, chunks_rev)
    case 1n+f PartitionState{1n+r, Nil{}, current_rev, chunks_rev}:
      partition_finish(current_rev, chunks_rev)
    case 1n+f PartitionState{1n++r, Con{entry, rest}, current_rev, chunks_rev}:
      partition_go(f, target, partition_step(Nat.is_eq(r, 0n), target, r, entry, rest, current_rev, chunks_rev))

def partition(+target: Nat, +entries: List<&2, MemTable.Entry>) -> List<&2, List<&2, MemTable.Entry>>:
  +size = partition_target(target)
  partition_go(List.length(&2, MemTable.Entry, entries), size, PartitionState{size, entries, Nil{}, Nil{}})

def concat_chunks(chunks: List<&2, List<&2, MemTable.Entry>>) -> List<&2, MemTable.Entry>:
  match chunks:
    case Nil{}:
      Nil{}
    case Con{chunk, rest}:
      List.append(&2, MemTable.Entry, chunk, concat_chunks(rest))

def chunks_bounded_go(+target: Nat, chunks: List<&2, List<&2, MemTable.Entry>>) -> Bool:
  match chunks:
    case Nil{}:
      True{}
    case Con{chunk, rest}:
      bool_and(
        Nat.is_le(List.length(&2, MemTable.Entry, chunk), target),
        chunks_bounded_go(target, rest))

def chunks_bounded(target: Nat, chunks: List<&2, List<&2, MemTable.Entry>>) -> Bool:
  chunks_bounded_go(partition_target(target), chunks)

def chunks_strict_unique(chunks: List<&2, List<&2, MemTable.Entry>>) -> Bool:
  runs_well_formed(chunks)

def chunks_pairwise_disjoint(chunks: List<&2, List<&2, MemTable.Entry>>) -> Bool:
  pairwise_disjoint(chunks)
