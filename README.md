# MyLSM

MyLSM is an experimental durable LSM key-value store implemented in Bend 2. It
combines a write-ahead log, MemTable, SSTables, Bloom filters, tiered compaction,
recovery, and machine-checked laws for parts of the pure storage core.

> **Current status:** useful developer prototype and research project. It is not
> yet a production-ready replacement for RocksDB, LevelDB, or Pebble.

## Quick start

Requirements: Bend 2.0.35 or newer. The 0.4.0.0 source and proof gates are
validated with Bend 2.0.35.

```sh
# Inspect available CPU/GPU/native capabilities
bin/mylsm doctor

# Run the durable demonstration
bin/mylsm demo

# Run the proof gate
bin/mylsm check

# Run smoke fuzzing and the benchmark harness
bin/mylsm fuzz
bin/mylsm bench
```

The demo writes and reads two keys, deletes one key, verifies the tombstone, and
runs a small pure worker using Bend's GPU-call syntax. Storage IO always remains
on the CPU. See `app/README.md` for details.

## Use as a library (Bend hub)

Paste the import; the compiler fetches the package from the hub into
`~/.bend/lib`, verifies it against its hash, and runs offline afterwards:

```bend
import mylsm-lsm-store@0.4.0.0/mylsm.bend as MyLSM
```

`MyLSM.open(dir)` creates an empty in-memory handle. To recover a persisted
database from that directory, call `MyLSM.open_recovering(dir)`; it returns an
`IO(Result<&1, &1, U32 & String, Db.Db>)` and reads the Manifest, SSTables, and
WAL through the filesystem effects.

Level 1 is a session monad — no manual handle threading. Steps share one
quantity (`&2`); `v : T <- …` binds a result, bare `sput(…)` is a Unit step,
`return` wraps the answer:

```bend
import Base
import mylsm-lsm-store@0.4.0.0/mylsm.bend as MyLSM

def show(m: Maybe<&2, String>) -> U32:
  match m:
    case Some{v}: 1
    case None{}: 0

# A session describes steps; `run_sess` executes them.
def session() -> MyLSM.Sess<&2, Maybe<&2, String>>:
  do MyLSM.Sess<&2, Maybe<&2, String>>:
    MyLSM.sput("hello", "world")
    MyLSM.sput("answer", "42")
    MyLSM.sdel("hello")
    v : Maybe<&2, String> <- MyLSM.sget("answer")
    return v

def main() -> U32:
  db = MyLSM.open("/scratch")
  result = MyLSM.run_sess(&2, Maybe<&2, String>, db, session())
  show(MyLSM.value_of(&2, Maybe<&2, String>, result))
```

Level 2 exposes the parts directly (ordered-map core, key ordering, codecs,
tables, manifests) without a session. Reads are newest-first with
tombstones included, so the newest write wins and a delete hides every older
version — this snippet proves both in one run:

```bend
import Base
import mylsm-lsm-store@0.4.0.0/mylsm.bend as MyLSM

def bit(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

def is_present(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{v}: True{}
    case None{}: False{}

def is_missing(m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}: True{}
    case Some{v}: False{}

def main() -> U32:
  live = MyLSM.mem_put(MyLSM.mem_put(MyLSM.mem_empty(), "k", "v1"), "k", "v2")
  gone = MyLSM.mem_del(MyLSM.mem_empty(), "k")
  bit(Bool.and(is_present(MyLSM.mem_get(live, "k")), is_missing(MyLSM.mem_get(gone, "k"))))
```

Pure and in-memory; durability (`bin/mylsm demo`) stays in this repo. See
`docs/superpowers/specs/2026-09-22-mylsm-hub-facade-design.md` for the full
API (both levels, error policy, fetch semantics).

## Runtime modes

Select execution with environment variables:

```sh
MYLSM_DEVICE=auto bin/mylsm demo
MYLSM_DEVICE=cpu MYLSM_THREADS=8 bin/mylsm demo
MYLSM_DEVICE=gpu MYLSM_GPU_MEMORY=4GB bin/mylsm demo
```

`auto` prefers a verified native GPU artifact, then native CPU using detected
logical cores, and finally the portable Bend backend. GPU mode applies only to
suitable pure compute; WAL, fsync, Manifest, SSTable IO, and recovery stay on
CPU.

## Building native binaries (per architecture)

```sh
bin/mylsm doctor   # check Bend, clang, GPU caps
bin/mylsm build    # bend app/mylsm_demo.bend -o .mylsm/build/mylsm-demo
bin/mylsm run      # native binary, or portable fallback
```

Binaries are host-native (`arm64`/`x86_64`, macOS/Linux): build on the
target machine, there is no cross-compile flag. GPU (Metal / CUDA +
`nvidia-smi`) is also decided at build time — without a `.gpu` artifact,
`gpu` mode fails closed. Threads and GPU memory reach the binary as
`--threads N` (1..256, default: logical CPUs) and `--gpu SIZE`, via
`MYLSM_THREADS` / `MYLSM_GPU_MEMORY`. Storage IO always stays on CPU; only
pure `!` workers are GPU-eligible.

If `build` fails, read `.mylsm/build/mylsm-demo-build.log`. On macOS,
Homebrew `llvm@19` breaks Bend's Metal prelude — use Apple clang instead
(Bend respects `CC`):

```sh
export CC=/usr/bin/clang
bin/mylsm build
```

Without a native binary, `demo` and `repl` use Bend's portable CPU backend.

## Correctness status

The modular proof suite contains witnesses for key storage transitions, codecs,
flush, compaction, recovery, and CPU/GPU worker agreement. Run
`./proofs/run.sh` for the bounded parallel proof gate, or target an individual
`proofs/*Proof.bend` module while developing. The current suite passes all 22
isolated modules on Bend 2.0.35 with no failures or
timeouts. A timeout is not a passing proof. Closed fixtures provide concrete
executable evidence, but some general open-input properties and all host IO
behavior still require stronger proofs or empirical validation.

Bend 2.0.35's `--verdict` currently fails with a mismatch between its
TypeScript implementation and the formalized BendTT kernel. The passing module
checks therefore do not establish independent kernel validation.

## Packed storage 0.4.0.0

Version 0.4.0.0 stores checksummed binary SST blocks, WAL frames, and a binary
Manifest. Its disk format is incompatible with earlier releases. Back up and
remove existing database directories before opening them with this version;
there is no compatibility reader or migration tool.

Five-run Darwin arm64 benchmarks passed the elapsed-time and peak-memory gates
for 4,097 writes, 20,485 writes, 1,000,000 writes, and compaction. The 1M
median fell from 252,254 ms to 156,931 ms, while peak RSS fell from
2,502,393,856 to 942,784,512 bytes. The complete measurements and raw-sample
links are in [the 0.4.0.0 benchmark report](bench/results/packed-storage-0.4.0.0.md).

## Crash recovery testing

On Darwin and Linux, run the deterministic external-crash matrix with:

```sh
MYLSM_CRASH_RESET=1 bench/fault_inject.sh .mylsm-crash-injection
```

The default executes ten WAL, flush, compaction, and Manifest publication
checkpoints three times. Bend owns environment lookup and activation policy;
the proof suite includes an open unset theorem plus closed mismatch/exact fixtures.
The minimal host effect emits a marker and sends the worker `SIGSTOP`.
The Bash harness verifies the marker and stopped state, sends external
`kill -9`, requires signal-derived status 137, and reopens the database twice to
verify every acknowledged deterministic key/value and the expected level shape.

The harness accepts only repository-local `.mylsm-crash-*` output roots, requires
an ownership sentinel before reset deletion, and preserves diagnostics when a
case fails. Darwin and Linux are supported; other platforms fail closed. This matrix
is empirical evidence for the audited host effects, operating system, filesystem,
and hardware used by the run. It is not a Bend proof of signal delivery,
`fsync`, rename atomicity, process death, or storage durability.

## Roadmap

### Phase 1 — Useful developer product

Goal: make MyLSM practical to explore and operate locally.

- [x] Durable put/get/delete demonstration.
- [x] Adaptive CPU/GPU launcher and capability diagnostics.
- [x] Proof, fuzz, and benchmark CLI commands.
- [x] Interactive REPL with `put`, `get`, `del`, `help`, and `exit`.
- [x] REPL commands for `scan`, `stats`, `flush`, `compact`, and `maintain`.
- [x] `timing on|off|once` and `time <command>`.
- [x] Runtime commands for `mode auto|cpu|gpu`, `compute`, and runtime status.
- [x] Controlled native restart when changing thread count.
- [x] Quoted keys and values with deterministic checksummed import/export.

Exit criteria:

- The REPL can execute a documented session against a persistent directory.
- Restarting the REPL recovers every acknowledged write.
- CPU/GPU selection and timing output identify exactly what was measured.

### Phase 2 — Reliability and adversarial hardening

Goal: survive corruption, crashes, and resource pressure predictably.

- [x] Replace the current fault-injection scaffold with real `kill -9` phases.
- [x] Test crashes during WAL append, flush, compaction, and Manifest publish.
- [x] Run 1M+ mutated inputs through WAL, Manifest, and SSTable parsers.
      (`workload/fuzz.bend`: 1,000,000 decided, 0 traps, fixed seed.)
- [x] Test truncated files, invalid checksums, missing tables, and hostile names.
      (`workload/fuzz_grammar.bend`: 708 directed cases on verdict.)
- [x] Test disk-full and permission-denied behavior.
      (`crash/diskfull.sh`: ENOSPC and all four permission cases fail closed
      and recover with acknowledged data intact.)
- [x] Run repeated write/crash/recover cycles and compare acknowledged state.
      (200-case matrix with ack journals, zero mismatches; overnight recipe
      in `crash/soak_overnight.md`.)
- [x] Verify memory remains bounded under sustained write pressure.
      (5×20k soak stable ±20%; growth ~3 KB/key linear, `stats` budgets.)
- [ ] Strengthen open-input laws where Bend automation permits.
      (Two attempts verdict-kept-closed with reasons recorded; open
      decidability laws already cover all decoders.)

Exit criteria:

- No acknowledged write is lost in the crash matrix.
- Corrupt or missing Manifest-listed data always fails closed.
- Fuzzing and restart soak tests complete without crashes or unbounded memory.

### Phase 3 — Competitive storage performance

Goal: remove known algorithmic and IO bottlenecks before making comparisons.

- [x] Replace linear SSTable lookup with sparse block indexes and binary search.
      (Stored 64-entry chunks with bounded scans; binary search is N/A over
      `List` without O(1) indexing — see the Phase 3 spec.)
- [x] Replace quadratic table construction with balanced sorted-run construction.
- [ ] Add block-oriented reads instead of whole-file reads.
- [x] Add block cache and measured Bloom-filter tuning.
- [x] Add real grouped commits and configurable batching.
- [x] Maintain active and frozen MemTables concurrently.
- [x] Run flush and disjoint-range compaction in the background.
      (Non-blocking writer rotation plus parallel-let over disjoint ranges;
      no OS threads — pure Bend has none. See the Phase 3 spec.)
- [ ] Parallelize Bloom construction and independent compaction ranges.
      (Compaction ranges parallelized; chunked Bloom measured slower than
      sequential at production table sizes, GPU flat — builders stay
      sequential. See `bench/bloom_par.bend`.)
- [x] Measure write amplification, recovery time, memory, latency percentiles,
      and throughput.
- [ ] Compare identical workloads against RocksDB, LevelDB, and Pebble.
      (Deterministic recipe in `bench/op_log.md`; no runs yet.)

Exit criteria:

- Benchmarks are reproducible and include machine, disk, dataset, and tuning.
- Datasets exceed available RAM.
- MyLSM reaches an explicitly recorded performance target without weakening
  durability or proof gates.

### Phase 4 — Production readiness

Goal: provide a stable, operable database rather than a standalone experiment.

- [ ] Stable embedded API and versioned on-disk format.
- [ ] Multi-client concurrency and snapshot semantics.
- [ ] Streaming scans and bounded iterators.
- [ ] Backup, restore, inspection, and repair tooling.
- [ ] Metrics for WAL, cache, flush, compaction, stalls, and errors.
- [ ] Format migration and compatibility tests.
- [ ] Supported-platform matrix for macOS Metal, Linux CUDA, and CPU fallback.
- [ ] Security review, operational documentation, and release process.

Exit criteria:

- Compatibility, recovery, and migration suites pass across supported releases.
- Operators can diagnose, back up, restore, and repair a database.
- Performance and reliability claims are backed by published evidence.

## Near-term priority

The next highest-value work is randomized parser hardening, disk-full behavior,
and repeated crash/recovery soak testing. GPU optimization should remain secondary to
SSTable layout, batching, background maintenance, and IO behavior because those
areas dominate LSM database performance.

## Design documents

- `docs/superpowers/specs/2026-09-17-lsm-bend-design.md`
- `docs/superpowers/specs/2026-09-18-cli-demo-runtime-design.md`
- `docs/superpowers/plans/2026-09-17-lsm-bend.md`
- `docs/superpowers/plans/2026-09-18-cli-demo-runtime.md`
- `docs/superpowers/plans/2026-09-18-phase-1-developer-product.md`
- `docs/superpowers/plans/2026-09-21-real-crash-injection.md`
