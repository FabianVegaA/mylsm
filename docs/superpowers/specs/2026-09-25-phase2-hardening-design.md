# Phase 2 — Reliability and Adversarial Hardening — Design Spec

**Date:** 2026-09-25
**Status:** Draft, pending human review
**Scope:** Single spec + single plan: bench/ refactor (slice 0) then
hardening slices A → B → C → D, sequential with gates.
**Supersedes:** `2026-09-25-bench-layout-design.md` (folded in as slice 0).
**Related:** `bench/BASELINE.md`, `bench/fault_inject.sh`,
`bench/fuzz.bend`, `AGENT.md` (bolt gate).

## 1. Mission and decisions

Finish README Phase 2's open items (parser fuzz at scale, adversarial
inputs, disk-full/permissions, crash soak, bounded memory, stronger
open-input laws) against its exit criteria: no acknowledged write lost in
the crash matrix; corrupt or missing Manifest-listed data always fails
closed; fuzzing and restart soak complete without crashes or unbounded
memory. Single spec+plan, sequential gates (approach 1, approved).
Decisions: hybrid grammar+blind fuzz; ramdisk-full plus chmod-based
permissions; memory gate = soak stability (C) + growth observation (B)
with per-component budgets inspired by RocksDB/LevelDB/Pebble; soak =
extended matrix now + overnight recipe; custom code wins ties on
measurement (standing rule); no retrocompat constraints carried over
(formats may change if hardening requires it, with laws updated).

## 2. Slice 0 — bench/ refactor (approved structure)

```
bench/
  README.md          # map of what to run when (new, one page)
  BASELINE.md        # unchanged observations
  op_log.md          # unchanged cross-engine recipe
  lib/
    common.bend      # env_default, nat_default, bool_text, samples_ok,
                     # mem/frozen/level counts, print_shape (deduped from 5)
    run.sh           # data-dir guards, 15% disk gate + override, thread
                     # detection, native build, run with env, result logs
  smoke/             # fast checks (<30s): bench, effs, console,
                     # crash_point bends, cli.sh, crash_point_overhead.sh,
                     # crash_point_smoke.sh
  workload/          # durable benchmarks: million_writes (.bend+.sh),
                     # phase3_metrics (.bend+.sh), compaction_bench,
                     # compaction_regression.sh, bloom_tune.bend,
                     # fuzz.bend, fuzz_grammar.bend (new, slice A)
  crash/             # fault_inject.sh, crash_worker.bend
  flame/             # unchanged
```

Rename-only moves; moved `.bend` files re-point imports (`../../src/`,
`../lib/common.bend`) and drop local helper copies; moved `.sh` files
source `../lib/run.sh` and keep only post-processing; `bin/mylsm` updates
the `fuzz` and `bench` command paths. Dead code in `bench/` MAY be deleted:
unreachable helpers, harness logic superseded by `lib/`, one-off scripts
with no gate or documentation pointing at them. Deletion is per-file
explicit in the plan with its reason; anything with a live caller or a
BASELINE.md reference stays. Gates: per-file `--check-only`,
smokes run, `bash -n` + small-count run per script, bolt zero-new-findings,
final `./proofs/run.sh` sanity (no src/laws/proofs edits expected).

## 3. Slice A — fuzz + adversarial (hybrid)

**Grammar-directed corpus** (`workload/fuzz_grammar.bend`, new), one
generator per format, each case carrying its expected verdict
(`Some`/`Done` accept, `None`/`Fail` reject — never trap):
- WAL: valid frames, length/value mismatches, broken chk4, truncation at
  every byte offset, hostile bytes in keys/values;
- Manifest: valid levels, hostile names (`../`, empty, 4 GiB, non-UTF8),
  absurd generations, missing trailing newline;
- S2 tables: out-of-range level/count, invalid tags, over-limit lengths,
  broken SHA hex, truncation at each framing boundary (`S2;`, entries,
  `#`, checksum).
**Blind volume** (extends `workload/fuzz.bend`): fixed-seed PRNG over the
directed corpus — bit flips, random truncations, swaps, cross-format
splices — to 1M+ inputs counting `decided` vs `trap`; one trap blocks.
Seed and counts in the log for bit-identical reproduction.
**Laws**: extend `is_decided`/totality coverage to every new generator;
any totality gap found becomes law + witness before leaving the slice.
**Gate A**: 1M+ decided, 0 traps, directed corpus 100% on expected
verdict, proofs green.

## 4. Slice B — crash soak (matrix now, overnight recipe)

**Extended matrix** (`crash/fault_inject.sh`): 20–30 cycles per checkpoint
(WAL append, flush, compaction, Manifest publish) over ~50k writes with the
acknowledged state journaled; post-recovery comparison automatic and
blocking. Reuses the existing external `kill -9` + reopen-twice harness
discipline.
**Overnight soak recipe** (documented, manual): hundreds of cycles over a
rotating key set, acknowledged-state + level-shape + RSS sampled per
cycle; script plus runbook; results appended to `BASELINE.md`, never a
release gate.
**Gate B**: zero acknowledged writes lost across the matrix.

## 5. Slice C — resources and memory (budgets, not magic numbers)

**Disk-full (real ramdisk)**: N-MB volume (`hdiutil` macOS / `tmpfs`
Linux), writes to `ENOSPC`; every failure closed (no half-acknowledged
writes, no corrupt Manifest); after freeing space the DB reopens healthy.
Requires mount privileges and careful cleanup — documented prerequisites.
**Permissions**: `chmod`/`chown` over WAL, tables, Manifest plus read-only
directories at the same checkpoints; fail-closed everywhere.
**Memory budgets per component** (RocksDB/LevelDB/Pebble model — every
piece carries an explicit cap, no global magic number):
- active + frozen MemTables: 4096 entries each, exact counts (already
  structural);
- `bcache`: 256 entries with FIFO trim (already structural);
- open tables: KNOWN GAP — today fully materialized; measure and document
  per-table cost, do not claim a bound that does not exist (feeds the
  future block-disk-reads cycle);
- WAL replay buffers and compaction working sets: measured, bounded by
  input sizes;
- HVM runtime overhead: observed only (2.7 GB max RSS for ~22 MB logical
  on record), reported, not budgeted.
`stats` surfaces the counters; the soak asserts RSS stability across
cycles (±margin) and records the growth ratio 100k/500k/1M.
**Gate C**: soak RSS stable + adversarial resource cases fail closed.

## 6. Slice D — open-input laws (where automation permits)

Strengthen quantifiers over pure decoders and totality claims opened by
slices A–C. Where the checker normalizes, open theorems; where it
diverges, closed fixtures explicitly documented as such (never forced).
**Gate D**: `./proofs/run.sh` green at the updated module count.

## 7. Cross-cutting gates and risks

- Every slice ends with: targeted `bend proofs/*Proof.bend`, full
  `./proofs/run.sh`, `bench/fuzz.bend` CLEAN, bolt under the AGENT.md gate
  (S001 parked, S002 filtered, S003 over 200 chars), bench evidence where
  measurable. Regression → revert the slice.
- No `@unsafe` in laws/witnesses; open theorems vs closed fixtures
  distinguished; trust-root comments preserved.
- Risks: ramdisk needs privileges (documented, skippable per-machine with
  the run marked non-comparable); 1M-fuzz wall time (native binary
  required, portable backend too slow — same constraint as ever);
  adversarial corpus may find real decoder bugs (that is the point; fix +
  law + re-run inside slice A); overnight soak is manual by design.
