import Base
import ../src/Console.bend as Console
import ../src/Compact.bend as Compact
import ../src/BitTree.bend as BitTree
import ../src/Db.bend as Db
import ../src/Flush.bend as Flush
import ../src/Fs.bend as Fs
import ../src/Manifest.bend as Manifest
import ../src/MemTable.bend as MemTable
import ../src/SstFile.bend as SstFile
import ../src/Sstable.bend as Sstable
import ../src/SortedRun.bend as SortedRun

# Compaction phase benchmark. Fixture construction is outside every measured
# phase. Each fixture preserves sorted SSTable run boundaries and run_merge uses
# the same stable newest-first merge primitive as production compaction.

def env_default(value: String, fallback: String) -> String:
  match value:
    case SNil{}: fallback
    case SCon{h, t}: SCon{h, t}

def nat_default(value: Maybe<&2, Nat>, fallback: Nat) -> Nat:
  match value:
    case None{}: fallback
    case Some{n}: n

def zeros(n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+m:
      "0" ++ zeros(m)

def padded(n: Nat) -> String:
  +shown = Nat.show(n)
  zeros(Nat.sub(10n, String.length(shown))) ++ shown

def make_run(fuel: Nat, +index: Nat, +tag: String) -> List<&2, MemTable.Entry>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+rest:
      Con{MemTable.Entry{"key-" ++ padded(index), Some{"value-" ++ tag ++ "-" ++ Nat.show(index)}}, make_run(rest, Nat.add(index, 1n), tag)}

def make_fixture(+runs: Nat, +entries: Nat) -> List<&2, List<&2, MemTable.Entry>>:
  match runs:
    case 0n:
      Nil{}
    case 1n+rest:
      Con{make_run(entries, 0n, Nat.show(runs)), make_fixture(rest, entries)}

def bool_text(ok: Bool) -> String:
  match ok:
    case True{}: "pass"
    case False{}: "fail"

def bool_and(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}: b
    case False{}: False{}

def maybe_value_eq(got: Maybe<&2, String>, +expected: String) -> Bool:
  match got:
    case None{}: False{}
    case Some{value}: String.eq(value, expected)

def table_get(t: Sstable.Table, +key: String) -> Maybe<&2, String>:
  MemTable.get(MemTable.MT{Db.table_entries(t)}, key)

def merged_ok(+merged: List<&2, MemTable.Entry>, +entries: Nat, +runs: Nat) -> Bool:
  +last = Nat.sub(entries, 1n)
  bool_and(
    Nat.is_eq(List.length(&2, MemTable.Entry, merged), entries),
    bool_and(
      maybe_value_eq(MemTable.get(MemTable.MT{merged}, "key-" ++ padded(0n)), "value-" ++ Nat.show(runs) ++ "-0"),
      maybe_value_eq(MemTable.get(MemTable.MT{merged}, "key-" ++ padded(last)), "value-" ++ Nat.show(runs) ++ "-" ++ Nat.show(last))))

def parsed_ok(parsed: Maybe<&2, Sstable.Table>, +entries: Nat, +runs: Nat) -> Bool:
  match parsed:
    case None{}:
      False{}
    case Some{+table}:
      +middle = Nat.div(entries, 2n)
      +last = Nat.sub(entries, 1n)
      bool_and(
        Nat.is_eq(Sstable.table_count(table), entries),
        bool_and(
          maybe_value_eq(table_get(table, "key-" ++ padded(0n)), "value-" ++ Nat.show(runs) ++ "-0"),
          bool_and(
            maybe_value_eq(table_get(table, "key-" ++ padded(middle)), "value-" ++ Nat.show(runs) ++ "-" ++ Nat.show(middle)),
            maybe_value_eq(table_get(table, "key-" ++ padded(last)), "value-" ++ Nat.show(runs) ++ "-" ++ Nat.show(last)))))

def tombstone_shape(xs: List<&2, MemTable.Entry>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{MemTable.Entry{key, val}, rest}:
      match val rest:
        case None{} Nil{}: String.eq(key, "gone")
        case _ _: False{}

def tombstone_ok() -> Bool:
  tombstone_shape(SortedRun.merge_many_newest(
    Con{Con{MemTable.Entry{"gone", None{}}, Nil{}},
      Con{Con{MemTable.Entry{"gone", Some{"old"}}, Nil{}}, Nil{}}}))

def odd_runs() -> List<&2, List<&2, MemTable.Entry>>:
  Con{
    Con{MemTable.Entry{"a", Some{"a"}}, Con{MemTable.Entry{"c", Some{"c"}}, Nil{}}},
    Con{
      Con{MemTable.Entry{"b", Some{"b"}}, Con{MemTable.Entry{"d", Some{"d"}}, Nil{}}},
      Con{Con{MemTable.Entry{"e", Some{"e"}}, Nil{}}, Nil{}}}}

def odd_disjoint_ok() -> Bool:
  +merged = SortedRun.merge_many_newest(odd_runs())
  bool_and(
    Nat.is_eq(List.length(&2, MemTable.Entry, merged), 5n),
    bool_and(
      maybe_value_eq(MemTable.get(MemTable.MT{merged}, "a"), "a"),
      bool_and(
        maybe_value_eq(MemTable.get(MemTable.MT{merged}, "d"), "d"),
        maybe_value_eq(MemTable.get(MemTable.MT{merged}, "e"), "e"))))

def force_bloom(b: Sstable.Bloom) -> Nat:
  match b:
    case Sstable.Blm{bits, size}:
      Nat.add(size, BitTree.word_count(bits))

def print_phase(+case_name: String, +phase: String, start: Nat, stop: Nat) -> IO(Unit):
  IO.print("case=" ++ case_name ++ " phase=" ++ phase ++ " elapsed_ms=" ++ Nat.show(Nat.sub(stop, start)))

def run_case(+dir: String, +entries_per_run: Nat, +runs: Nat) -> IO(Unit):
  do IO<Unit>:
    +case_name : String <- IO.pure(String, Nat.show(runs) ++ "x" ++ Nat.show(entries_per_run))
    fixture_start : Nat <- IO.now()
    +fixture : List<&2, List<&2, MemTable.Entry>> <- IO.pure(List<&2, List<&2, MemTable.Entry>>, make_fixture(runs, entries_per_run))
    fixture_count : Nat <- IO.pure(Nat, Nat.mul(runs, entries_per_run))
    fixture_stop : Nat <- IO.now()
    _p0 : Unit <- print_phase(case_name, "fixture_construction_unmeasured", fixture_start, fixture_stop)
    _p1 : Unit <- IO.print("case=" ++ case_name ++ " fixture_entries=" ++ Nat.show(fixture_count))

    merge_start : Nat <- IO.now()
    +merged : List<&2, MemTable.Entry> <- IO.pure(List<&2, MemTable.Entry>, SortedRun.merge_many_newest(fixture))
    merged_count : Nat <- IO.pure(Nat, List.length(&2, MemTable.Entry, merged))
    +merge_correct : Bool <- IO.pure(Bool, merged_ok(merged, entries_per_run, runs))
    merge_stop : Nat <- IO.now()
    _p2 : Unit <- print_phase(case_name, "run_merge", merge_start, merge_stop)

    tombstone_start : Nat <- IO.now()
    +kept : List<&2, MemTable.Entry> <- IO.pure(List<&2, MemTable.Entry>, Compact.shadow_drop(merged, Nil{}))
    +kept_count : Nat <- IO.pure(Nat, List.length(&2, MemTable.Entry, kept))
    tombstone_stop : Nat <- IO.now()
    _p3 : Unit <- print_phase(case_name, "tombstone_processing", tombstone_start, tombstone_stop)

    bloom_start : Nat <- IO.now()
    bloom : Sstable.Bloom <- IO.pure(Sstable.Bloom, Sstable.bloom_of(kept, Sstable.bloom_new(Sstable.bloom_bits(1n, kept_count))))
    bloom_forced : Nat <- IO.pure(Nat, force_bloom(bloom))
    bloom_stop : Nat <- IO.now()
    _p4 : Unit <- print_phase(case_name, "bloom_construction", bloom_start, bloom_stop)

    serialization_start : Nat <- IO.now()
    +serialized : String <- IO.pure(String, SstFile.serialize(kept, 1n))
    serialized_bytes : Nat <- IO.pure(Nat, String.length(serialized))
    +parse_correct : Bool <- IO.pure(Bool, parsed_ok(SstFile.parse(serialized), entries_per_run, runs))
    serialization_stop : Nat <- IO.now()
    _p5 : Unit <- print_phase(case_name, "serialization", serialization_start, serialization_stop)

    +filename : String <- IO.pure(String, "compaction-" ++ case_name ++ ".tbl")
    +tmp_path : String <- IO.pure(String, dir ++ "/" ++ filename ++ ".tmp")
    +final_path : String <- IO.pure(String, dir ++ "/" ++ filename)
    write_start : Nat <- IO.now()
    _w0 : Unit <- IO.try(Unit, Flush.write_file(tmp_path, serialized))
    _w1 : Unit <- IO.try(Unit, Fs.rename(tmp_path, final_path))
    _w2 : Unit <- IO.try(Unit, Fs.fsync(dir))
    write_stop : Nat <- IO.now()
    _p6 : Unit <- print_phase(case_name, "output_write", write_start, write_stop)

    +manifest : Manifest.Manifest <- IO.pure(Manifest.Manifest, Manifest.M{Con{Con{filename, Nil{}}, Nil{}}})
    +manifest_tmp : String <- IO.pure(String, dir ++ "/MANIFEST.tmp")
    +manifest_path : String <- IO.pure(String, dir ++ "/MANIFEST")
    publish_start : Nat <- IO.now()
    _m0 : Unit <- IO.try(Unit, Flush.write_file(manifest_tmp, Manifest.serialize(manifest)))
    _m1 : Unit <- IO.try(Unit, Fs.rename(manifest_tmp, manifest_path))
    _m2 : Unit <- IO.try(Unit, Fs.fsync(dir))
    publish_stop : Nat <- IO.now()
    _p7 : Unit <- print_phase(case_name, "manifest_publication", publish_start, publish_stop)
    correctness : Bool <- IO.pure(Bool, bool_and(merge_correct, bool_and(Nat.is_eq(kept_count, entries_per_run), bool_and(parse_correct, bool_and(tombstone_ok(), odd_disjoint_ok())))))
    _p8 : Unit <- IO.print("case=" ++ case_name ++ " correctness=" ++ bool_text(correctness) ++ " newest_wins=" ++ bool_text(merge_correct) ++ " tombstone=" ++ bool_text(tombstone_ok()) ++ " odd_disjoint_runs=" ++ bool_text(odd_disjoint_ok()) ++ " output_parse=" ++ bool_text(parse_correct))
    IO.print("case=" ++ case_name ++ " status=complete merged_entries=" ++ Nat.show(merged_count) ++ " kept_entries=" ++ Nat.show(kept_count) ++ " bloom_force=" ++ Nat.show(bloom_forced) ++ " serialized_bytes=" ++ Nat.show(serialized_bytes))

def main() -> IO(Unit):
  do IO<Unit>:
    entries_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_ENTRIES"))
    dir_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_DIR"))
    +entries : Nat <- IO.pure(Nat, nat_default(Nat.read(entries_env), 4097n))
    +dir : String <- IO.pure(String, env_default(dir_env, ".mylsm-compaction-bench-data"))
    _h0 : Unit <- IO.print("benchmark=compaction bend_version=2.0.9 entries_per_run=" ++ Nat.show(entries))
    _h1 : Unit <- IO.print("output_directory=" ++ dir)
    _c1 : Unit <- run_case(dir, entries, 1n)
    _c4 : Unit <- run_case(dir, entries, 4n)
    run_case(dir, entries, 5n)
