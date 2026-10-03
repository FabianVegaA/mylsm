import Base
import ./Wal.bend as Wal
import ./MemTable.bend as MemTable
import ./Db.bend as Db
import ./Manifest.bend as Manifest
import ./Sstable.bend as Sstable
import ./SstFileV2.bend as SstFileV2

# --- WAL frame codec (pure) ---

def dash_step(+done: Bool, isdash: Bool, +acc: Nat) -> (Bool & Nat):
  match done:
    case True{}:
      (True{}, acc)
    case False{}:
      match isdash:
        case True{}:
          (False{}, Nat.add(1n, acc))
        case False{}:
          (True{}, acc)

def dash_snd(st: (Bool & Nat)) -> Nat:
  match st:
    case (d, a):
      a

def dash_step_fst(st: (Bool & Nat), +ch: Char) -> (Bool & Nat):
  match st:
    case (done, acc):
      dash_step(done, Char.is_eq(ch, Char.from_u32(45)), acc)

def dash_go(fuel: Nat, st: (Bool & Nat), str: String) -> Nat:
  match fuel:
    case 0n:
      dash_snd(st)
    case 1n+f:
      match str:
        case SNil{}:
          dash_snd(st)
        case SCon{h, t}:
          dash_go(f, dash_step_fst(st, h), t)

def dashes_len(+str: String) -> Nat:
  dash_go(Nat.add(String.length(str), 1n), (False{}, 0n), str)

def semi_eq(+ok: Bool, +num: Nat) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      Some{num}
    case False{}:
      None{}

def semi_go(+ch: Char, +num: Nat) -> Maybe<&2, Nat>:
  semi_eq(Char.is_eq(ch, Char.from_u32(59)), num)

def sc_go(dropped: String, +num: Nat) -> Maybe<&2, Nat>:
  match dropped:
    case SNil{}:
      None{}
    case SCon{h, t}:
      semi_go(h, num)

def frame_len_go(+num: Nat, +str: String) -> Maybe<&2, Nat>:
  sc_go(String.drop(str, num), num)

def frame_len(+str: String) -> Maybe<&2, Nat>:
  frame_len_go(dashes_len(str), str)

def frame_of(+raw: String) -> String:
  Wal.dashes(String.length(raw)) ++ ";" ++ raw

def consumed(+num: Nat) -> Nat:
  Nat.add(String.length(Wal.dashes(num)), Nat.add(1n, num))

def clip_go(+mlen: Maybe<&2, Nat>, +str: String) -> String:
  match mlen:
    case None{}:
      str
    case Some{n}:
      String.take(String.drop(str, Nat.add(String.length(Wal.dashes(n)), 1n)), n)

def drop_after(+mlen: Maybe<&2, Nat>, +str: String) -> String:
  match mlen:
    case None{}:
      str
    case Some{n}:
      String.drop(str, consumed(n))

def dec_apply(+m2: Maybe<&2, Wal.Batch>, res: Db.RotRes) -> Db.RotRes:
  match m2:
    case None{}:
      res
    case Some{Wal.Batch{muts}}:
      match res:
        case Db.Rot{mem, frozen, mc, fc}:
          Db.apply_and_rotate(muts, mem, frozen, mc, fc)

# Fuel-only drivers (no s-match: fuel bounds the walk; torn/empty tails
# are fixpoints that burn fuel and return the valid-prefix accumulation).
def replay_mem_go(fuel: Nat, res: Db.RotRes, +str: String) -> Db.RotRes:
  match fuel:
    case 0n:
      res
    case 1n+g:
      +fl = frame_len(str)
      replay_mem_go(g, dec_apply(Wal.decode(clip_go(fl, str)), res), drop_after(fl, str))

def replay_mem(+str: String) -> Db.RotRes:
  replay_mem_go(Nat.add(String.length(str), 1n), Db.Rot{MemTable.empty(), MemTable.empty(), 0n, 0n}, str)

def valid_add(+mlen: Maybe<&2, Nat>, +acc: Nat) -> Nat:
  match mlen:
    case None{}:
      acc
    case Some{n}:
      Nat.add(acc, consumed(n))

def replay_valid_go(fuel: Nat, +acc: Nat, +str: String) -> Nat:
  match fuel:
    case 0n:
      acc
    case 1n+g:
      +fl = frame_len(str)
      replay_valid_go(g, valid_add(fl, acc), drop_after(fl, str))

def replay_valid(+str: String) -> Nat:
  replay_valid_go(Nat.add(String.length(str), 1n), 0n, str)

# --- Flush-counter restore (pure) ---

def mid_and(lhs: Bool, rhs: Bool) -> Bool:
  match lhs:
    case True{}:
      rhs
    case False{}:
      False{}

def shape_mid(first: Bool, second: Bool, third: Bool) -> Bool:
  mid_and(first, mid_and(second, third))

# Table generations are compact decimal only. Unparsable middles are invalid
# (no unary-dash legacy reads: no retrocompat).
def gen_valid_read(parsed: Maybe<&2, Nat>) -> Bool:
  match parsed:
    case Some{n}:
      True{}
    case None{}:
      False{}

def gen_valid(+middle: String) -> Bool:
  gen_valid_read(Nat.read(middle))

def ov_ok(+big: Bool, +name: String, +ln: Nat) -> Bool:
  match big:
    case True{}:
      shape_mid(String.starts_with(name, "l"), String.ends_with(name, ".tbl"), gen_valid(String.take(String.drop(name, 3n), Nat.sub(ln, 7n))))
    case False{}:
      False{}

def name_shape(+name: String) -> Bool:
  +ln = String.length(name)
  ov_ok(Nat.is_le(7n, ln), name, ln)

def level_name_ok(+big: Bool, +name: String, +ln: Nat, +prefix: String, +prefix_len: Nat) -> Bool:
  match big:
    case False{}:
      False{}
    case True{}:
      shape_mid(String.starts_with(name, prefix), String.ends_with(name, ".tbl"), gen_valid(String.take(String.drop(name, prefix_len), Nat.sub(ln, Nat.add(prefix_len, 4n)))))

def name_shape_level(+name: String, +level: Nat) -> Bool:
  +prefix = "l" ++ Nat.show(level) ++ "-"
  +prefix_len = String.length(prefix)
  +ln = String.length(name)
  level_name_ok(Nat.is_le(Nat.add(prefix_len, 4n), ln), name, ln, prefix, prefix_len)

def gen_value_read(parsed: Maybe<&2, Nat>) -> Nat:
  match parsed:
    case Some{n}:
      n
    case None{}:
      0n

def gen_value(+middle: String) -> Nat:
  gen_value_read(Nat.read(middle))

def name_gen(+name: String) -> Nat:
  +ln = String.length(name)
  gen_value(String.take(String.drop(name, 3n), Nat.sub(ln, 7n)))

def names_ok(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      mid_and(name_shape(h), names_ok(t))

def level_names_ok(+level: Nat, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      mid_and(name_shape_level(h, level), level_names_ok(level, t))

def manifest_names_ok(levels: List<&2, List<&2, String>>, +level: Nat) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{names, rest}:
      mid_and(level_names_ok(level, names), manifest_names_ok(rest, Nat.add(level, 1n)))

def names_all(lvls: List<&2, List<&2, String>>) -> List<&2, String>:
  match lvls:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      List.append(&2, String, h, names_all(t))

def cmax(names: List<&2, String>, +cur: Nat) -> Nat:
  match names:
    case Nil{}:
      cur
    case Con{h, t}:
      cmax(t, Nat.max(name_gen(h), cur))

def count_gen(+lvls: List<&2, List<&2, String>>) -> Nat:
  Nat.add(cmax(names_all(lvls), 0n), 1n)

def mfst_lists(+mfst: Manifest.Manifest) -> List<&2, List<&2, String>>:
  match mfst:
    case Manifest.M{lvs}:
      lvs

# L0 may overlap by design. Every table within each level below L0 must have
# a range disjoint from every peer; metadata makes this check independent of
# SortedRun and avoids reparsing entries during recovery.
def disjoint_with_table(+tbl: Sstable.Table, rest: List<&2, Sstable.Table>) -> Bool:
  match rest:
    case Nil{}:
      True{}
    case Con{+h, t}:
      mid_and(Sstable.ranges_disjoint(tbl, h), disjoint_with_table(tbl, t))

def level_pairwise_disjoint(tables: List<&2, Sstable.Table>) -> Bool:
  match tables:
    case Nil{}:
      True{}
    case Con{+h, +t}:
      mid_and(disjoint_with_table(h, t), level_pairwise_disjoint(t))

def lower_levels_disjoint(levels: List<&2, List<&2, Sstable.Table>>) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{+level, rest}:
      mid_and(level_pairwise_disjoint(level), lower_levels_disjoint(rest))

def l1_plus_disjoint(levels: List<&2, List<&2, Sstable.Table>>) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{l0, lower}:
      lower_levels_disjoint(lower)

# --- Batched checksum verification (Task 3): IO stays sequential in
# load_tables; the pure verify below runs over already-loaded bodies ---
# Sequential checksum verdict over encoded bodies.
def verify_all_seq(+bodies: List<&2, String>) -> List<&2, Bool>:
  match bodies:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Con{SstFileV2.body_checksum_ok(h), verify_all_seq(t)}

# Two-way parallel checksum verdict; halves share no state.
def verify_all_par(+bodies: List<&2, String>) -> List<&2, Bool>:
  +half = Nat.div(List.length(&2, String, bodies), 2n)
  left right = verify_all_seq(List.take(&2, String, bodies, half)) verify_all_seq(List.drop(&2, String, bodies, half))
  List.append(&2, Bool, left, right)

# Bang gate: one lane per body, so GPU pays only for wide batches.
def verify_bang_gate(+num: Nat) -> Bool:
  Nat.is_le(64n, num)

# Pick CPU-pool or GPU execution for the same verify tree.
def verify_all_pick(gate: Bool, +bodies: List<&2, String>) -> List<&2, Bool>:
  match gate:
    case False{}:
      verify_all_par(bodies)
    case True{}:
      verify_all_par!(bodies)

# Size-gated entry point; open_db stays sequential until measured.
def verify_all_auto(+bodies: List<&2, String>) -> List<&2, Bool>:
  verify_all_pick(verify_bang_gate(List.length(&2, String, bodies)), bodies)

def needs_flush_cap(+mem: MemTable.MemTable, +cap: Nat) -> Bool:
  Nat.is_lt(cap, MemTable.count(mem))
