import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM
import ../../src/Fs.bend as Fs
import ../lib/common.bend as Common

# Phase D metrics harness: write loop tracking logical bytes, first/middle/
# last samples, timed recovery, and 101 sampled point reads.

# Write many for the database metrics benchmark.
def written(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>
) -> IO(MyLSM.Utf8.Handle):
  match pair:
    case (handle, Done{_}): IO.pure(MyLSM.Utf8.Handle, handle)
    case (_, Fail{_}): IO.die(MyLSM.Utf8.Handle, 1, "metrics write failed")

# Takes the handle back after a flush or stops the run.
def flushed(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(MyLSM.Utf8.Handle):
  match pair:
    case (handle, Done{Unit{}}): IO.pure(MyLSM.Utf8.Handle, handle)
    case (_, Fail{_}): IO.die(MyLSM.Utf8.Handle, 1, "metrics flush failed")

def flush.due(due: Bool, handle: MyLSM.Utf8.Handle) -> IO(MyLSM.Utf8.Handle):
  match due:
    case False{}: IO.pure(MyLSM.Utf8.Handle, handle)
    case True{}:
      do IO<MyLSM.Utf8.Handle>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.flush(handle)
        flushed(pair)

# Writes key-N=value-N and flushes every 4096 writes.
def write_many(fuel: Nat, +index: Nat, handle: MyLSM.Utf8.Handle) -> IO(MyLSM.Utf8.Handle):
  match fuel:
    case 0n: IO.pure(MyLSM.Utf8.Handle, handle)
    case 1n+rest:
      do IO<MyLSM.Utf8.Handle>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
          MyLSM.Utf8.put(handle, "key-" ++ Nat.show(index), "value-" ++ Nat.show(index))
        next : MyLSM.Utf8.Handle <- written(pair)
        maintained : MyLSM.Utf8.Handle <- flush.due(
          Nat.is_eq(Nat.mod(Nat.add(index, 1n), 4096n), 0n), next)
        write_many(rest, Nat.add(index, 1n), maintained)

# Handle logical go in the database metrics benchmark.
def logical_go(fuel: Nat, +start: Nat, acc: Nat) -> Nat:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      logical_go(f, Nat.add(start, 1n), Nat.add(acc, Nat.add(String.length("key-" ++ Nat.show(start)), String.length("value-" ++ Nat.show(start)))))

def sample.read(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>
) -> MyLSM.Utf8.Handle:
  match pair:
    case (handle, _): handle

# Times 101 point reads spread over the written keys.
def sample_reads(
  +samples: Nat,
  handle: MyLSM.Utf8.Handle,
  +count: Nat,
  acc: List<&2, Nat>
) -> IO(MyLSM.Utf8.Handle & List<&2, Nat>):
  match samples:
    case 0n: IO.pure(MyLSM.Utf8.Handle & List<&2, Nat>, (handle, acc))
    case 1n+rest:
      do IO<MyLSM.Utf8.Handle & List<&2, Nat>>:
        +probe : Nat <- IO.pure(Nat, Nat.div(Nat.mul(count, Nat.sub(101n, samples)), 101n))
        +start : Nat <- IO.now()
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <-
          MyLSM.Utf8.get(handle, "key-" ++ Nat.show(probe))
        +stop : Nat <- IO.now()
        _printed : Unit <- IO.print("sample_ms=" ++ Nat.show(Nat.sub(stop, start)))
        sample_reads(rest, sample.read(pair), count, Con{Nat.sub(stop, start), acc})

# Handle frac pick in the database metrics benchmark.
def frac_pick(small: Bool, +frac: Nat) -> String:
  match small:
    case True{}:
      "0" ++ Nat.show(frac)
    case False{}:
      Nat.show(frac)

# Print ratio for the database metrics benchmark.
def print_ratio(+tag: String, +num: Nat, +den: Nat) -> IO(Unit):
  match den:
    case 0n:
      IO.print(tag ++ "=unknown")
    case 1n+d:
      +scaled = Nat.div(Nat.mul(num, 100n), den)
      +frac = Nat.mod(scaled, 100n)
      IO.print(tag ++ "=" ++ Nat.show(Nat.div(scaled, 100n)) ++ "." ++ frac_pick(Nat.is_le(frac, 9n), frac))

# Bucket order statistics for percentiles (sorting would need mutually
# recursive helpers, which the checker forbids; all shapes here mirror
# proven merge_go/scan_go patterns). Readings above 63 ms clamp.

# Check whether whether buckets holds for the database metrics benchmark.
def empty_buckets(count: Nat, acc: List<&2, List<&2, Nat>>) -> List<&2, List<&2, Nat>>:
  match count:
    case 0n:
      acc
    case 1n+m:
      empty_buckets(m, Con{Nil{}, acc})

# Handle bucket add in the database metrics benchmark.
def bucket_add(+buckets: List<&2, List<&2, Nat>>, ix: Nat, val: Nat) -> List<&2, List<&2, Nat>>:
  match buckets:
    case Nil{}:
      Nil{}
    case Con{+b, t}:
      match ix:
        case 0n:
          Con{Con{val, b}, t}
        case 1n+p:
          Con{b, bucket_add(t, p, val)}

# Handle fill buckets in the database metrics benchmark.
def fill_buckets(+samples: List<&2, Nat>, +buckets: List<&2, List<&2, Nat>>) -> List<&2, List<&2, Nat>>:
  match samples:
    case Nil{}:
      buckets
    case Con{+ms, t}:
      fill_buckets(t, bucket_add(buckets, Nat.min(ms, 63n), ms))

# Concatenate all for the database metrics benchmark.
def concat_all(+buckets: List<&2, List<&2, Nat>>) -> List<&2, Nat>:
  match buckets:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      List.append(&2, Nat, h, concat_all(t))

# Handle nth sorted in the database metrics benchmark.
def nth_sorted(bound: Nat, +ix: Nat, +xs: List<&2, Nat>) -> Nat:
  match bound ix xs:
    case 0n _ _:
      0n
    case 1n+f _ Nil{}:
      0n
    case 1n+f 0n Con{h, t}:
      h
    case 1n+f 1n+p Con{h, t}:
      nth_sorted(f, p, t)

# Byte accounting over the data dir (replaces shell wc).

# Select size for the database metrics benchmark.
def pick_size(tbl: Bool, size: Nat) -> Nat:
  match tbl:
    case True{}:
      size
    case False{}:
      0n

# Handle sum go in the database metrics benchmark.
def sum_go(names: List<&1, String>, +dir: String, acc: Nat) -> IO(Nat):
  match names:
    case Nil{}:
      IO.pure(Nat, acc)
    case Con{+h, t}:
      do IO<Nat>:
        size : Nat <- IO.try(Nat, Fs.file_size(dir ++ "/" ++ h))
        sum_go(t, dir, Nat.add(acc, pick_size(String.starts_with(h, "SST."), size)))

# Sums the sizes of every SST file in the database directory.
def table_bytes(+dir: String) -> IO(Nat):
  do IO<Nat>:
    names : List<&1, String> <- IO.try(List<&1, String>, Fs.read_dir(dir))
    sum_go(names, dir, 0n)

# Return the size of if in the database metrics benchmark.
def size_if(present: Bool, +dir: String, +file: String) -> IO(Nat):
  match present:
    case False{}:
      IO.pure(Nat, 0n)
    case True{}:
      do IO<Nat>:
        size : Nat <- IO.try(Nat, Fs.file_size(dir ++ "/" ++ file))
        IO.pure(Nat, size)

# Handle file bytes in the database metrics benchmark.
def file_bytes(+dir: String, +file: String) -> IO(Nat):
  do IO<Nat>:
    present : Bool <- IO.try(Bool, Fs.exists(dir ++ "/" ++ file))
    size_if(present, dir, file)

# Takes the opened handle or stops the run.
def opened(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{handle}: IO.pure(MyLSM.Utf8.Handle, handle)
    case Fail{_}: IO.die(MyLSM.Utf8.Handle, 1, "metrics database open failed")

# Closes the handle and keeps the read samples.
def closed(pair: MyLSM.Utf8.Handle & List<&2, Nat>) -> IO(List<&2, Nat>):
  match pair:
    case (handle, samples):
      do IO<List<&2, Nat>>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        return samples

# Prints the sample verdict for one phase.
def verdict(phase: String, pair: MyLSM.Utf8.Handle & Bool) -> IO(MyLSM.Utf8.Handle):
  match pair:
    case (handle, ok):
      do IO<MyLSM.Utf8.Handle>:
        _printed : Unit <- IO.print("phase=" ++ phase ++ " samples=" ++ Common.bool_text(ok))
        return handle

def main() -> IO(Unit):
  do IO<Unit>:
    count_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_WRITES"))
    dir_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_DIR"))
    +count : Nat <- IO.pure(Nat, Common.nat_default(Nat.read(count_env), 20485n))
    +dir : String <- IO.pure(String, Common.env_default(dir_env, ".mylsm-phase3-metrics-data"))
    created : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.create(dir)
    handle : MyLSM.Utf8.Handle <- opened(created)
    +t0 : Nat <- IO.now()
    completed : MyLSM.Utf8.Handle <- write_many(count, 0n, handle)
    +t1 : Nat <- IO.now()
    +logical : Nat <- IO.pure(Nat, logical_go(count, 0n, 0n))
    _u0 : Unit <- IO.print("metric_writes_completed=" ++ Nat.show(count))
    _u1 : Unit <- IO.print("metric_elapsed_ms=" ++ Nat.show(Nat.sub(t1, t0)))
    _u2 : Unit <- IO.print("metric_logical_bytes=" ++ Nat.show(logical))
    before : MyLSM.Utf8.Handle & Bool <- Common.samples(completed, count)
    checked : MyLSM.Utf8.Handle <- verdict("pre_recovery", before)
    _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(checked)
    +r0 : Nat <- IO.now()
    existing : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.open_existing(dir)
    reopened : MyLSM.Utf8.Handle <- opened(existing)
    +r1 : Nat <- IO.now()
    _u4 : Unit <- IO.print("metric_recovery_ms=" ++ Nat.show(Nat.sub(r1, r0)))
    after : MyLSM.Utf8.Handle & Bool <- Common.samples(reopened, count)
    rechecked : MyLSM.Utf8.Handle <- verdict("post_recovery", after)
    read : MyLSM.Utf8.Handle & List<&2, Nat> <- sample_reads(101n, rechecked, count, Nil{})
    +samples : List<&2, Nat> <- closed(read)
    +ordered : List<&2, Nat> <- IO.pure(List<&2, Nat>, concat_all(fill_buckets(samples, empty_buckets(64n, Nil{}))))
    +olen : Nat <- IO.pure(Nat, List.length(&2, Nat, ordered))
    _u6 : Unit <- IO.print("metric_p50_read_ms=" ++ Nat.show(nth_sorted(olen, 50n, ordered)))
    _u7 : Unit <- IO.print("metric_p95_read_ms=" ++ Nat.show(nth_sorted(olen, 95n, ordered)))
    _u8 : Unit <- IO.print("metric_p99_read_ms=" ++ Nat.show(nth_sorted(olen, 99n, ordered)))
    _u9 : Unit <- IO.print("metric_read_samples=" ++ Nat.show(olen))
    +wal : Nat <- file_bytes(dir, "WAL")
    +mfst : Nat <- file_bytes(dir, "MANIFEST")
    +tables : Nat <- table_bytes(dir)
    _u10 : Unit <- IO.print("metric_wal_bytes=" ++ Nat.show(wal))
    _u11 : Unit <- IO.print("metric_manifest_bytes=" ++ Nat.show(mfst))
    _u12 : Unit <- IO.print("metric_table_bytes=" ++ Nat.show(tables))
    _u13 : Unit <- print_ratio("metric_write_amplification", Nat.add(wal, Nat.add(mfst, tables)), logical)
    _u14 : Unit <- print_ratio("throughput_ops_per_sec", Nat.mul(count, 1000n), Nat.sub(t1, t0))
    IO.print("metrics_harness=complete")
