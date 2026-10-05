import Base
import ../../src/Console.bend as Console
import ../../src/Compact.bend as Compact
import ../../src/BitTree.bend as BitTree
import ../../src/Db.bend as Db
import ../../src/Flush.bend as Flush
import ../../src/Fs.bend as Fs
import ../../src/Manifest.bend as Manifest
import ../../src/MemTable.bend as MemTable
import ../../src/SstFile.bend as SstFile
import ../../src/SstStreamIo.bend as SstStreamIo
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ../../src/Sstable.bend as Sstable
import ../../src/SortedRun.bend as SortedRun
import ../lib/common.bend as Common

# Compaction phase benchmark. Fixture construction is outside every measured
# phase. Each fixture preserves sorted SSTable run boundaries and run_merge uses
# the same stable newest-first merge primitive as production compaction.

# Handle zero values for s for the compaction benchmark.
def zeros(num: Nat) -> String:
  match num:
    case 0n:
      ""
    case 1n+m:
      "0" ++ zeros(m)

# Handle padded in the compaction benchmark.
def padded(num: Nat) -> String:
  +shown = Nat.show(num)
  zeros(Nat.sub(10n, String.length(shown))) ++ shown

# Create run for the compaction benchmark.
def make_run(fuel: Nat, +index: Nat, +tag: String) -> List<&2, MemTable.Entry>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+rest:
      Con{MemTable.Entry{"key-" ++ padded(index), Some{"value-" ++ tag ++ "-" ++ Nat.show(index)}}, make_run(rest, Nat.add(index, 1n), tag)}

# Create fixture for the compaction benchmark.
def make_fixture(+runs: Nat, +entries: Nat) -> List<&2, List<&2, MemTable.Entry>>:
  match runs:
    case 0n:
      Nil{}
    case 1n+rest:
      Con{make_run(entries, 0n, Nat.show(runs)), make_fixture(rest, entries)}

# Evaluate and for the compaction benchmark.
def bool_and(lhs: Bool, rhs: Bool) -> Bool:
  match lhs:
    case True{}: rhs
    case False{}: False{}

# Return the table get for the compaction benchmark.
def table_get(tab: Sstable.Table, +key: String) -> Maybe<&2, String>:
  MemTable.get(MemTable.MT{Db.table_entries(tab)}, key)

# Merge d ok for the compaction benchmark.
def merged_ok(+merged: List<&2, MemTable.Entry>, +entries: Nat, +runs: Nat) -> Bool:
  +last = Nat.sub(entries, 1n)
  bool_and(
    Nat.is_eq(List.length(&2, MemTable.Entry, merged), entries),
    bool_and(
      Common.maybe_value_eq(MemTable.get(MemTable.MT{merged}, "key-" ++ padded(0n)), "value-" ++ Nat.show(runs) ++ "-0"),
      Common.maybe_value_eq(MemTable.get(MemTable.MT{merged}, "key-" ++ padded(last)), "value-" ++ Nat.show(runs) ++ "-" ++ Nat.show(last))))

# Parse d ok for the compaction benchmark.
def parsed_ok(parsed: Result<&1, &1, SstFile.Error, Sstable.Table>, +entries: Nat, +runs: Nat) -> Bool:
  match parsed:
    case Fail{_}:
      False{}
    case Done{+table}:
      +middle = Nat.div(entries, 2n)
      +last = Nat.sub(entries, 1n)
      bool_and(
        Nat.is_eq(Sstable.table_count(table), entries),
        bool_and(
          Common.maybe_value_eq(table_get(table, "key-" ++ padded(0n)), "value-" ++ Nat.show(runs) ++ "-0"),
          bool_and(
            Common.maybe_value_eq(table_get(table, "key-" ++ padded(middle)), "value-" ++ Nat.show(runs) ++ "-" ++ Nat.show(middle)),
            Common.maybe_value_eq(table_get(table, "key-" ++ padded(last)), "value-" ++ Nat.show(runs) ++ "-" ++ Nat.show(last)))))

def encoded_size.pair(pair: Bytes.Bytes & U32) -> Nat:
  match pair:
    case (_, +len):
      U32.to_nat(len)

# Encode d size for the compaction benchmark.
def encoded_size(result: Result<&1, &1, SstFile.Error, Bytes.Bytes>) -> Nat:
  match result:
    case Fail{_}:
      0n
    case Done{bytes}:
      encoded_size.pair(Bytes.length(bytes))

# Encode d table ok for the compaction benchmark.
def encoded_table_ok(result: Result<&1, &1, SstFile.Error, Bytes.Bytes>, +entries: Nat, +runs: Nat) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{bytes}:
      parsed_ok(SstFile.parse(bytes), entries, runs)

# Handle tombstone shape in the compaction benchmark.
def tombstone_shape(xs: List<&2, MemTable.Entry>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{MemTable.Entry{key, val}, rest}:
      match val rest:
        case None{} Nil{}: String.eq(key, "gone")
        case _ _: False{}

# Handle tombstone ok in the compaction benchmark.
def tombstone_ok() -> Bool:
  tombstone_shape(SortedRun.merge_many_newest(
    Con{Con{MemTable.Entry{"gone", None{}}, Nil{}},
      Con{Con{MemTable.Entry{"gone", Some{"old"}}, Nil{}}, Nil{}}}))

# Handle odd runs in the compaction benchmark.
def odd_runs() -> List<&2, List<&2, MemTable.Entry>>:
  Con{
    Con{MemTable.Entry{"a", Some{"a"}}, Con{MemTable.Entry{"c", Some{"c"}}, Nil{}}},
    Con{
      Con{MemTable.Entry{"b", Some{"b"}}, Con{MemTable.Entry{"d", Some{"d"}}, Nil{}}},
      Con{Con{MemTable.Entry{"e", Some{"e"}}, Nil{}}, Nil{}}}}

# Handle odd disjoint ok in the compaction benchmark.
def odd_disjoint_ok() -> Bool:
  +merged = SortedRun.merge_many_newest(odd_runs())
  bool_and(
    Nat.is_eq(List.length(&2, MemTable.Entry, merged), 5n),
    bool_and(
      Common.maybe_value_eq(MemTable.get(MemTable.MT{merged}, "a"), "a"),
      bool_and(
        Common.maybe_value_eq(MemTable.get(MemTable.MT{merged}, "d"), "d"),
        Common.maybe_value_eq(MemTable.get(MemTable.MT{merged}, "e"), "e"))))

# Handle force bloom in the compaction benchmark.
def force_bloom(rhs: Sstable.Bloom) -> Nat:
  match rhs:
    case Sstable.Blm{bits, size}:
      Nat.add(size, BitTree.word_count(bits))

# Print phase for the compaction benchmark.
def print_phase(+case_name: String, +phase: String, start: Nat, stop: Nat) -> IO(Unit):
  IO.print("case=" ++ case_name ++ " phase=" ++ phase ++ " elapsed_ms=" ++ Nat.show(Nat.sub(stop, start)))

# Run case for the compaction benchmark.
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
    serialized : Result<&1, &1, SstFile.Error, Bytes.Bytes> <- IO.pure(Result<&1, &1, SstFile.Error, Bytes.Bytes>, SstFile.encode_file(kept, 1))
    serialized_bytes : Nat <- IO.pure(Nat, encoded_size(serialized))
    +parse_correct : Bool <- IO.pure(Bool, encoded_table_ok(SstFile.encode_file(kept, 1), entries_per_run, runs))
    serialization_stop : Nat <- IO.now()
    _p5 : Unit <- print_phase(case_name, "serialization", serialization_start, serialization_stop)

    +filename : String <- IO.pure(String, "compaction-" ++ case_name ++ ".tbl")
    +tmp_path : String <- IO.pure(String, dir ++ "/" ++ filename ++ ".tmp")
    +final_path : String <- IO.pure(String, dir ++ "/" ++ filename)
    write_start : Nat <- IO.now()
    _w0 : Unit <- IO.try(Unit, SstStreamIo.write_table(tmp_path, kept, 1))
    _w1 : Unit <- IO.try(Unit, Fs.rename(tmp_path, final_path))
    _w2 : Unit <- IO.try(Unit, Fs.fsync(dir))
    write_stop : Nat <- IO.now()
    _p6 : Unit <- print_phase(case_name, "output_write", write_start, write_stop)

    +manifest : Manifest.Manifest <- IO.pure(Manifest.Manifest, Manifest.M{Con{Con{filename, Nil{}}, Nil{}}})
    +manifest_tmp : String <- IO.pure(String, dir ++ "/MANIFEST.tmp")
    +manifest_path : String <- IO.pure(String, dir ++ "/MANIFEST")
    publish_start : Nat <- IO.now()
    _m0 : Unit <- IO.try(Unit, Flush.write_manifest(manifest_tmp, manifest))
    _m1 : Unit <- IO.try(Unit, Fs.rename(manifest_tmp, manifest_path))
    _m2 : Unit <- IO.try(Unit, Fs.fsync(dir))
    publish_stop : Nat <- IO.now()
    _p7 : Unit <- print_phase(case_name, "manifest_publication", publish_start, publish_stop)
    correctness : Bool <- IO.pure(Bool, bool_and(merge_correct, bool_and(Nat.is_eq(kept_count, entries_per_run), bool_and(parse_correct, bool_and(tombstone_ok(), odd_disjoint_ok())))))
     _p8 : Unit <- IO.print("case=" ++ case_name ++ " correctness=" ++ Common.bool_text(correctness) ++ " newest_wins=" ++ Common.bool_text(merge_correct) ++ " tombstone=" ++ Common.bool_text(tombstone_ok()) ++ " odd_disjoint_runs=" ++ Common.bool_text(odd_disjoint_ok()) ++ " output_parse=" ++ Common.bool_text(parse_correct))
    IO.print("case=" ++ case_name ++ " status=complete merged_entries=" ++ Nat.show(merged_count) ++ " kept_entries=" ++ Nat.show(kept_count) ++ " bloom_force=" ++ Nat.show(bloom_forced) ++ " serialized_bytes=" ++ Nat.show(serialized_bytes))

def main() -> IO(Unit):
  do IO<Unit>:
    entries_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_ENTRIES"))
    dir_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_DIR"))
    +entries : Nat <- IO.pure(Nat, Common.nat_default(Nat.read(entries_env), 4097n))
    +dir : String <- IO.pure(String, Common.env_default(dir_env, ".mylsm-compaction-bench-data"))
    _h0 : Unit <- IO.print("benchmark=compaction bend_version=2.0.35 entries_per_run=" ++ Nat.show(entries))
    _h1 : Unit <- IO.print("output_directory=" ++ dir)
    _c1 : Unit <- run_case(dir, entries, 1n)
    _c4 : Unit <- run_case(dir, entries, 4n)
    run_case(dir, entries, 5n)
