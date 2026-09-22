# MyLSM

MyLSM is an experimental durable LSM key-value store implemented in Bend 2. It
combines a write-ahead log, MemTable, SSTables, Bloom filters, tiered compaction,
recovery, and machine-checked laws for parts of the pure storage core.

> **Current status:** useful developer prototype and research project. It is not
> yet a production-ready replacement for RocksDB, LevelDB, or Pebble.

## Quick start

Requirements: Bend 2.0.4 or newer. Bend 2.0.13 was used for the latest
SSTable v2 development and million-write validation.

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

```sh
# Paste the import; the compiler fetches and verifies the hash.
```

```bend
import 0x05fa0e42448e8e221df592b204de523d/mylsm.bend as MyLSM
```

Level 1 (Sess session, primary): `do MyLSM.Sess<…>:` with
`MyLSM.sput/sdel/sbatch/sget`, run via `MyLSM.run_sess` over `MyLSM.open`.
Level 2 (parts): `MyLSM.cmp/eq/mem_*/sst_*/wal_*/mfst_*/sort_newest/range_scan`.
Pure and in-memory; durability (`bin/mylsm demo`) stays in this repo.

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

## Correctness status

The modular proof suite contains witnesses for key storage transitions, codecs,
flush, compaction, recovery, and CPU/GPU worker agreement. Run
`./proofs/run.sh` for the bounded parallel proof gate, or target an individual
`proofs/*Proof.bend` module while developing. The crash-injection development
baseline passed all 34 isolated modules on Bend 2.0.24 with no failures or
timeouts. A timeout is not a passing proof. Closed fixtures provide concrete
executable evidence, but some general open-input properties and all host IO
behavior still require stronger proofs or empirical validation.

## Compaction performance status

The current development tree uses balanced stable sorted-run merging for
MemTable canonicalization and compaction, indexed BitTree Bloom filters, cached
SSTable range metadata, conservative tombstone retention, and compact decimal
table generations with legacy-name recovery. The first-compaction workload
(20,485 durable writes) improved from a timeout beyond 30 minutes to 4.524
seconds on the development M1, but that run had only 2% free disk and is not a
publishable comparison. See `bench/BASELINE.md`.

The SSTable v2 acceptance run completed 1,000,000 durable writes and post-restart
first/middle/last-key verification in 1,087.20 seconds on Bend 2.0.13. Its main
L1 table was 29,175,202 bytes versus 103,339,329 bytes for the equivalent legacy
v1 table. MyLSM still needs block-oriented lookups, bounded multi-output
publication and stronger general proofs before making competitive or production
claims.

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
- [ ] Run 1M+ mutated inputs through WAL, Manifest, and SSTable parsers.
- [ ] Test truncated files, invalid checksums, missing tables, and hostile names.
- [ ] Test disk-full and permission-denied behavior.
- [ ] Run repeated write/crash/recover cycles and compare acknowledged state.
- [ ] Verify memory remains bounded under sustained write pressure.
- [ ] Strengthen open-input laws where Bend automation permits.

Exit criteria:

- No acknowledged write is lost in the crash matrix.
- Corrupt or missing Manifest-listed data always fails closed.
- Fuzzing and restart soak tests complete without crashes or unbounded memory.

### Phase 3 — Competitive storage performance

Goal: remove known algorithmic and IO bottlenecks before making comparisons.

- [ ] Replace linear SSTable lookup with sparse block indexes and binary search.
- [x] Replace quadratic table construction with balanced sorted-run construction.
- [ ] Add block-oriented reads instead of whole-file reads.
- [ ] Add block cache and measured Bloom-filter tuning.
- [ ] Add real grouped commits and configurable batching.
- [ ] Maintain active and frozen MemTables concurrently.
- [ ] Run flush and disjoint-range compaction in the background.
- [ ] Parallelize Bloom construction and independent compaction ranges.
- [ ] Measure write amplification, recovery time, memory, latency percentiles,
      and throughput.
- [ ] Compare identical workloads against RocksDB, LevelDB, and Pebble.

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
