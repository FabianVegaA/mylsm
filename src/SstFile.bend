import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest

# SSTable file codec (Task 8): header "T"+dashes(level) ";" dashes(wallen)
# ";" walbytes, whole file body ++ "#" ++ checksum (Manifest.mhash style).
# Bloom filters are NOT stored: parse rebuilds them deterministically via
# Sstable.build (same entries, same level, same count => same table).
# Parse mirrors Manifest: validate-first (Bool), then unchecked structural
# parse, top leaf dispatch. Every reshape is fail-closed (None).

def muts_of_entries(+es: List<&2, MemTable.Entry>) -> List<&2, Wal.Mut>:
  match es:
    case Nil{}:
      Nil{}
    case Con{MemTable.Entry{key, val}, t}:
      match val:
        case None{}:
          Con{Wal.Del{key}, muts_of_entries(t)}
        case Some{v}:
          Con{Wal.Put{key, v}, muts_of_entries(t)}

def entries_of_muts(+ms: List<&2, Wal.Mut>) -> List<&2, MemTable.Entry>:
  match ms:
    case Nil{}:
      Nil{}
    case Con{m, t}:
      match m:
        case Wal.Put{key, val}:
          Con{MemTable.Entry{key, Some{val}}, entries_of_muts(t)}
        case Wal.Del{key}:
          Con{MemTable.Entry{key, None{}}, entries_of_muts(t)}

def serialize(+es: List<&2, MemTable.Entry>, +level: Nat) -> String:
  +muts = muts_of_entries(es)
  +w = Wal.encode(Wal.Batch{muts})
  +n = String.length(w)
  +body = "T" ++ Wal.dashes(level) ++ ";" ++ Wal.dashes(n) ++ ";" ++ w
  body ++ "#" ++ U32.show(Manifest.mhash(body, 7))

# --- Validation (all total, structural) ---

def dash_and(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      b
    case False{}:
      False{}

def all_dash(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      dash_and(Char.is_eq(h, Char.from_u32(45)), all_dash(t))

def hdr_ok(+hdr: String) -> Bool:
  dash_and(String.starts_with(hdr, "T"), all_dash(String.drop(hdr, 1n)))

def is_some_batch(+m: Maybe<&2, Wal.Batch>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{b}:
      True{}

def inner_go(+lend2: String, +r2l: List<&2, String>) -> Bool:
  +wb = String.join(r2l, ";")
  +n = String.length(lend2)
  +taken = String.take(wb, n)
  dash_and(all_dash(lend2), dash_and(String.eq(String.drop(wb, n), ""), is_some_batch(Wal.decode(taken))))

def inner_ok_sp(+sp: List<&2, String>) -> Bool:
  match sp:
    case Nil{}:
      False{}
    case Con{lend, r2}:
      match lend r2:
        case SNil{} Nil{}:
          False{}
        case SNil{} Con{rh, rt}:
          inner_go("", Con{rh, rt})
        case SCon{h, t} Nil{}:
          False{}
        case SCon{h, t} Con{rh, rt}:
          inner_go(SCon{h, t}, Con{rh, rt})

def inner_ok(rest: String) -> Bool:
  inner_ok_sp(String.split(rest, Char.from_u32(59)))

def shape_sp(+sp: List<&2, String>) -> Bool:
  match sp:
    case Nil{}:
      False{}
    case Con{hdr, r1}:
      match hdr r1:
        case SNil{} Nil{}:
          False{}
        case SNil{} Con{rh, rt}:
          dash_and(hdr_ok(""), inner_ok(String.join(Con{rh, rt}, ";")))
        case SCon{h, t} Nil{}:
          False{}
        case SCon{h, t} Con{rh, rt}:
          dash_and(hdr_ok(SCon{h, t}), inner_ok(String.join(Con{rh, rt}, ";")))

def shape_ok(body: String) -> Bool:
  shape_sp(String.split(body, Char.from_u32(59)))

def chk_rd2(+m: Maybe<&2, U32>, content: String) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{v}:
      U32.is_eq(v, Manifest.mhash(content, 7))

# Note: the chk part never carries "#" (split consumed the separator), so
# validation reads the digits directly; a hash mismatch (or unreadable
# digits) fails closed.
def chk_ok(+chk: String, content: String) -> Bool:
  chk_rd2(U32.read(chk), content)

def split_valid(p: (List<&2, String> & String)) -> Bool:
  match p:
    case (+body, chk):
      dash_and(shape_ok(String.join(body, "#")), chk_ok(chk, String.join(body, "#")))

def split_last_hash(ls: List<&2, String>, acc: List<&2, String>) -> (List<&2, String> & String):
  match ls:
    case Nil{}:
      (List.reverse(&2, String, acc), "")
    case Con{h, Nil{}}:
      (List.reverse(&2, String, acc), h)
    case Con{h, Con{k, t}}:
      split_last_hash(Con{k, t}, Con{h, acc})

def valid_file(s: String) -> Bool:
  split_valid(split_last_hash(String.split(s, Char.from_u32(35)), Nil{}))

# --- Unchecked parse (total; defensive None unreachable when valid) ---

def level_of(hdr: String) -> Nat:
  String.length(String.drop(hdr, 1n))

def wal_sp2(+sp2: List<&2, String>) -> String:
  match sp2:
    case Nil{}:
      ""
    case Con{lend, r2}:
      match lend r2:
        case SNil{} Nil{}:
          ""
        case SNil{} Con{rh, rt}:
          String.take(String.join(Con{rh, rt}, ";"), String.length(""))
        case SCon{h, t} Nil{}:
          ""
        case SCon{h, t} Con{rh, rt}:
          String.take(String.join(Con{rh, rt}, ";"), String.length(SCon{h, t}))

def wal_sp(+sp: List<&2, String>) -> String:
  match sp:
    case Nil{}:
      ""
    case Con{hdr, r1}:
      match hdr r1:
        case SNil{} Nil{}:
          ""
        case SNil{} Con{rh, rt}:
          wal_sp2(String.split(String.join(Con{rh, rt}, ";"), Char.from_u32(59)))
        case SCon{h, t} Nil{}:
          ""
        case SCon{h, t} Con{rh, rt}:
          wal_sp2(String.split(String.join(Con{rh, rt}, ";"), Char.from_u32(59)))

def wal_of(body: String) -> String:
  wal_sp(String.split(body, Char.from_u32(59)))

def hdr_sp(+sp: List<&2, String>) -> String:
  match sp:
    case Nil{}:
      ""
    case Con{hdr, _}:
      hdr

def hdr_of(body: String) -> String:
  hdr_sp(String.split(body, Char.from_u32(59)))

def build_dec(+m: Maybe<&2, Wal.Batch>, body: String) -> Maybe<&2, Sstable.Table>:
  match m:
    case None{}:
      None{}
    case Some{Wal.Batch{+muts}}:
      +n = List.length(&2, Wal.Mut, muts)
      Some{Sstable.build(entries_of_muts(muts), level_of(hdr_of(body)), n)}

def build_of(+body: String) -> Maybe<&2, Sstable.Table>:
  build_dec(Wal.decode(wal_of(body)), body)

def parse_unchecked(p: (List<&2, String> & String)) -> Maybe<&2, Sstable.Table>:
  match p:
    case (body, chk):
      build_of(String.join(body, "#"))

def parse_dispatch(ok: Bool, s: String) -> Maybe<&2, Sstable.Table>:
  match ok:
    case True{}:
      parse_unchecked(split_last_hash(String.split(s, Char.from_u32(35)), Nil{}))
    case False{}:
      None{}

def parse(+s: String) -> Maybe<&2, Sstable.Table>:
  parse_dispatch(valid_file(s), s)

# --- Closed-vector laws live in LAWS.bend (spec law 6: flush preservation
# needs the file codec round-trip beneath it) ---

# Total-parser witness used by the hardening law.
def is_decided(+m: Maybe<&2, Sstable.Table>) -> Bool:
  True{}
