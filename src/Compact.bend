import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SortedRun.bend as SortedRun
import ./SstFile.bend as SstFile
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest
import ./Flush.bend as Flush
import ./Fs.bend as Fs
import ./Db.bend as Db
import ./CrashPoint.bend as CrashPoint

# Tiered compaction (Task 9): L0-drain + L1 overlap-closure.
#
# Invariants (Task 7/8 read path depends on them):
# - L0-DRAIN: every compaction consumes ALL of L0 (post L0 = []), so every
#   L0 table is strictly newer than every L1+ table.
# - L1-DISJOINT: output is disjoint from every remaining L1 table, via
#   overlap-closure over the final hull (rounds = len(l1)+1 unconditionally;
#   rounds past fixpoint are idempotent, so no done-flag is needed).
# - READ-ORDER MERGE: inputs merge in exact read order (L0 stored order ++
#   absorbed-L1 stored order), so first-wins == read first-match.
# - TOMBSTONE-SAFE: all winning tombstones are retained at this checkpoint.
#   This conservative policy prevents resurrection without requiring zero-output
#   publication support.
# Trigger: L0 count > 4 (spec: backpressure stall at 8 = 2T, Task 10).
# CrashPoint calls are test-only host effects. Unset or unequal checkpoints are
# successful no-ops; signal delivery and filesystem ordering are not Bend proofs.
# Soundness sketch (spec law 11): keys resolving outside the closure are
# untouched (a key in both closure-inputs and a remainder table would put
# it in the hull and in a hull-disjoint range — contradiction); keys inside
# resolve to the same newest version (subset order == read order).

def ov_and(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      b
    case False{}:
      False{}

def le_cmp(c: Cmp) -> Bool:
  match c:
    case LT{}:
      True{}
    case EQ{}:
      True{}
    case GT{}:
      False{}

def ov12(fa: Maybe<&2, String>, lb: Maybe<&2, String>) -> Bool:
  match fa lb:
    case None{} _:
      False{}
    case _ None{}:
      False{}
    case Some{x} Some{y}:
      le_cmp(Keys.cmp(x, y))


def table_overlap(+a: Sstable.Table, +b: Sstable.Table) -> Bool:
  ov_and(ov12(Sstable.table_smallest(a), Sstable.table_largest(b)), ov12(Sstable.table_smallest(b), Sstable.table_largest(a)))

# Hull bound folds (pump+fuel+leaf; single-Maybe state, no pairs).
def pick_lo(c: Cmp, a: String, b: String) -> Maybe<&2, String>:
  match c:
    case LT{}:
      Some{a}
    case EQ{}:
      Some{a}
    case GT{}:
      Some{b}

def min_step(fm: Maybe<&2, String>, cur: Maybe<&2, String>) -> Maybe<&2, String>:
  match fm cur:
    case None{} _:
      cur
    case _ None{}:
      fm
    case Some{+a} Some{+b}:
      pick_lo(Keys.cmp(a, b), a, b)

def min_go(fuel: Nat, +cur: Maybe<&2, String>, tabs: List<&2, Sstable.Table>) -> Maybe<&2, String>:
  match fuel:
    case 0n:
      cur
    case 1n+f:
      match tabs:
        case Nil{}:
          cur
        case Con{h, t}:
          min_go(f, min_step(Sstable.table_smallest(h), cur), t)

def min_first(+tabs: List<&2, Sstable.Table>) -> Maybe<&2, String>:
  min_go(List.length(&2, Sstable.Table, tabs), None{}, tabs)

def pick_hi(c: Cmp, a: String, b: String) -> Maybe<&2, String>:
  match c:
    case LT{}:
      Some{b}
    case EQ{}:
      Some{b}
    case GT{}:
      Some{a}

def max_step(lm: Maybe<&2, String>, cur: Maybe<&2, String>) -> Maybe<&2, String>:
  match lm cur:
    case None{} _:
      cur
    case _ None{}:
      lm
    case Some{+a} Some{+b}:
      pick_hi(Keys.cmp(a, b), a, b)

def max_go(fuel: Nat, +cur: Maybe<&2, String>, tabs: List<&2, Sstable.Table>) -> Maybe<&2, String>:
  match fuel:
    case 0n:
      cur
    case 1n+f:
      match tabs:
        case Nil{}:
          cur
        case Con{h, t}:
          max_go(f, max_step(Sstable.table_largest(h), cur), t)

def max_last(+tabs: List<&2, Sstable.Table>) -> Maybe<&2, String>:
  max_go(List.length(&2, Sstable.Table, tabs), None{}, tabs)

# Overlap of one table against a hull (bounds as params).
def hull_step(keep: Bool, +t: Sstable.Table, +acc: List<&2, Sstable.Table>) -> List<&2, Sstable.Table>:
  match keep:
    case True{}:
      Con{t, acc}
    case False{}:
      acc

def hull_neg(keep: Bool, +t: Sstable.Table, +acc: List<&2, Sstable.Table>) -> List<&2, Sstable.Table>:
  match keep:
    case True{}:
      acc
    case False{}:
      Con{t, acc}

def ov_hull(+t: Sstable.Table, +lo: Maybe<&2, String>, +hi: Maybe<&2, String>) -> Bool:
  ov_and(ov12(Sstable.table_smallest(t), hi), ov12(lo, Sstable.table_largest(t)))

def filt_go(fuel: Nat, +lo: Maybe<&2, String>, +hi: Maybe<&2, String>, +acc: List<&2, Sstable.Table>, rest: List<&2, Sstable.Table>) -> List<&2, Sstable.Table>:
  match fuel:
    case 0n:
      List.reverse(&2, Sstable.Table, acc)
    case 1n+f:
      match rest:
        case Nil{}:
          List.reverse(&2, Sstable.Table, acc)
        case Con{+h, t}:
          filt_go(f, lo, hi, hull_step(ov_hull(h, lo, hi), h, acc), t)

def filter_pos(+rest: List<&2, Sstable.Table>, +lo: Maybe<&2, String>, +hi: Maybe<&2, String>) -> List<&2, Sstable.Table>:
  filt_go(List.length(&2, Sstable.Table, rest), lo, hi, Nil{}, rest)

def filt_neg_go(fuel: Nat, +lo: Maybe<&2, String>, +hi: Maybe<&2, String>, +acc: List<&2, Sstable.Table>, rest: List<&2, Sstable.Table>) -> List<&2, Sstable.Table>:
  match fuel:
    case 0n:
      List.reverse(&2, Sstable.Table, acc)
    case 1n+f:
      match rest:
        case Nil{}:
          List.reverse(&2, Sstable.Table, acc)
        case Con{+h, t}:
          filt_neg_go(f, lo, hi, hull_neg(ov_hull(h, lo, hi), h, acc), t)

def filter_neg(+rest: List<&2, Sstable.Table>, +lo: Maybe<&2, String>, +hi: Maybe<&2, String>) -> List<&2, Sstable.Table>:
  filt_neg_go(List.length(&2, Sstable.Table, rest), lo, hi, Nil{}, rest)

# The production policy is conservative: every winning tombstone is retained
# regardless of the lower-level shadow list.
def drop_none(+k: String, +shadow: List<&2, MemTable.Entry>, +acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{k, None{}}, acc}

def drop_go(fuel: Nat, +shadow: List<&2, MemTable.Entry>, +acc: List<&2, MemTable.Entry>, xs: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match fuel:
    case 0n:
      List.reverse(&2, MemTable.Entry, acc)
    case 1n+f:
      match xs:
        case Nil{}:
          List.reverse(&2, MemTable.Entry, acc)
        case Con{MemTable.Entry{k, v}, t}:
          match v:
            case None{}:
              drop_go(f, shadow, drop_none(k, shadow, acc), t)
            case Some{s}:
              drop_go(f, shadow, Con{MemTable.Entry{k, Some{s}}, acc}, t)

def shadow_drop(+xs: List<&2, MemTable.Entry>, +shadow: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  drop_go(List.length(&2, MemTable.Entry, xs), shadow, Nil{}, xs)


# Preserve each table's strict sorted-run boundary and stored read order.
def table_runs(tabs: List<&2, Sstable.Table>) -> List<&2, List<&2, MemTable.Entry>>:
  match tabs:
    case Nil{}:
      Nil{}
    case Con{h, rest}:
      Con{Db.table_entries(h), table_runs(rest)}


# Production output: merge L0 in chronological stored order, merge absorbed L1
# in its original stored order, then merge L0 as strictly newer than L1.
# Tombstones are retained, so a triggered compaction publishes exactly one table.
def finish_runs(+l0_runs: List<&2, List<&2, MemTable.Entry>>, +l1_runs: List<&2, List<&2, MemTable.Entry>>, +rest: List<&2, Sstable.Table>) -> List<&2, Sstable.Table>:
  +merged_l0 = SortedRun.merge_many_newest(l0_runs)
  +merged_l1 = SortedRun.merge_many_newest(l1_runs)
  +merged = SortedRun.merge_many_newest(Con{merged_l0, Con{merged_l1, Nil{}}})
  Con{Sstable.from_sorted_unique(shadow_drop(merged, Nil{}), 1n), rest}

# Closure rounds retain the original L1 list so the final absorbed runs are
# selected in exact stored read order, independent of the round that found them.
def closed_runs_go(major: Nat, +lo: Maybe<&2, String>, +hi: Maybe<&2, String>, +l0_runs: List<&2, List<&2, MemTable.Entry>>, +all_l1: List<&2, Sstable.Table>, +rest: List<&2, Sstable.Table>) -> List<&2, Sstable.Table>:
  match major:
    case 0n:
      finish_runs(l0_runs, table_runs(filter_pos(all_l1, lo, hi)), rest)
    case 1n+m:
      +abs_new = filter_pos(rest, lo, hi)
      +rem_new = filter_neg(rest, lo, hi)
      closed_runs_go(m, min_step(min_first(abs_new), lo), max_step(max_last(abs_new), hi), l0_runs, all_l1, rem_new)


# Top dispatch (all matches on params; count gate inside).
def compact_snd(+l0: List<&2, Sstable.Table>, rest1: List<&2, List<&2, Sstable.Table>>) -> List<&2, List<&2, Sstable.Table>>:
  match rest1:
    case Nil{}:
      Con{Nil{}, Con{finish_runs(table_runs(l0), Nil{}, Nil{}), Nil{}}}
    case Con{+l1, +below}:
      Con{Nil{}, Con{closed_runs_go(Nat.add(List.length(&2, Sstable.Table, l1), 1n), min_first(l0), max_last(l0), table_runs(l0), l1, l1), below}}

def compact_dec(gt: Bool, +l0: List<&2, Sstable.Table>, +rest1: List<&2, List<&2, Sstable.Table>>) -> List<&2, List<&2, Sstable.Table>>:
  match gt:
    case True{}:
      compact_snd(l0, rest1)
    case False{}:
      Con{l0, rest1}

def compact_levels(levels: List<&2, List<&2, Sstable.Table>>) -> List<&2, List<&2, Sstable.Table>>:
  match levels:
    case Nil{}:
      Nil{}
    case Con{+l0, rest1}:
      compact_dec(Nat.is_lt(4n, List.length(&2, Sstable.Table, l0)), l0, rest1)

# --- IO helpers (Task 9b): remainder-membership, name splits, level surgery.
# Remainder test via ranges (sound by old-L1 disjointness, spec law 12):
# in a disjoint family, overlap with a remainder table means identity.

def or_leaf(+hit: Bool, +acc: Bool) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      acc

def in_go(fuel: Nat, +t: Sstable.Table, +acc: Bool, rem: List<&2, Sstable.Table>) -> Bool:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      match rem:
        case Nil{}:
          acc
        case Con{h, tt}:
          in_go(f, t, or_leaf(table_overlap(t, h), acc), tt)

def in_rem(+t: Sstable.Table, +rem: List<&2, Sstable.Table>) -> Bool:
  in_go(List.length(&2, Sstable.Table, rem), t, False{}, rem)

def abs_pick(+inr: Bool, +n: String, +acc: List<&2, String>) -> List<&2, String>:
  match inr:
    case True{}:
      acc
    case False{}:
      Con{n, acc}

def abs_go(fuel: Nat, +rem: List<&2, Sstable.Table>, +acc: List<&2, String>, tabs: List<&2, Sstable.Table>, names: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+f:
      match tabs names:
        case Nil{} Nil{}:
          List.reverse(&2, String, acc)
        case Nil{} Con{nh, nt}:
          List.reverse(&2, String, acc)
        case Con{th, tt} Nil{}:
          List.reverse(&2, String, acc)
        case Con{th, tt} Con{nh, nt}:
          abs_go(f, rem, abs_pick(in_rem(th, rem), nh, acc), tt, nt)

def abs_names(+tabs: List<&2, Sstable.Table>, +names: List<&2, String>, +rem: List<&2, Sstable.Table>) -> List<&2, String>:
  abs_go(List.length(&2, Sstable.Table, tabs), rem, Nil{}, tabs, names)

def rem_pick(+inr: Bool, +n: String, +acc: List<&2, String>) -> List<&2, String>:
  match inr:
    case True{}:
      Con{n, acc}
    case False{}:
      acc

def rem_go(fuel: Nat, +rem: List<&2, Sstable.Table>, +acc: List<&2, String>, tabs: List<&2, Sstable.Table>, names: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+f:
      match tabs names:
        case Nil{} Nil{}:
          List.reverse(&2, String, acc)
        case Nil{} Con{nh, nt}:
          List.reverse(&2, String, acc)
        case Con{th, tt} Nil{}:
          List.reverse(&2, String, acc)
        case Con{th, tt} Con{nh, nt}:
          rem_go(f, rem, rem_pick(in_rem(th, rem), nh, acc), tt, nt)

def rem_names(+tabs: List<&2, Sstable.Table>, +names: List<&2, String>, +rem: List<&2, Sstable.Table>) -> List<&2, String>:
  rem_go(List.length(&2, Sstable.Table, tabs), rem, Nil{}, tabs, names)

# --- Closed-vector laws live in laws/Compact.bend (spec laws 6, 11, 12) ---

# --- IO chain (Task 9b): output file + manifest rewrite + input removal.
# Crash discipline mirrors flush: output durable, then manifest (tmp +
# rename + dir fsync), then input files become orphans (recovery ignores
# files absent from the manifest; Task 12 sweeps them). Manifest/table
# drift (exact serialized Manifest identity mismatch) aborts fail-closed;
# names stay positionally aligned with tables (output head, remainder tail).

def l1hd(r1: List<&2, List<&2, Sstable.Table>>) -> List<&2, Sstable.Table>:
  match r1:
    case Nil{}:
      Nil{}
    case Con{l1, below}:
      l1

def l1list(lvls: List<&2, List<&2, Sstable.Table>>) -> List<&2, Sstable.Table>:
  match lvls:
    case Nil{}:
      Nil{}
    case Con{l0, r1}:
      l1hd(r1)

def l0list(lvls: List<&2, List<&2, Sstable.Table>>) -> List<&2, Sstable.Table>:
  match lvls:
    case Nil{}:
      Nil{}
    case Con{l0, r1}:
      l0

def hd_tbl(l: List<&2, Sstable.Table>) -> Sstable.Table:
  match l:
    case Nil{}:
      Sstable.from_sorted_unique(Nil{}, 1n)
    case Con{h, t}:
      h

def tail_of(l: List<&2, Sstable.Table>) -> List<&2, Sstable.Table>:
  match l:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      t

def ml0(m: Manifest.Manifest) -> List<&2, String>:
  match m:
    case Manifest.M{lvs}:
      match lvs:
        case Nil{}:
          Nil{}
        case Con{l0n, r1}:
          l0n

def ml1b(r1: List<&2, List<&2, String>>) -> List<&2, String>:
  match r1:
    case Nil{}:
      Nil{}
    case Con{l1n, below}:
      l1n

def ml1(m: Manifest.Manifest) -> List<&2, String>:
  match m:
    case Manifest.M{lvs}:
      match lvs:
        case Nil{}:
          Nil{}
        case Con{l0n, r1}:
          ml1b(r1)

def mbelb(r1: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match r1:
    case Nil{}:
      Nil{}
    case Con{l1n, below}:
      below

def mbelow(m: Manifest.Manifest) -> List<&2, List<&2, String>>:
  match m:
    case Manifest.M{lvs}:
      match lvs:
        case Nil{}:
          Nil{}
        case Con{l0n, r1}:
          mbelb(r1)

def mfst_new(+m: Manifest.Manifest, +remnames: List<&2, String>, +outname: String) -> Manifest.Manifest:
  Manifest.M{Con{Nil{}, Con{Con{outname, remnames}, mbelow(m)}}}

def remove_list(names: List<&2, String>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match names:
    case Nil{}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
    case Con{n, t}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        rm : Result<&1, &1, U32 & String, Unit> <- Fs.remove(n)
        remove_list(t)

def compact_goB(+dir: String, +mpath: String, +mtmp: String, +m2: Manifest.Manifest, +dels: List<&2, String>, +mem: MemTable.MemTable, +levels2: List<&2, List<&2, Sstable.Table>>, +flushed: Nat) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    v1 : Unit <- IO.try(Unit, Flush.write_file(mtmp, Manifest.serialize(m2)))
    cp1 : Unit <- IO.try(Unit, CrashPoint.hit("compact.manifest_synced"))
    v2 : Unit <- IO.try(Unit, Fs.rename(mtmp, mpath))
    v3 : Unit <- IO.try(Unit, Fs.fsync(dir))
    cp2 : Unit <- IO.try(Unit, CrashPoint.hit("compact.manifest_published"))
    ign : Result<&1, &1, U32 & String, Unit> <- remove_list(dels)
    return Done{Db.Db{dir, mem, levels2, Nat.add(flushed, 1n), Manifest.serialize(m2)}}

def prefix_go(names: List<&2, String>, +dir: String, +acc: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}:
      List.reverse(&2, String, acc)
    case Con{h, t}:
      prefix_go(t, dir, Con{dir ++ "/" ++ h, acc})

def prefix(+names: List<&2, String>, +dir: String) -> List<&2, String>:
  prefix_go(names, dir, Nil{})

def drift_go(ok: Bool, +dir: String, +mpath: String, +mtmp: String, +m: Manifest.Manifest, +oldl1: List<&2, Sstable.Table>, +remt: List<&2, Sstable.Table>, +outname: String, +mem: MemTable.MemTable, +levels2: List<&2, List<&2, Sstable.Table>>, +flushed: Nat) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case True{}:
      compact_goB(dir, mpath, mtmp, mfst_new(m, rem_names(oldl1, ml1(m), remt), outname), List.append(&2, String, prefix(ml0(m), dir ++ "/l0"), prefix(abs_names(oldl1, ml1(m), remt), dir ++ "/l1")), mem, levels2, flushed)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(2n), "manifest drift")})

def compact_goA(+dir: String, +l1dir: String, +tmp: String, +final: String, +mpath: String, +mtmp: String, +content: String, +outname: String, +mem: MemTable.MemTable, +levels2: List<&2, List<&2, Sstable.Table>>, +oldl1: List<&2, Sstable.Table>, +remt: List<&2, Sstable.Table>, +flushed: Nat, +manifest_token: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    u1 : Unit <- IO.try(Unit, Flush.ensure_dir(l1dir))
    u2 : Unit <- IO.try(Unit, Flush.write_file(tmp, content))
    cp1 : Unit <- IO.try(Unit, CrashPoint.hit("compact.output_synced"))
    u3 : Unit <- IO.try(Unit, Fs.rename(tmp, final))
    u4 : Unit <- IO.try(Unit, Fs.fsync(l1dir))
    cp2 : Unit <- IO.try(Unit, CrashPoint.hit("compact.output_published"))
    +m : Manifest.Manifest <- IO.try(Manifest.Manifest, Flush.load_mfst(mpath))
    drift_go(String.eq(Manifest.serialize(m), manifest_token), dir, mpath, mtmp, m, oldl1, remt, outname, mem, levels2, flushed)

def compact_pre(+dir: String, +mem: MemTable.MemTable, +levels: List<&2, List<&2, Sstable.Table>>, +flushed: Nat, +manifest_token: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  +levels2 = compact_levels(levels)
  +newl1 = l1list(levels2)
  +out = hd_tbl(newl1)
  +remt = tail_of(newl1)
  +l1dir = dir ++ "/l1"
  +outname = "l1-" ++ Nat.show(flushed) ++ ".tbl"
  compact_goA(dir, l1dir, l1dir ++ "/" ++ outname ++ ".tmp", l1dir ++ "/" ++ outname, dir ++ "/MANIFEST", dir ++ "/MANIFEST.tmp", SstFile.serialize(Db.table_entries(out), 1n), outname, mem, levels2, l1list(levels), remt, flushed, manifest_token)

def compact_trig(gt: Bool, +dir: String, +mem: MemTable.MemTable, +levels: List<&2, List<&2, Sstable.Table>>, +flushed: Nat, +manifest_token: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match gt:
    case True{}:
      compact_pre(dir, mem, levels, flushed, manifest_token)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{Db.Db{dir, mem, levels, flushed, manifest_token}})

def compact(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, levels, flushed, manifest_token}:
      match levels:
        case Nil{}:
          IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{Db.Db{dir, mem, Nil{}, flushed, manifest_token}})
        case Con{+l0, r1}:
          compact_trig(Nat.is_lt(4n, List.length(&2, Sstable.Table, l0)), dir, mem, Con{l0, r1}, flushed, manifest_token)
