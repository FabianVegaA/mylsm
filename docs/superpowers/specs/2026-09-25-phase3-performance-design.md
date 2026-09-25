# Phase 3 — Competitive Storage Performance — Design Spec

**Date:** 2026-09-25
**Status:** Draft, pending human review
**Scope:** Single spec + single plan covering all four slices in order **A → B → D → C**
**Execution approach:** Approach 2 (skeleton-first): one structural commit fixing all A+B types/APIs with old logic delegating, then logic fill per phase, each gated.
**Related:** `docs/superpowers/specs/2026-09-24-bend-hub-refactor-design.md`, `docs/superpowers/plans/2026-09-24-bend-hub-refactor.md`, `README.md` (Phase 3 checklist), `bench/BASELINE.md`

## 1. Mission

Remove the known algorithmic and IO bottlenecks before any cross-database comparison, in slice order: **A** reads (block index, block-oriented reads, live Bloom, block cache, measured Bloom tuning), **B** writes (grouped commits, configurable batching, active+frozen MemTables, background flush/compaction), **D** measurement (write amplification, recovery time, memory, latency percentiles, throughput, RocksDB/LevelDB/Pebble recipe), **C** GPU (`!` on chunked Bloom and block digests, CPU/GPU agreement laws).

Decisions (2026-09-25): single spec+plan; order A→B→D→C; skeleton-first execution; hub proofs trusted, ours cover glue only; bench gate from the refactor still holds (no measured win → revert).

**Custom-code precedence (normative):** community packages are the default, not the mandate. If measurement shows custom code beats the hub module (throughput, proof burden, or fit), the custom code stays: keep it and record the numbers in the commit message when the verdict is clear-cut; escalate to the user when it is a close call or a direction change (e.g. dropping an adoption the spec planned). The refactor already set this precedent twice (balanced merge kept over hub tree/heap, prepend-log kept over `HashMap`).

**No retrocompatibility (normative):** no database, file, or wire format is preserved across any phase. `Tbl` gains fields, checksums may change mode (C2 tree-hash), Manifest naming may change, staged-batch framing may change. No migration code, no legacy readers, no version dispatch — the V1 deletion (2026-09-24) is the precedent. Every phase's bench runs on fresh directories.

## 2. Skeleton (structural commit, no behavior change)

One commit fixing every A+B interface; all bodies delegate to current logic; gate is `--check-only` + `./proofs/run.sh` green.

- `Sstable.Tbl` gains two `Data` fields: `chunks: List<&2, List<&2, Entry>>` (entries in ≤64-entry blocks, ascending) and `blocks: List<&2, String>` (first key per chunk, ascending). `entries` is kept so `table_entries` and its consumers (`Db.all_entries`, `Compact.table_runs`) are untouched. Rationale: `List` has no O(1) indexing, so binary search over a flat list is theater; stored chunks give O(#chunks) pointer hops plus a ≤64 bounded scan, cutting `String.cmp` per lookup from N to N/64+64. Builders (`build`/`from_sorted_unique`/`build_sorted`) fill all three representations at build time (one O(N) chunking). Match sites: 6 in `src/Sstable.bend` + `Db.bend:59`.
- `Db.Db` gains `frozen: MemTable.MemTable` (drained-by-flush staging, empty until phase B) and `batch_cap: Nat` (grouped-commit bound, phase B). `open_db` initializes `frozen` empty and a default `batch_cap`; every `Db{...}` constructor (write path, flush, compact, recover, fixture laws) is updated mechanically.
- `Wal` gains `stage(+staged: List<&2, Batch>, +b: Batch) -> List<&2, Batch>` (pure accumulation, no IO). Grouped commit reuses the existing single-`wal_append`+fsync `db_write`: N stages + 1 fsync.
- No behavior change, no new laws; the name-gate (`run.sh` 1:1 laws↔proofs) stays green by construction.

## 3. Phase A — Reads

- `block_get(table, k)`: linear scan over `blocks` to select the chunk, bounded (≤64) scan inside; `lookup` becomes a one-line delegate. New laws: `block_get == lookup` on fixtures + open-input statement the checker admits, witnessed in `proofs/SstableProof.bend`.
- `db_get` redesign (the measured bottleneck: today it concats mem + all tables then linear-scans): per-source newest-first search — mem, frozen, L0 newest-first, L1+ — consulting `maybe_present` Bloom prefilter per table before `block_get`. First match wins **including tombstones**. Laws pin newest-wins + tombstone-hides on fixtures (same properties the facade README proves today); equivalence with the old concat-scan is asserted on closed fixtures only (checker-heavy open induction is out of scope; runtime million-writes samples cover it).
- Block cache: `Db` gains `bcache: List<&2, BEntry>` with `BEntry{name: String, key: String, val: Maybe<&2, String>}` (table name from Manifest naming, bounded FIFO at 256 entries, pure `Data`, no threading redesign). Law: cached read == uncached read. Measured; reverted if the workload shows no win (sequential-write workloads will show none — the gate workload must include point-read locality).
- Bloom tuning measured: harness counts observed false positives over a workload sample at current `bloom_bits` schedule vs candidate schedules; `bloom_bits` changes only with data. No Dayan-exact promise — Monkey schedule stays unless measurement says otherwise.

## 4. Phase B — Writes

- Grouped commits: app/REPL path stages up to `batch_cap` batches via `Wal.stage`, then one `db_write` (one `wal_append` + one fsync). Law: staged-then-write == sequential writes (the existing `Db` batch-fold property, cited not re-proved).
- Active/frozen: writes go to `mem`; at the 4096 cap, `mem` rotates into `frozen` (instead of blocking) and a fresh `mem` opens; flush drains `frozen`. Reads search mem then frozen (phase A path covers it). Laws: rotation preserves newest-wins; flush-pre/post `db_get` agreement (extends existing `laws/Flush.bend` properties).
- Flush/compaction "background": honest scope — Bend pure code has no OS threads, so true background IO needs host-effect work (out of scope). What lands here: non-blocking writer rotation above + disjoint-range compaction parallelism via parallel-let (already the pattern in `merge_round`). Documented as such; no thread claims.
- `batch_cap` configurable through `bin/mylsm` env (`MYLSM_BATCH_CAP`, default preserves current single-batch behavior).

## 5. Phase D — Measurement

- New `bench/phase3_metrics.bend` harness reporting, on the million-writes workload shape: write amplification (bytes appended to WAL + tables + Manifest ÷ logical key/value bytes), recovery time (reopen + sample verify, ms), peak memory note (host-measured, not Bend-proved), read/write latency percentiles (p50/p95/p99 via `IO.now` around sampled ops), throughput (ops/s, existing formula).
- Methodology (from `bench/BASELINE.md`, normative): dataset > RAM, same machine/disk/tuning, ≥3 clean runs + median before replacing any frozen observation. Comparison_invalid rules (disk <15%) apply.
- RocksDB/LevelDB/Pebble: no Bend bindings are built. D ships a deterministic op-log export of the workload (key sequence, sizes, mix) plus a recipe to replay it under each engine's stock bench tool (`db_bench` et al.) with matching key distribution; the comparison table is filled manually. Promising automation here would be dishonest — the deliverable is reproducible method + our numbers.

## 6. Phase C — GPU

- C1 Bloom parallel: `bloom_of` over `Tbl.chunks` with parallel-let per chunk + `!` on the chunk hash-set call; `Sstable.bloom_of_seq` kept as reference; law `bloom_chunked == bloom_seq` (CPU/GPU agreement, the `worker_gpu_agrees` pattern in `laws/Demo.bend` extended to production); bench decides `!` vs CPU-parallel vs sequential per machine (unified-memory Metal vs CUDA differ — no portable claim).
- C2 SHA tree-hash: evaluated with a spike gate (the Task-5 precedent). The hub `sha256` is sequential Merkle–Damgård; block-parallel digest means tree-hash = new checksum format + new laws. If the spike shows no win on the available GPU, C2 becomes a documented no-op.
- `merge_round` stays CPU: divergent `String.cmp` branching, guide-backed (`bend guide`: divergent work stays faster on CPU). No `!` there, documented why.
- `!` never changes semantics: every GPU call site ships a CPU-agreement law. Artifact gating follows `bin/mylsm` (`--gpu` fails closed without a `.gpu` artifact).

## 8. Community packages (robust ones first, spike-gated)

Already adopted (2026-09-24 refactor): `sha256` (v2 checksum), `bitset` word fns (`word_get`/`word_put`), `math/pow2t`. The affinity rule governs everything below (`Type`-sorted hub state can only be used ephemerally inside functions or via pure fns — never stored in our `Data` types, never dropped). Each candidate gets a spike gate: no clean shape or no measured win → documented no-op, same as refactor Tasks 5–6.

- **Phase A: `lru.bend` block cache — evaluate.** The spec's §3 `BEntry` assoc-list is the fallback. LRU proper needs the threaded-cache redesign (cache handed back on every read, like `HashMap.get`): `db_get` would return `Db & Maybe`, rippling to `sget_go`, facade, app, and agreement laws. Spike first: if the threading ripple exceeds the measured gain over the assoc-list, keep the assoc-list and record why.
- **Phase B: `priority_queue.bend` run selection — evaluate, ephemeral.** Compaction picks which runs to merge (few tables, tiny N): build the queue, drain fully inside the picker, no stored state. Expect small win; keep only with bench evidence. `queue`/`deque` for batch staging: rejected upfront — a pure `List` fold is equivalent and storable in `Data`.
- **Phase C2: `keccak`/`blake3` as tree-hash leaves — spike options.** If the SHA tree-hash spike proceeds, these are alternative leaf digests (both FIPS/RFC-proven upstream); pick by measured digest throughput on the target GPU, not by preference.
- **Phase D: none.** The metrics harness and op-log export are bespoke; no community package fits.
- **Rejected upfront:** `hash_table` (MemTable stays prepend-log, affinity), `Bitset` as Bloom storage (affinity), `balanced_search_tree`/`binary_heap` for sort/merge (same complexity class, Task-5 finding), `dynamic_array` as `Table` storage (affinity).

## 9. Gates and risks

- Per-phase gate (same as the refactor): `bend --check-only`, targeted `bend proofs/<X>Proof.bend`, `./proofs/run.sh` green (31 modules baseline; count grows only with new law files), `bench/fuzz.bend` clean, bench before/after vs `bench/BASELINE.md`, commit per phase. Regression → revert the phase.
- No `@unsafe` in laws/witnesses/adapted code; C/JS effects stay minimal host ops; open theorems vs closed fixtures distinguished (AGENT.md, unchanged).
- Risks: `Db` constructor ripple (every `Db{...}` site incl. fixture laws — mechanical but wide; the skeleton commit isolates it); `db_get` redesign touching `Flush`/`Compact`/`Recover` agreement laws (one module at a time, targeted proofs first); D numbers incomparable across machines (methodology section is normative, not advisory); C gains not portable across GPU vendors (reported per-machine, never claimed generally).
