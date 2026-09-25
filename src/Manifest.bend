import Base

# Manifest (Task 5): which SSTables live at which level.
# Format is positional (line i = level i, no level numbers to parse):
#   <name>,<name>
#   <name>
#   #<checksum-decimal>
# Names are engine-generated (sst-<level>-<counter>.tbl) AND strictly
# validated on parse ([A-Za-z0-9._-], not "." / ".."): T1 hostile bytes
# must fail closed, never traverse directories (spec §8).
# Checksum covers all content lines (fail-closed on corruption, like WAL).
# Parsing leans on Base (split/join/starts_with/drop/read): precompiled,
# trusted, zero proof burden — laws pin OUR format, not Base.

type Manifest is Data:
  M{levels: List<&2, List<&2, String>>}

def mhash(str: String, seed: U32) -> U32:
  match str:
    case SNil{}:
      seed
    case SCon{c, t}:
      mhash(t, U32.add(U32.mul(seed, 31), Char.to_u32(c)))

def encode_line(names: List<&2, String>) -> String:
  String.join(names, ",")

def encode_lines(xss: List<&2, List<&2, String>>) -> List<&2, String>:
  match xss:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{encode_line(h), encode_lines(t)}

def serialize(mfst: Manifest) -> String:
  match mfst:
    case M{levels}:
      +ls = encode_lines(levels)
      +content = String.join(ls, SCon{Char.from_u32(10), SNil{}})
      String.join(List.append(&2, String, ls, Con{"#" ++ U32.show(mhash(content, 7)), Nil{}}), SCon{Char.from_u32(10), SNil{}})

# --- Strict name validation (structural recursion + leaves; no fuel:
# recursion is unconditional, decisions combine via leaves) ---
def name_ok_step(ok: Bool, good: Bool) -> Bool:
  match ok:
    case True{}:
      good
    case False{}:
      False{}

def nc_alpha(ok: Bool, ch: Char) -> Bool:
  match ok:
    case True{}:
      True{}
    case False{}:
      Char.is_digit(ch)

def nc_us(ok: Bool, +ch: Char) -> Bool:
  match ok:
    case True{}:
      True{}
    case False{}:
      nc_alpha(Char.is_alpha(ch), ch)

def nc_dot(ok: Bool, +ch: Char) -> Bool:
  match ok:
    case True{}:
      True{}
    case False{}:
      nc_us(Char.is_eq(ch, Char.from_u32(95)), ch)

def nc_dash(ok: Bool, +ch: Char) -> Bool:
  match ok:
    case True{}:
      True{}
    case False{}:
      nc_dot(Char.is_eq(ch, Char.from_u32(46)), ch)

def name_char_ok(+ch: Char) -> Bool:
  nc_dash(Char.is_eq(ch, Char.from_u32(45)), ch)

def name_go(str: String, ok: Bool) -> Bool:
  match str:
    case SNil{}:
      ok
    case SCon{h, t}:
      name_go(t, name_ok_step(ok, name_char_ok(h)))

def name_dots2(d2: Bool, str: String) -> Bool:
  match d2:
    case True{}:
      False{}
    case False{}:
      name_go(str, True{})

def name_dots(d1: Bool, d2: Bool, str: String) -> Bool:
  match d1:
    case True{}:
      False{}
    case False{}:
      name_dots2(d2, str)

def name_ok(str: String) -> Bool:
  match str:
    case SNil{}:
      False{}
    case SCon{+h, +t}:
      name_dots(String.eq(SCon{h, t}, "."), String.eq(SCon{h, t}, ".."), SCon{h, t})

def names_and(lhs: Bool, rhs: Bool) -> Bool:
  match lhs:
    case True{}:
      rhs
    case False{}:
      False{}

def names_ok(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      names_and(name_ok(h), names_ok(t))

# --- Parse: validate everything first (Bool), then parse unchecked
# (total, structural, no Maybe in loops). Top dispatch is a leaf. ---
def line_valid(line: String) -> Bool:
  match line:
    case SNil{}:
      True{}
    case SCon{h, t}:
      names_ok(String.split(SCon{h, t}, Char.from_u32(44)))

def body_valid(ls: List<&2, String>) -> Bool:
  match ls:
    case Nil{}:
      True{}
    case Con{h, t}:
      names_and(line_valid(h), body_valid(t))

def chk_rd(opt: Maybe<&2, U32>, content: String) -> Bool:
  match opt:
    case None{}:
      False{}
    case Some{v}:
      U32.is_eq(v, mhash(content, 7))

def chk_sw(sw: Bool, chk: String, content: String) -> Bool:
  match sw:
    case True{}:
      chk_rd(U32.read(String.drop(chk, 1n)), content)
    case False{}:
      False{}

def chk_valid(+chk: String, content: String) -> Bool:
  chk_sw(String.starts_with(chk, "#"), chk, content)

def valid_split(pair: (List<&2, String> & String)) -> Bool:
  match pair:
    case (+body, chk):
      names_and(body_valid(body), chk_valid(chk, String.join(body, SCon{Char.from_u32(10), SNil{}})))

def split_last(ls: List<&2, String>, acc: List<&2, String>) -> (List<&2, String> & String):
  match ls:
    case Nil{}:
      (List.reverse(&2, String, acc), "")
    case Con{h, Nil{}}:
      (List.reverse(&2, String, acc), h)
    case Con{h, Con{k, t}}:
      split_last(Con{k, t}, Con{h, acc})

def valid_lines(lines: List<&2, String>) -> Bool:
  valid_split(split_last(lines, Nil{}))

def valid_manifest(str: String) -> Bool:
  valid_lines(String.split(str, Char.from_u32(10)))

def parse_line_u(line: String) -> List<&2, String>:
  match line:
    case SNil{}:
      Nil{}
    case SCon{h, t}:
      String.split(SCon{h, t}, Char.from_u32(44))

def parse_levels_u(ls: List<&2, String>, acc: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match ls:
    case Nil{}:
      List.reverse(&2, List<&2, String>, acc)
    case Con{h, t}:
      parse_levels_u(t, Con{parse_line_u(h), acc})

def parse_unchecked(pair: (List<&2, String> & String)) -> Manifest:
  match pair:
    case (body, chk):
      M{parse_levels_u(body, Nil{})}

def parse_dispatch(ok: Bool, str: String) -> Maybe<&2, Manifest>:
  match ok:
    case True{}:
      Some{parse_unchecked(split_last(String.split(str, Char.from_u32(10)), Nil{}))}
    case False{}:
      None{}

def parse(+str: String) -> Maybe<&2, Manifest>:
  parse_dispatch(valid_manifest(str), str)

# Total-parser witness used by the hardening law.
def is_decided(+_m: Maybe<&2, Manifest>) -> Bool:
  True{}
