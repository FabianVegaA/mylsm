import Base
import ../lib/common.bend as Common
import ../../src/Wal.bend as Wal
import ../../src/Manifest.bend as Manifest
import ../../src/SstFile.bend as SstFile
import ../../src/Sstable.bend as Sstable
import ../../src/SortedRun.bend as SortedRun
import ../../src/MemTable.bend as MemTable

# Directed adversarial corpus (Phase 2A). Every case carries its expected
# verdict: decoders must ACCEPT the valid ones and REJECT the rest — never
# trap.
#
# Verdict discipline (each rule verified by execution, never assumed):
# - truncs_all: EVERY strict non-empty prefix of a SMALL single-record base.
#   Single framing unit means no internal boundary can complete: all reject.
#   Used only on bases under ~64 bytes (portable-run budget).
# - truncs8/truncs3: 8th-fractions / endpoints for large or multi-record
#   bases. Multi-record prefixes can land on a record boundary and parse as
#   a shorter batch, so only provable cuts carry verdicts (full, len-1,
#   take-1).
# - Trailing garbage after a complete payload always rejects (verified per
#   format), so every cross-splice rejects.
# - Flips touch first/last chars only (tag/version/checksum/terminator):
#   always structurally fatal.
# - The empty string round-trips in WAL (empty batch accepts) and rejects
#   elsewhere.

type Expect is Data:
  Accept{}
  Reject{}

def wal_verdict(res: Maybe<&2, Wal.Batch>, want: Expect) -> Bool:
  match res want:
    case None{} Reject{}:
      True{}
    case None{} Accept{}:
      False{}
    case Some{batch} Accept{}:
      True{}
    case Some{_} Reject{}:
      False{}

def check_wal(+str: String, want: Expect) -> Bool:
  wal_verdict(Wal.decode(str), want)

def mfest_verdict(res: Maybe<&2, Manifest.Manifest>, want: Expect) -> Bool:
  match res want:
    case None{} Reject{}:
      True{}
    case None{} Accept{}:
      False{}
    case Some{mfst} Accept{}:
      True{}
    case Some{_} Reject{}:
      False{}

def check_mfest(+str: String, want: Expect) -> Bool:
  mfest_verdict(Manifest.parse(str), want)

def sst_verdict(res: Maybe<&2, Sstable.Table>, want: Expect) -> Bool:
  match res want:
    case None{} Reject{}:
      True{}
    case None{} Accept{}:
      False{}
    case Some{tab} Accept{}:
      True{}
    case Some{_} Reject{}:
      False{}

def check_sst(+str: String, want: Expect) -> Bool:
  sst_verdict(SstFile.parse(str), want)

# Every strict non-empty prefix rejects (single-record bases only).
def truncs_all_go(+base: String, +cut: Nat, acc: List<&1, String & Expect>) -> List<&1, String & Expect>:
  match cut:
    case 0n:
      acc
    case 1n+m:
      truncs_all_go(base, m, Con{(String.take(base, cut), Reject{}), acc})

def truncs_all(+base: String, +len: Nat) -> List<&1, String & Expect>:
  Con{(base, Accept{}), truncs_all_go(base, Nat.sub(len, 1n), Nil{})}

# Full input accepts; every strict 8th-prefix rejects (large bases).
def truncs8_go(+base: String, +len: Nat, +eighth: Nat, acc: List<&1, String & Expect>) -> List<&1, String & Expect>:
  match eighth:
    case 0n:
      acc
    case 1n+m:
      truncs8_go(base, len, m, Con{(String.take(base, Nat.div(Nat.mul(len, eighth), 8n)), Reject{}), acc})

def truncs8(+base: String) -> List<&1, String & Expect>:
  Con{(base, Accept{}), truncs8_go(base, String.length(base), 7n, Nil{})}

# Full input accepts; len-1 and take-1 reject (multi-record bases: only the
# provable cuts — terminator/checksum break and incomplete opener).
def truncs3(+base: String) -> List<&1, String & Expect>:
  Con{(base, Accept{}),
  Con{(String.take(base, Nat.sub(String.length(base), 1n)), Reject{}),
  Con{(String.take(base, 1n), Reject{}), Nil{}}}}

def flip_first(+base: String) -> String:
  "X" ++ String.drop(base, 1n)

def flip_last(+base: String) -> String:
  String.take(base, Nat.sub(String.length(base), 1n)) ++ "X"

def splice_hostile(+base: String) -> String:
  +half = Nat.div(String.length(base), 2n)
  String.take(base, half) ++ "../evil" ++ String.drop(base, half)

def hostile_prefix(+base: String) -> String:
  "../evil" ++ base

def splice_mid(+base: String, +frag: String) -> String:
  +half = Nat.div(String.length(base), 2n)
  String.take(base, half) ++ frag ++ String.drop(base, half)

# --- WAL bases ---

def wal_base_single() -> String:
  Wal.encode(Wal.Batch{Con{Wal.Put{"k", "v"}, Nil{}}})

def wal_base_multi() -> String:
  Wal.encode(Wal.Batch{Con{Wal.Put{"a", "1"}, Con{Wal.Del{"b"}, Con{Wal.Put{"c", "3"}, Nil{}}}}})

def wal_muts_go(count: Nat, +idx: Nat, acc: List<&2, Wal.Mut>) -> List<&2, Wal.Mut>:
  match count:
    case 0n:
      acc
    case 1n+f:
      wal_muts_go(f, Nat.add(idx, 1n), Con{Wal.Put{"k" ++ Nat.show(idx), "v"}, acc})

def wal_base_big() -> String:
  Wal.encode(Wal.Batch{wal_muts_go(20n, 0n, Nil{})})

def wal_base_dels() -> String:
  Wal.encode(Wal.Batch{Con{Wal.Del{"x"}, Con{Wal.Del{"y"}, Nil{}}}})

def wal_specials() -> List<&1, String & Expect>:
  Con{(flip_first(wal_base_single()), Reject{}),
  Con{(flip_last(wal_base_single()), Reject{}),
  Con{(wal_base_single() ++ "garbage", Reject{}),
  Con{(splice_hostile(wal_base_single()), Reject{}),
  Con{(hostile_prefix(wal_base_single()), Reject{}),
  Con{(splice_mid(wal_base_big(), "X"), Reject{}),
  Con{(splice_mid(wal_base_big(), ";"), Reject{}),
  Con{(splice_mid(wal_base_big(), "P"), Reject{}),
  Con{(Wal.encode(Wal.Batch{Nil{}}), Accept{}),
  Con{("", Accept{}),
  Con{("garbage", Reject{}),
  Con{(wal_base_single() ++ wal_base_single(), Accept{}),
  Con{(wal_base_single() ++ wal_base_multi(), Accept{}),
  Con{(wal_base_multi() ++ wal_base_single(), Accept{}), Nil{}}}}}}}}}}}}}}}

def wal_cases() -> List<&1, String & Expect>:
  List.append(&1, String & Expect, truncs_all(wal_base_single(), String.length(wal_base_single())),
  List.append(&1, String & Expect, truncs3(wal_base_multi()),
  List.append(&1, String & Expect, truncs3(wal_base_big()),
  List.append(&1, String & Expect, truncs3(wal_base_dels()), wal_specials()))))

def run_cons(ok: Bool, rest: (Bool & Nat)) -> (Bool & Nat):
  match rest:
    case (rok, n):
      (Bool.and(ok, rok), Nat.add(1n, n))

def run_wal(cases: List<&1, String & Expect>) -> (Bool & Nat):
  match cases:
    case Nil{}:
      (True{}, 0n)
    case Con{p, t}:
      match p:
        case (str, want):
          run_cons(check_wal(str, want), run_wal(t))

# --- Manifest bases ---

def mfest_base_empty() -> String:
  Manifest.serialize(Manifest.M{Nil{}})

def mfest_base_one() -> String:
  Manifest.serialize(Manifest.M{Con{Con{"l0-1.tbl", Nil{}}, Nil{}}})

def mfest_base_two() -> String:
  Manifest.serialize(Manifest.M{Con{Con{"l0-2.tbl", Con{"l0-1.tbl", Nil{}}}, Con{Con{"l1-1.tbl", Nil{}}, Nil{}}}})

def mfest_names_go(count: Nat, +idx: Nat, acc: List<&2, String>) -> List<&2, String>:
  match count:
    case 0n:
      acc
    case 1n+f:
      mfest_names_go(f, Nat.add(idx, 1n), Con{"l0-" ++ Nat.show(idx) ++ ".tbl", acc})

def mfest_base_big() -> String:
  Manifest.serialize(Manifest.M{Con{mfest_names_go(10n, 0n, Nil{}), Nil{}}})

def mfest_specials() -> List<&1, String & Expect>:
  Con{(flip_first(mfest_base_one()), Reject{}),
  Con{(flip_last(mfest_base_one()), Reject{}),
  Con{(mfest_base_one() ++ "garbage", Reject{}),
  Con{(splice_hostile(mfest_base_one()), Reject{}),
  Con{(hostile_prefix(mfest_base_one()), Reject{}),
  Con{(splice_mid(mfest_base_big(), "X"), Reject{}),
  Con{(splice_mid(mfest_base_big(), ";"), Reject{}),
  Con{(splice_mid(mfest_base_big(), "l"), Reject{}),
  Con{("", Reject{}),
  Con{("garbage", Reject{}),
  Con{(mfest_base_one() ++ mfest_base_two(), Reject{}),
  Con{(mfest_base_two() ++ mfest_base_one(), Reject{}), Nil{}}}}}}}}}}}}}

def mfest_cases() -> List<&1, String & Expect>:
  List.append(&1, String & Expect, truncs_all(mfest_base_empty(), String.length(mfest_base_empty())),
  List.append(&1, String & Expect, truncs_all(mfest_base_one(), String.length(mfest_base_one())),
  List.append(&1, String & Expect, truncs3(mfest_base_two()),
  List.append(&1, String & Expect, truncs3(mfest_base_big()), mfest_specials()))))

def run_mfest(cases: List<&1, String & Expect>) -> (Bool & Nat):
  match cases:
    case Nil{}:
      (True{}, 0n)
    case Con{p, t}:
      match p:
        case (str, want):
          run_cons(check_mfest(str, want), run_mfest(t))

# --- S2 bases: empty, one put, two puts, tombstone, big ---

def sst_base_empty() -> String:
  SstFile.serialize(Nil{}, 0n)

def sst_base_one() -> String:
  SstFile.serialize(Con{MemTable.Entry{"k", Some{"v"}}, Nil{}}, 0n)

def sst_base_two() -> String:
  SstFile.serialize(Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}, 0n)

def sst_base_tomb() -> String:
  SstFile.serialize(Con{MemTable.Entry{"gone", None{}}, Nil{}}, 1n)

def sst_big_go(count: Nat, +idx: Nat, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match count:
    case 0n:
      acc
    case 1n+f:
      sst_big_go(f, Nat.add(idx, 1n), Con{MemTable.Entry{"k" ++ Nat.show(idx), Some{"v"}}, acc})

def sst_base_big() -> String:
  SstFile.serialize(SortedRun.sort_newest(sst_big_go(70n, 0n, Nil{})), 0n)

def sst_specials() -> List<&1, String & Expect>:
  Con{(flip_first(sst_base_two()), Reject{}),
  Con{(flip_last(sst_base_two()), Reject{}),
  Con{(sst_base_two() ++ "garbage", Reject{}),
  Con{(splice_hostile(sst_base_two()), Reject{}),
  Con{(hostile_prefix(sst_base_two()), Reject{}),
  Con{(splice_mid(sst_base_big(), "X"), Reject{}),
  Con{(splice_mid(sst_base_big(), ";"), Reject{}),
  Con{(splice_mid(sst_base_big(), "P"), Reject{}),
  Con{("", Reject{}),
  Con{("garbage", Reject{}),
  Con{(sst_base_two() ++ sst_base_tomb(), Reject{}),
  Con{(sst_base_tomb() ++ sst_base_two(), Reject{}), Nil{}}}}}}}}}}}}}

def sst_cases() -> List<&1, String & Expect>:
  List.append(&1, String & Expect, truncs_all(sst_base_empty(), String.length(sst_base_empty())),
  List.append(&1, String & Expect, truncs_all(sst_base_one(), String.length(sst_base_one())),
  List.append(&1, String & Expect, truncs3(sst_base_two()),
  List.append(&1, String & Expect, truncs_all(sst_base_tomb(), String.length(sst_base_tomb())),
  List.append(&1, String & Expect, truncs3(sst_base_big()), sst_specials())))))

def run_sst(cases: List<&1, String & Expect>) -> (Bool & Nat):
  match cases:
    case Nil{}:
      (True{}, 0n)
    case Con{p, t}:
      match p:
        case (str, want):
          run_cons(check_sst(str, want), run_sst(t))

def report(ok: Bool, total: Nat) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("GRAMMAR CLEAN: " ++ Nat.show(total) ++ " directed cases on verdict")
    case False{}:
      IO.die(Unit, U32.from_nat(1n), "directed case off verdict")

def report1(wokb: Bool, wn: Nat, mokb: Bool, mn: Nat, sok: (Bool & Nat)) -> IO(Unit):
  match sok:
    case (sokb, sn):
      report(Bool.and(wokb, Bool.and(mokb, sokb)), Nat.add(wn, Nat.add(mn, sn)))

def report2(wokb: Bool, wn: Nat, mok: (Bool & Nat), sok: (Bool & Nat)) -> IO(Unit):
  match mok:
    case (mokb, mn):
      report1(wokb, wn, mokb, mn, sok)

def report3(wok: (Bool & Nat), mok: (Bool & Nat), sok: (Bool & Nat)) -> IO(Unit):
  match wok:
    case (wokb, wn):
      report2(wokb, wn, mok, sok)

def main() -> IO(Unit):
  do IO<Unit>:
    report3(run_wal(wal_cases()), run_mfest(mfest_cases()), run_sst(sst_cases()))
