import Base
import ./MemTable.bend as MemTable
import ./Manifest.bend as Manifest
import ./Sstable.bend as Sstable

# --- Flush-counter restore (pure) ---

# Handle mid and in the pure recovery decisions.
def mid_and(lhs: Bool, rhs: Bool) -> Bool:
  match lhs:
    case True{}:
      rhs
    case False{}:
      False{}

# Handle shape mid in the pure recovery decisions.
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

# Handle gen valid in the pure recovery decisions.
def gen_valid(+middle: String) -> Bool:
  gen_valid_read(Nat.read(middle))

# Handle ov ok in the pure recovery decisions.
def ov_ok(+big: Bool, +name: String, +ln: Nat) -> Bool:
  match big:
    case True{}:
      shape_mid(String.starts_with(name, "l"), String.ends_with(name, ".tbl"), gen_valid(String.take(String.drop(name, 3n), Nat.sub(ln, 7n))))
    case False{}:
      False{}

# Handle name shape in the pure recovery decisions.
def name_shape(+name: String) -> Bool:
  +ln = String.length(name)
  ov_ok(Nat.is_le(7n, ln), name, ln)

# Return the level name ok for the pure recovery decisions.
def level_name_ok(+big: Bool, +name: String, +ln: Nat, +prefix: String, +prefix_len: Nat) -> Bool:
  match big:
    case False{}:
      False{}
    case True{}:
      shape_mid(String.starts_with(name, prefix), String.ends_with(name, ".tbl"), gen_valid(String.take(String.drop(name, prefix_len), Nat.sub(ln, Nat.add(prefix_len, 4n)))))

# Handle name shape level in the pure recovery decisions.
def name_shape_level(+name: String, +level: Nat) -> Bool:
  +prefix = "l" ++ Nat.show(level) ++ "-"
  +prefix_len = String.length(prefix)
  +ln = String.length(name)
  level_name_ok(Nat.is_le(Nat.add(prefix_len, 4n), ln), name, ln, prefix, prefix_len)

# Handle gen value read in the pure recovery decisions.
def gen_value_read(parsed: Maybe<&2, Nat>) -> Nat:
  match parsed:
    case Some{n}:
      n
    case None{}:
      0n

# Handle gen value in the pure recovery decisions.
def gen_value(+middle: String) -> Nat:
  gen_value_read(Nat.read(middle))

# Handle name gen in the pure recovery decisions.
def name_gen(+name: String) -> Nat:
  +ln = String.length(name)
  gen_value(String.take(String.drop(name, 3n), Nat.sub(ln, 7n)))

# Handle names ok in the pure recovery decisions.
def names_ok(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      mid_and(name_shape(h), names_ok(t))

# Return the level names ok for the pure recovery decisions.
def level_names_ok(+level: Nat, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      mid_and(name_shape_level(h, level), level_names_ok(level, t))

# Handle manifest names ok in the pure recovery decisions.
def manifest_names_ok(levels: List<&2, List<&2, String>>, +level: Nat) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{names, rest}:
      mid_and(level_names_ok(level, names), manifest_names_ok(rest, Nat.add(level, 1n)))

# Handle names all in the pure recovery decisions.
def names_all(lvls: List<&2, List<&2, String>>) -> List<&2, String>:
  match lvls:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      List.append(&2, String, h, names_all(t))

# Handle cmax in the pure recovery decisions.
def cmax(names: List<&2, String>, +cur: Nat) -> Nat:
  match names:
    case Nil{}:
      cur
    case Con{h, t}:
      cmax(t, Nat.max(name_gen(h), cur))

# Count gen in the pure recovery decisions.
def count_gen(+lvls: List<&2, List<&2, String>>) -> Nat:
  Nat.add(cmax(names_all(lvls), 0n), 1n)

# Handle mfst lists in the pure recovery decisions.
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

# Return the level pairwise disjoint for the pure recovery decisions.
def level_pairwise_disjoint(tables: List<&2, Sstable.Table>) -> Bool:
  match tables:
    case Nil{}:
      True{}
    case Con{+h, +t}:
      mid_and(disjoint_with_table(h, t), level_pairwise_disjoint(t))

# Check lower-level levels disjoint for the pure recovery decisions.
def lower_levels_disjoint(levels: List<&2, List<&2, Sstable.Table>>) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{+level, rest}:
      mid_and(level_pairwise_disjoint(level), lower_levels_disjoint(rest))

# Handle l1 plus disjoint in the pure recovery decisions.
def l1_plus_disjoint(levels: List<&2, List<&2, Sstable.Table>>) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{l0, lower}:
      lower_levels_disjoint(lower)

# Handle needs flush cap in the pure recovery decisions.
def needs_flush_cap(+mem: MemTable.MemTable, +cap: Nat) -> Bool:
  Nat.is_lt(cap, MemTable.count(mem))
