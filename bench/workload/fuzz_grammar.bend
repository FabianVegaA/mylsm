import Base
import ../lib/common.bend as Common
import ../../src/Wal.bend as Wal
import ../../src/Manifest.bend as Manifest
import ../../src/SstFile.bend as SstFile
import ../../src/Sstable.bend as Sstable
import ../../src/SortedRun.bend as SortedRun
import ../../src/MemTable.bend as MemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

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

# Represent Expect data used by the storage format grammar test.
type Expect is Data:
  Accept{}
  Reject{}

# Handle wal verdict in the storage format grammar test.
def wal_verdict(res: Result<&1, &1, Wal.Error, Wal.Batch>, want: Expect) -> Bool:
  match res want:
    case Fail{_} Reject{}:
      True{}
    case Fail{_} Accept{}:
      False{}
    case Done{batch} Accept{}:
      True{}
    case Done{_} Reject{}:
      False{}

def wal.decode.hex.value(value: Maybe<&1, Bytes.Bytes>) -> Result<&1, &1, Wal.Error, Wal.Batch>:
  match value:
    case None{}:
      Fail{Wal.Malformed{}}
    case Some{bytes}:
      Wal.decode_frame(bytes)

def wal.decode.hex(+str: String) -> Result<&1, &1, Wal.Error, Wal.Batch>:
  wal.decode.hex.value(Bytes.from_hex(str))

# Check whether wal holds for the storage format grammar test.
def check_wal(+str: String, want: Expect) -> Bool:
  wal_verdict(wal.decode.hex(str), want)

# Handle mfest verdict in the storage format grammar test.
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

# Check whether mfest holds for the storage format grammar test.
def check_mfest(bytes: Bytes.Bytes, want: Expect) -> Bool:
  mfest_verdict(Manifest.parse(bytes), want)

# Handle sst verdict in the storage format grammar test.
def sst_verdict(res: Result<&1, &1, SstFile.Error, Sstable.Table>, want: Expect) -> Bool:
  match res want:
    case Fail{_} Reject{}:
      True{}
    case Fail{_} Accept{}:
      False{}
    case Done{tab} Accept{}:
      True{}
    case Done{_} Reject{}:
      False{}

def sst_hex.verdict(value: Maybe<&1, Bytes.Bytes>, want: Expect) -> Bool:
  match value want:
    case None{} Reject{}:
      True{}
    case None{} Accept{}:
      False{}
    case Some{bytes} _:
      sst_verdict(SstFile.parse(bytes), want)

# Check whether sst holds for the storage format grammar test.
def check_sst(+hex: String, want: Expect) -> Bool:
  sst_hex.verdict(Bytes.from_hex(hex), want)

# Every strict non-empty prefix rejects (single-record bases only).
def truncs_all_go(+base: String, +cut: Nat, acc: List<&1, String & Expect>) -> List<&1, String & Expect>:
  match cut:
    case 0n:
      acc
    case 1n+m:
      truncs_all_go(base, m, Con{(String.take(base, cut), Reject{}), acc})

# Handle truncs all in the storage format grammar test.
def truncs_all(+base: String, +len: Nat) -> List<&1, String & Expect>:
  Con{(base, Accept{}), truncs_all_go(base, Nat.sub(len, 1n), Nil{})}

# Full input accepts; every strict 8th-prefix rejects (large bases).
def truncs8_go(+base: String, +len: Nat, +eighth: Nat, acc: List<&1, String & Expect>) -> List<&1, String & Expect>:
  match eighth:
    case 0n:
      acc
    case 1n+m:
      truncs8_go(base, len, m, Con{(String.take(base, Nat.div(Nat.mul(len, eighth), 8n)), Reject{}), acc})

# Handle truncs8 in the storage format grammar test.
def truncs8(+base: String) -> List<&1, String & Expect>:
  Con{(base, Accept{}), truncs8_go(base, String.length(base), 7n, Nil{})}

# Full input accepts; len-1 and take-1 reject (multi-record bases: only the
# provable cuts — terminator/checksum break and incomplete opener).
def truncs3(+base: String) -> List<&1, String & Expect>:
  Con{(base, Accept{}),
  Con{(String.take(base, Nat.sub(String.length(base), 1n)), Reject{}),
  Con{(String.take(base, 1n), Reject{}), Nil{}}}}

# Handle flip first in the storage format grammar test.
def flip_first(+base: String) -> String:
  "X" ++ String.drop(base, 1n)

# Handle flip last in the storage format grammar test.
def flip_last(+base: String) -> String:
  String.take(base, Nat.sub(String.length(base), 1n)) ++ "X"

# Handle splice hostile in the storage format grammar test.
def splice_hostile(+base: String) -> String:
  +half = Nat.div(String.length(base), 2n)
  String.take(base, half) ++ "../evil" ++ String.drop(base, half)

# Handle hostile prefix in the storage format grammar test.
def hostile_prefix(+base: String) -> String:
  "../evil" ++ base

# Handle splice mid in the storage format grammar test.
def splice_mid(+base: String, +frag: String) -> String:
  +half = Nat.div(String.length(base), 2n)
  String.take(base, half) ++ frag ++ String.drop(base, half)

# --- WAL bases ---

def wal.hex(result: Result<&1, &1, Wal.Error, Bytes.Bytes>) -> String:
  match result:
    case Fail{_}:
      ""
    case Done{bytes}:
      Bytes.to_hex(bytes)

# Handle wal base single in the storage format grammar test.
def wal_base_single() -> String:
  wal.hex(Wal.encode_frame(Wal.Batch{Con{Wal.Put{"k", "v"}, Nil{}}}))

# Handle wal base multi in the storage format grammar test.
def wal_base_multi() -> String:
  wal.hex(Wal.encode_frame(Wal.Batch{Con{Wal.Put{"a", "1"}, Con{Wal.Del{"b"}, Con{Wal.Put{"c", "3"}, Nil{}}}}}))

# Handle wal muts go in the storage format grammar test.
def wal_muts_go(count: Nat, +idx: Nat, acc: List<&2, Wal.Mut>) -> List<&2, Wal.Mut>:
  match count:
    case 0n:
      acc
    case 1n+f:
      wal_muts_go(f, Nat.add(idx, 1n), Con{Wal.Put{"k" ++ Nat.show(idx), "v"}, acc})

# Handle wal base big in the storage format grammar test.
def wal_base_big() -> String:
  wal.hex(Wal.encode_frame(Wal.Batch{wal_muts_go(20n, 0n, Nil{})}))

# Handle wal base dels in the storage format grammar test.
def wal_base_dels() -> String:
  wal.hex(Wal.encode_frame(Wal.Batch{Con{Wal.Del{"x"}, Con{Wal.Del{"y"}, Nil{}}}}))

# Handle wal base empty in the storage format grammar test.
def wal_base_empty() -> String:
  wal.hex(Wal.encode_frame(Wal.Batch{Nil{}}))

# Handle wal specials in the storage format grammar test.
def wal_specials() -> List<&1, String & Expect>:
  Con{(flip_first(wal_base_single()), Reject{}),
  Con{(flip_last(wal_base_single()), Reject{}),
  Con{(wal_base_single() ++ "garbage", Reject{}),
  Con{(splice_hostile(wal_base_single()), Reject{}),
  Con{(hostile_prefix(wal_base_single()), Reject{}),
  Con{(splice_mid(wal_base_big(), "X"), Reject{}),
  Con{(splice_mid(wal_base_big(), ";"), Reject{}),
  Con{(splice_mid(wal_base_big(), "P"), Reject{}),
  Con{(wal_base_empty(), Accept{}),
  Con{("", Reject{}),
  Con{("garbage", Reject{}),
  Con{(wal_base_single() ++ wal_base_single(), Reject{}),
  Con{(wal_base_single() ++ wal_base_multi(), Reject{}),
  Con{(wal_base_multi() ++ wal_base_single(), Reject{}), Nil{}}}}}}}}}}}}}}}

# Handle wal cases in the storage format grammar test.
def wal_cases() -> List<&1, String & Expect>:
  List.append(&1, String & Expect, truncs_all(wal_base_single(), String.length(wal_base_single())),
  List.append(&1, String & Expect, truncs3(wal_base_multi()),
  List.append(&1, String & Expect, truncs3(wal_base_big()),
  List.append(&1, String & Expect, truncs3(wal_base_dels()), wal_specials()))))

# Run cons for the storage format grammar test.
def run_cons(ok: Bool, rest: (Bool & Nat)) -> (Bool & Nat):
  match rest:
    case (rok, n):
      (Bool.and(ok, rok), Nat.add(1n, n))

# Run wal for the storage format grammar test.
def run_wal(cases: List<&1, String & Expect>) -> (Bool & Nat):
  match cases:
    case Nil{}:
      (True{}, 0n)
    case Con{p, t}:
      match p:
        case (str, want):
          run_cons(check_wal(str, want), run_wal(t))

# --- Manifest bases ---

# Handle mfest hex in the storage format grammar test.
def mfest_hex(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Handle mfest base empty in the storage format grammar test.
def mfest_base_empty() -> Bytes.Bytes:
  mfest_hex(Bytes.from_hex("4d594c534d334d0000000003000000001205c80e921bb2ce3c951dca55299a11f60403d7440d7f3949c06848ca9fd22a"))

# Handle mfest base two in the storage format grammar test.
def mfest_base_two() -> Bytes.Bytes:
  mfest_hex(Bytes.from_hex("4d594c534d334d0000000003000000020000000200000005612e74626c00000005622e74626c0000000100000006c3a92e74626cf39b88edf66c32df5f8d45703f73f871850048939b317897290ae7a689d303ad"))

# Handle mfest cases in the storage format grammar test.
def mfest_cases() -> List<&1, Bytes.Bytes & Expect>:
  Con{(mfest_base_empty(), Accept{}),
  Con{(mfest_base_two(), Accept{}),
  Con{(Bytes.set(mfest_base_empty(), 0, 0), Reject{}),
  Con{(Bytes.concat([mfest_base_empty(), Bytes.new(1)]), Reject{}),
  Con{(Bytes.new(0), Reject{}), Nil{}}}}}}

# Run mfest for the storage format grammar test.
def run_mfest(cases: List<&1, Bytes.Bytes & Expect>) -> (Bool & Nat):
  match cases:
    case Nil{}:
      (True{}, 0n)
    case Con{p, t}:
      match p:
        case (bytes, want):
          run_cons(check_mfest(bytes, want), run_mfest(t))

# --- Packed v3 bases, kept as hex so binary bytes never pass through String. ---

def sst_hex.result(result: Result<&1, &1, SstFile.Error, Bytes.Bytes>) -> String:
  match result:
    case Fail{_}:
      ""
    case Done{bytes}:
      Bytes.to_hex(bytes)

# Handle sst base empty in the storage format grammar test.
def sst_base_empty() -> String:
  sst_hex.result(SstFile.encode_file(Nil{}, 0))

# Handle sst base one in the storage format grammar test.
def sst_base_one() -> String:
  sst_hex.result(SstFile.encode_file(Con{MemTable.Entry{"k", Some{"v"}}, Nil{}}, 0))

# Handle sst base two in the storage format grammar test.
def sst_base_two() -> String:
  sst_hex.result(SstFile.encode_file(Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}, 0))

# Handle sst base tomb in the storage format grammar test.
def sst_base_tomb() -> String:
  sst_hex.result(SstFile.encode_file(Con{MemTable.Entry{"gone", None{}}, Nil{}}, 1))

# Handle sst big go in the storage format grammar test.
def sst_big_go(count: Nat, +idx: Nat, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match count:
    case 0n:
      acc
    case 1n+f:
      sst_big_go(f, Nat.add(idx, 1n), Con{MemTable.Entry{"k" ++ Nat.show(idx), Some{"v"}}, acc})

# Handle sst base big in the storage format grammar test.
def sst_base_big() -> String:
  sst_hex.result(SstFile.encode_file(SortedRun.sort_newest(sst_big_go(70n, 0n, Nil{})), 0))

# Handle sst specials in the storage format grammar test.
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

# Handle sst cases in the storage format grammar test.
def sst_cases() -> List<&1, String & Expect>:
  List.append(&1, String & Expect, truncs_all(sst_base_empty(), String.length(sst_base_empty())),
  List.append(&1, String & Expect, truncs_all(sst_base_one(), String.length(sst_base_one())),
  List.append(&1, String & Expect, truncs3(sst_base_two()),
  List.append(&1, String & Expect, truncs_all(sst_base_tomb(), String.length(sst_base_tomb())),
  List.append(&1, String & Expect, truncs3(sst_base_big()), sst_specials())))))

# Run sst for the storage format grammar test.
def run_sst(cases: List<&1, String & Expect>) -> (Bool & Nat):
  match cases:
    case Nil{}:
      (True{}, 0n)
    case Con{p, t}:
      match p:
        case (str, want):
          run_cons(check_sst(str, want), run_sst(t))

# Handle report in the storage format grammar test.
def report(ok: Bool, total: Nat) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("GRAMMAR CLEAN: " ++ Nat.show(total) ++ " directed cases on verdict")
    case False{}:
      IO.die(Unit, U32.from_nat(1n), "directed case off verdict")

# Report 1 for the storage format grammar test.
def report1(wokb: Bool, wn: Nat, mokb: Bool, mn: Nat, sok: (Bool & Nat)) -> IO(Unit):
  match sok:
    case (sokb, sn):
      report(Bool.and(wokb, Bool.and(mokb, sokb)), Nat.add(wn, Nat.add(mn, sn)))

# Report 2 for the storage format grammar test.
def report2(wokb: Bool, wn: Nat, mok: (Bool & Nat), sok: (Bool & Nat)) -> IO(Unit):
  match mok:
    case (mokb, mn):
      report1(wokb, wn, mokb, mn, sok)

# Report 3 for the storage format grammar test.
def report3(wok: (Bool & Nat), mok: (Bool & Nat), sok: (Bool & Nat)) -> IO(Unit):
  match wok:
    case (wokb, wn):
      report2(wokb, wn, mok, sok)

def main() -> IO(Unit):
  do IO<Unit>:
    report3(run_wal(wal_cases()), run_mfest(mfest_cases()), run_sst(sst_cases()))
