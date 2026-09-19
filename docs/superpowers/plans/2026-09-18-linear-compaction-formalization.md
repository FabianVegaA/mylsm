# Linear Compaction and Complete Pure-Core Formalization Plan

> **For agentic workers:** follow `AGENT.md`. Run `bend guide` before Bend work,
> keep every load-bearing pure rule in `laws/*.bend`, add its witness to
> `proofs/*Proof.bend`, run `./proofs/run.sh` before every commit, and parallelize only
> independent work with disjoint write sets. Do not use `@unsafe`.

**Goal:** replace the current quadratic compaction pipeline with a sorted-run
merge pipeline, remove the linked-list Bloom bottleneck, bound output table
sizes, and mechanize the complete pure-core correctness argument needed to show
that compaction preserves point reads, scans, newest-version precedence,
tombstones, ordering, uniqueness, and Bloom safety.

**Observed baseline:** on the development M1 with eight logical CPUs, 4,096
durable writes completed in 568 ms of Bend-measured write time, while the
1,000,000-write run did not complete within 30 minutes. `Recover.needs_flush_cap`
triggers only when `count > 4096`, so a full current L0 table contains 4,097
entries and the fifth-table compaction trigger occurs at 20,485 writes. The
stalled directory contained five L0 tables, confirming a measured compaction
cliff at or immediately after that threshold.

**Primary causes in the current code:**

1. `Sstable.build_go` constructs a run by repeated sorted insertion: `O(N²)`.
2. `Compact.finish_go` calls `Sstable.build_go`, then `Sstable.build` sorts the
   already sorted result again.
3. Bloom bits are represented as `List<Bool>`; each random `bit_set` and
   `bit_get` is linear in the bit index. Bloom construction is on the measured
   write/compaction path; Bloom lookup is not yet wired into `Db.db_get` and must
   be benchmarked separately rather than credited for write-path gains.
4. `Compact.last_go` reverses all table entries to obtain the largest key.
5. Tombstone shadow checks scan all lower entries once per tombstone.
6. Compaction materializes all input entries and one complete serialized output.

**Non-goals for this plan:**

- No weakening of WAL, file, directory, or Manifest sync ordering.
- No GPU claim for string merge or storage IO.
- No background compaction before the synchronous algorithm is correct and fast.
- No production-readiness claim based only on the benchmark.
- No proof claim over the operating system, filesystem, foreign effects, or
  crash timing. Those remain empirical fault-injection obligations.

## Completion contract

The work is complete only when all of the following are true:

- The compaction merge never calls insertion sort on already sorted SSTables.
- Compaction merge complexity is `O(N log K)` for `K` input runs, or documented
  `O(NK)` with a measured small fixed `K` only as an intermediate checkpoint.
- Bloom construction and lookup no longer perform linear linked-list indexing.
- SSTables carry cached `smallest`, `largest`, and `count` metadata.
- Tombstone shadow checks are linear merges over sorted runs.
- Output tables are bounded and pairwise range-disjoint.
- Existing on-disk files remain readable, or a versioned migration is provided.
- Every pure correctness claim in the formalization matrix below has a law in
  `laws/*.bend` and a checking witness in `proofs/*Proof.bend`.
- `./proofs/run.sh`, `bend bench/fuzz.bend`, `bench/cli_smoke.sh`, compaction
  differential tests, and crash tests all pass.
- The 20,485-write cliff is eliminated and the 1,000,000-write benchmark
  completes within the initial 30-minute gate on the same machine and disk
  class, with exact machine state recorded.

---

## Architecture decision

### Sorted-run merge

Every SSTable entry list is already sorted and unique. Compaction must preserve
that representation and merge runs directly:

```text
merge_newer(newer, older)
  LT -> emit newer head
  EQ -> emit newer head and consume both heads
  GT -> emit older head
```

The left run is always newer. The `EQ` branch is therefore the only place where
version precedence is decided. Tombstones are entries and follow the same
newest-wins rule.

L0 has explicit chronological newest-first precedence. L1 is required to be
pairwise key-range-disjoint, so relative age between valid L1 tables is
semantically irrelevant. Multi-run merge therefore proceeds in two stages:

```text
[L0 newest ... L0 oldest] -> balanced stable merge -> merged L0
[absorbed disjoint L1 runs] -> balanced range merge -> merged L1
merged L0 (newer) + merged L1 (older) -> stable merge -> output
```

Each L0 partial merge carries its precedence interval, and balancing must never
swap an older interval to the left of a newer interval. L1 merging must prove or
validate pairwise disjointness; duplicate keys across distinct L1 tables are a
malformed-state test, not an ordering rule silently invented by compaction.

### Immutable indexed Bloom tree

Replace `List<Bool>` with a fixed-depth tree of `U32` words:

```python
type BitTree is Data:
  BitLeaf{word: U32}
  BitBranch{left: BitTree, right: BitTree}

type Bloom is Data:
  Blm{root: BitTree, words: Nat, bits: Nat, capacity_words: Nat}
```

A hash position is split into `word_index = position / 32` and
`bit_index = position % 32`. Tree lookup and update are `O(log capacity_words)`;
bit selection inside a leaf uses U32 shifts and masks. `capacity_words` is the
next power-of-two leaf capacity, `words <= capacity_words`, and padded leaves are
never addressable by a valid bit position. The zero-bit case receives a
canonical one-leaf representation and always returns `False` before modulo.

This representation is intentionally pure and persistent. Parallel Bloom
construction is deferred until the sequential tree implementation and its laws
are green.

### Cached table metadata

Use this logical shape:

```python
type Table is Data:
  Tbl{
    entries: List<&2, MemTable.Entry>,
    filter: Bloom,
    nbits: Nat,
    smallest: Maybe<&2, String>,
    largest: Maybe<&2, String>,
    count: Nat
  }
```

The metadata is derived once from the canonical sorted run and need not be
stored on disk initially. Existing v1 SSTable payloads are **raw MemTable
entries**, potentially unsorted and duplicated, because `Flush.flush_pre`
serializes `entries` rather than `Db.table_entries(tbl)`. Therefore v1 parsing
must continue through canonicalizing `Sstable.build`; it must not call
`from_sorted_unique` directly. A later v2 codec may mark canonical sorted
payloads and parse them through the fast constructor. The parser must distinguish
v1 and v2 explicitly; validation alone must never assume legacy payload order.

### Bounded outputs

A pure partitioner splits a sorted unique merged run into chunks of at most
`target_entries`. Each chunk becomes one SSTable. Because input ordering is
strict, adjacent non-empty chunks are range-disjoint by construction.

The initial target is 16,384 entries. It is configuration data, not a semantic
constant, and must be benchmarked before becoming a stable format policy.

---

## Formalization boundary

“Complete formalization” in this plan means complete mechanization of the pure
compaction core and its observable model. It does **not** mean proving external
host behavior that Bend does not model.

### Mechanized in Bend

- sorted-run merge behavior;
- strict ordering and uniqueness of generated runs;
- newest-run precedence on duplicate keys;
- point-resolution equivalence before and after merge;
- scan equivalence before and after merge;
- tombstone preservation and safe shadow dropping;
- Bloom no-false-negative behavior for inserted keys;
- table metadata correctness;
- partition completeness, order, size bound, and disjointness;
- pure compaction preservation, L0 drain, closure absorption, and no-op gate;
- CPU/parallel pure-worker agreement if parallel workers are introduced.

### Verified empirically, not called formally proven

- append, `fsync`, rename, directory sync, and deletion behavior;
- atomic Manifest visibility under host crashes;
- behavior under `kill -9`, disk full, permissions, and filesystem corruption;
- scheduler fairness and actual parallel hardware utilization;
- wall-clock complexity and throughput.

The documentation and final release notes must preserve this boundary.

### Current implementation status (2026-09-18)

The linear merge, balanced MemTable canonicalization, indexed Bloom storage,
cached metadata, conservative tombstone retention, compact decimal filenames,
and closed regression fixtures are implemented. Exact Manifest drift detection
is also implemented by threading the serialized Manifest token through `Db`.

This milestone remains incomplete: production compaction still publishes one
output SSTable rather than partitioning into multiple target-sized SSTables, and
the quantified ordering/merge/compaction theorems in the matrix below have not
all been accepted by Bend 2.0.9. Existing closed fixtures must not be described
as substitutes for those general theorems.

---

## Formalization matrix

Each row requires: a named pure helper, a law in `laws/*.bend`, a same-name witness
in `proofs/*Proof.bend`, and at least one non-vacuous closed fixture. Laws marked general
must quantify arbitrary inputs under explicit well-formedness preconditions;
closed normalization fixtures supplement those theorems but never replace them.
If the installed Bend checker cannot accept a required general theorem, document
the exact blocker and leave this milestone incomplete or formally revise its
scope. Do not silently downgrade “complete formalization” to fixture-backed
validation.

| ID | Law | Required statement |
| --- | --- | --- |
| K1 | `key_cmp_refl` | For every String key, comparison with itself is `EQ`. |
| K2 | `key_cmp_eq_iff` | For arbitrary keys, `cmp(a,b) == EQ` iff key equality is true. |
| K3 | `key_cmp_reverse` | For arbitrary keys, reversing `cmp(a,b)` equals `cmp(b,a)`. |
| K4 | `key_lt_transitive` | For arbitrary `a,b,c`, `a < b` and `b < c` imply `a < c`. |
| K5 | `key_le_transitive` | For arbitrary `a,b,c`, `a <= b` and `b <= c` imply `a <= c`. |
| K6 | `key_trichotomy` | Exactly one of LT, EQ, or GT classifies every arbitrary key pair consistently with equality. |
| R1 | `run_merge_empty_left` | Merging empty newer run returns older run. |
| R2 | `run_merge_empty_right` | Merging empty older run returns newer run. |
| R3 | `run_merge_lt` | Lower newer head is emitted first. |
| R4 | `run_merge_eq_newer` | Equal keys emit exactly the newer entry. |
| R5 | `run_merge_gt` | Lower older head is emitted first. |
| R6 | `run_merge_sorted` | For arbitrary sorted inputs, output is sorted. |
| R7 | `run_merge_unique` | For arbitrary sorted unique inputs, output is unique. |
| R8 | `run_merge_resolve` | For arbitrary well-formed inputs and key, resolution equals newest-first input resolution. |
| R9 | `run_merge_scan` | For arbitrary well-formed inputs and bounds, scan equals the reference scan. |
| R10 | `run_merge_many_order` | For arbitrary well-formed L0 runs, balanced merge equals newest-first resolution. |
| R11 | `l1_disjoint_valid` | Valid L1 tables are pairwise range-disjoint; malformed duplicates are rejected. |
| R12 | `merge_fuel_complete` | Fuel `len(left)+len(right)+1` cannot truncate a two-run merge. |
| B0 | `bloom_well_formed` | Allocated capacity, logical words, bits, and padded leaves are consistent. |
| B1 | `bit_set_hit` | Setting an in-bounds bit makes that bit observable. |
| B2 | `bit_set_other` | Setting one bit preserves a distinct bit. |
| B3 | `bloom_add_hit` | A key added to a Bloom filter tests as maybe present. |
| B4 | `bloom_fold_safe` | Every key folded into a Bloom filter has no false negative. |
| B5 | `bloom_schedule_unchanged` | Existing per-level bit-budget policy is preserved. |
| M1 | `table_count_exact` | Cached count equals entry-list length. |
| M2 | `table_smallest_exact` | Cached smallest equals first key or `None`. |
| M3 | `table_largest_exact` | Cached largest equals final key or `None`. |
| M4 | `table_overlap_equiv` | For every table built by any constructor/parser path, metadata overlap equals reference entry-range overlap. |
| M5 | `legacy_canonicalize` | Parsing/canonicalizing arbitrary valid v1 payloads yields a sorted unique table with reference-equivalent resolution. |
| T1 | `shadow_live_kept` | Live entries are never removed by tombstone cleanup. |
| T2 | `shadow_tombstone_kept` | Tombstone remains when key exists below. |
| T3 | `shadow_tombstone_drop` | Tombstone drops only when no lower resurrection is possible under the selected policy. |
| T4 | `shadow_resolve_preserve` | Shadow cleanup preserves observable resolution. |
| P1 | `partition_concat` | Concatenating chunks reconstructs the input run. |
| P2 | `partition_bound` | Every chunk length is at most target. |
| P3 | `partition_ordered` | Every chunk remains sorted and unique. |
| P4 | `partition_disjoint` | Adjacent non-empty chunks have disjoint ranges. |
| C1 | `compact_linear_live` | New compaction output equals the expected live fixture. |
| C2 | `compact_linear_get` | Point reads are preserved for hit, tombstone, and miss fixtures. |
| C3 | `compact_linear_scan` | Range scans are preserved across representative boundaries. |
| C4 | `compact_linear_drain` | Triggered compaction drains all selected L0 inputs. |
| C5 | `compact_linear_closure` | Every overlapping L1 table is absorbed to closure. |
| C6 | `compact_linear_remainder` | Non-overlapping L1 tables remain unchanged. |
| C7 | `compact_linear_noop` | At or below threshold, levels are unchanged. |
| C8 | `compact_linear_idempotent` | Reapplying pure compaction below the next trigger is observationally idempotent. |
| C9 | `compact_old_new_agree` | During migration, corrected reference and new pure compaction agree on fixtures. |
| C10 | `closure_complete` | Under pairwise-disjoint L1 preconditions, closure absorbs every and only hull-overlapping table. |
| C11 | `compact_observational` | For arbitrary well-formed levels and key/range, compacted point/scan resolution equals the reference model. |
| N1 | `output_names_unique` | Multi-output generation assigns unique accepted names and advances the counter by output count. |
| N2 | `counter_restore_all_levels` | Recovery restores a counter greater than every listed/output generation across all levels. |
| A1 | `partition_worker_agrees` | Parallel pure partition worker equals CPU reference. |

Existing laws `compact_disjoint`, `compact_absorbed`, `compact_hit`,
`compact_preserve`, `compact_miss`, and `compact_noop` remain as regression
anchors until replacements pass. The existing `compact_live` fixture is not a
valid anchor unchanged: it drops tombstone `x` while L2 still contains
`x=vold`, permitting resurrection. Correct that fixture and add a pinned read of
`x` before switching any production compaction path. Preserve the old behavior
only under an explicitly named `legacy_buggy_reference` used to demonstrate the
regression, never as the semantic oracle.

---

## Task 0: Freeze the measured regression and protect user data

**Files:**

- Keep: `bench/million_writes.bend`
- Keep: `bench/million_writes.sh`
- Modify: `.gitignore`
- Modify: `bench/BASELINE.md`
- Create: `bench/compaction_bench.bend`
- Create: `bench/compaction_regression.sh`

### Steps

1. Record Bend version, OS, architecture, logical CPUs, free disk, write count,
   table threshold, MemTable cap, and exact commit in every result.
2. Refuse to benchmark with less than 15% free disk unless
   `MYLSM_BENCH_ALLOW_LOW_DISK=1` is set. Low-disk results must be marked invalid
   for comparison.
3. Add a pure compaction benchmark that constructs 1, 4, and 5 sorted 4,097-entry
   runs without WAL or `fsync`, so merge cost is isolated from storage latency.
4. Time these phases independently: run merge, tombstone processing, Bloom
   construction, serialization, output write, and Manifest publication.
5. Add timeout gates:
   - 4,096 durable writes complete without flush;
   - 4,097 durable writes cross one flush;
   - 20,485 durable writes cross the first compaction trigger;
   - pure five-run compaction completes;
   - failure prints the last completed phase.
6. Preserve benchmark data only under an explicit output directory. Never delete
   an arbitrary path without the existing reset opt-in.

### Validation

```sh
bash -n bench/million_writes.sh
bash -n bench/compaction_regression.sh
MYLSM_BENCH_RESET=1 bench/million_writes.sh 4097 .mylsm-compaction-baseline
bench/compaction_regression.sh baseline
./proofs/run.sh
```

### Checkpoint

```sh
git add .gitignore bench/million_writes.bend bench/million_writes.sh bench/compaction_bench.bend bench/compaction_regression.sh bench/BASELINE.md
git commit -m "bench: capture the compaction performance cliff"
```

---

## Task 1: Add reference predicates and models before optimization

**Files:**

- Modify: `src/Keys.bend`
- Create: `src/SortedRun.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`

### Foundational key-order API and laws

Before defining sorted-run correctness, add pure predicates/helpers for `LT`,
`LE`, Cmp reversal, implication, and one-hot classification in `src/Keys.bend`.
State K1–K6 as general laws over arbitrary Strings and implement explicit
structural witnesses through String/Char/U32/Word comparison where normalization
is insufficient. Existing `str_refl` may discharge K1, but closed examples such
as `"a" < "b"` do not satisfy K2–K6.

These laws are the foundation for strict ordering, range disjointness, hull
closure, scan bounds, and observational preservation. Task 2 is blocked until
K1–K6 check. If the installed Bend checker cannot express or verify them, record
the exact limitation and leave “complete pure-core formalization” incomplete;
do not model independent arbitrary `Cmp` values as if they formed a coherent
String order.

### Required reference-model API

```python
def is_strict(entries: List<&2, MemTable.Entry>) -> Bool
def is_unique(entries: List<&2, MemTable.Entry>) -> Bool
def resolve(entries: List<&2, MemTable.Entry>, key: String) -> Maybe<&2, Maybe<&2, String>>
def resolve_newest(runs: List<&2, List<&2, MemTable.Entry>>, key: String) -> Maybe<&2, Maybe<&2, String>>
def reference_scan(runs: List<&2, List<&2, MemTable.Entry>>, lo: String, hi: String) -> List<&2, MemTable.Entry>
def runs_well_formed(runs: List<&2, List<&2, MemTable.Entry>>) -> Bool
def level_disjoint(tables: List<&2, Sstable.Table>) -> Bool
def lower_shadow_complete(levels: List<&2, List<&2, Sstable.Table>>, target: Nat) -> Bool
```

`resolve` returns an outer `Maybe` for key presence and an inner `Maybe` for a
live value versus tombstone. This prevents “absent” and “deleted” from collapsing
inside preservation proofs.

### Steps

1. Prove K1–K6 in `Keys.bend`/`laws/*.bend`/`proofs/*Proof.bend`, including empty,
   prefix-related, unequal-length, differing-character, and Unicode-scalar
   structural branches.
2. Implement validators with structural or fuel-bounded recursion.
3. Implement a deliberately simple newest-first reference resolver independent
   of the optimized merge.
4. Implement a reference scan using the existing trusted behavior only for the
   model, not from the new merge under test.
5. Define explicit well-formedness predicates: every run strict/unique, L1+
   pairwise range-disjoint, chronological L0 order represented by list position,
   and lower shadow equal to all levels strictly below the target.
6. Port existing compaction fixtures to model-level fixtures.
7. Add non-vacuity laws showing one hit, one tombstone, one miss, and one bounded
   scan before adding preservation equalities.
8. Add `{==}` witnesses in `proofs/*Proof.bend` where normalization closes the law; use
   explicit structural witness recursion otherwise.

### Gate

```sh
./proofs/run.sh
```

Do not implement the optimized merge until the reference model is green.

### Checkpoint

```sh
git add src/Keys.bend src/SortedRun.bend LAWS../proofs/run.sh
git commit -m "proof: define compaction reference semantics"
```

---

## Task 2: Implement stable two-run linear merge

**Files:**

- Modify: `src/SortedRun.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`
- Create: `bench/sorted_run_smoke.bend`

### Required API

```python
def merge_newer(
  newer: List<&2, MemTable.Entry>,
  older: List<&2, MemTable.Entry>
) -> List<&2, MemTable.Entry>
```

### Bend implementation constraints

- Use explicit fuel `len(newer) + len(older) + 1`. Each recursive step consumes
  one fuel unit and at least one input head; prove R12 so fuel exhaustion cannot
  truncate a valid merge. This avoids relying on Bend accepting alternating
  structural decrease across two parameters.
- No `List.append` in the hot recursive step.
- Build a reverse accumulator and reverse once, or use a continuation only if
  the generated native benchmark proves it does not allocate excessively.
- Match the `Cmp` result in leaf helpers so affine Strings and Entries are used
  exactly once.
- `EQ` emits the newer entry and consumes both heads.
- Tombstones are not dropped by this function.
- No Bloom, table, IO, or Manifest behavior belongs in this module.

### Proof-first sequence

1. Add R1–R5 as closed branch laws.
2. Implement `merge_newer` until R1–R5 normalize.
3. Add `is_strict` and `is_unique` postcondition fixtures.
4. Add R8 and R9 anti-vacuity fixtures for live, overwritten, deleted, and
   missing keys.
5. Prove general R6–R9 and R12 under explicit `is_strict`/`is_unique`
   preconditions, using fuel induction and factored `LT/EQ/GT` step lemmas.
6. If String comparison blocks a theorem, record the exact checker failure and
   keep the task incomplete; closed branch fixtures and differential tests remain
   useful evidence but do not satisfy the formalization gate.
7. Differential-test random small sorted runs against the reference model.

### Gate

```sh
bend bench/sorted_run_smoke.bend
./proofs/run.sh
```

### Checkpoint

```sh
git add src/SortedRun.bend bench/sorted_run_smoke.bend LAWS../proofs/run.sh
git commit -m "feat: add proven linear sorted-run merge"
```

---

## Task 3: Implement precedence-preserving balanced multi-run merge

**Files:**

- Modify: `src/SortedRun.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`
- Modify: `bench/sorted_run_smoke.bend`

### Required API

```python
def merge_many_newest(
  runs: List<&2, List<&2, MemTable.Entry>>
) -> List<&2, MemTable.Entry>
```

### Design

Represent each work item with an age interval:

```python
type RunGroup is Data:
  RunGroup{
    newest_rank: Nat,
    oldest_rank: Nat,
    entries: List<&2, MemTable.Entry>
  }
```

Only adjacent L0 age intervals may merge. The group with the lower/newer rank is
always passed as the left argument to `merge_newer`. Pairwise rounds use explicit
round fuel `len(groups) + 1`; each round helper structurally consumes its input
list, and R10/R12-style laws show the bounded rounds reach one group. An odd
final group advances unchanged. Absorbed L1 tables use a separate disjoint-run
merge whose validator rejects overlapping or duplicate ranges; no chronological
L1 precedence is assumed.

### Required proofs

- Adjacent interval merge preserves age ordering.
- R10: for arbitrary well-formed L0 runs and keys, balanced result equals the
  newest-first reference resolver.
- Duplicate keys spanning three or more runs select the newest value.
- A tombstone in the newest run hides values in every older run.
- Empty runs do not change results.

### Complexity gate

Benchmark at least five geometrically increasing sizes after one warmup, run
three measured repetitions per size, and compare medians with fixture
construction excluded. Reject an implementation whose fitted/scaling ratios are
consistent with quadratic growth. Keep raw timings in `bench/results/`, but do
not commit machine noise unless updating an explicit baseline record.

### Checkpoint

```sh
git add src/SortedRun.bend bench/sorted_run_smoke.bend LAWS../proofs/run.sh
git commit -m "feat: merge sorted runs with stable precedence"
```

---

## Task 4: Replace linked-list Bloom indexing

**Files:**

- Modify: `src/Sstable.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`
- Create: `bench/bloom_bench.bend`

### Steps

1. Define `bloom_well_formed` over logical bits, logical words, power-of-two
   capacity, tree depth, and padded leaves. Implement `BitTree` allocation by
   word count with structurally decreasing depth/fuel.
2. Implement `bit_word`, `bit_mask`, `tree_set`, and `tree_test`.
3. Preserve the existing two hash seeds and `bloom_bits` schedule so this task
   changes representation, not policy.
4. Implement `bloom_add` and `bloom_of` over the tree.
5. Add B0–B5, including capacity coverage, padded-leaf rejection, collisions,
   first bit, last in-bounds bit, empty filter, same-position updates, and
   distinct-bit preservation fixtures.
6. Add a no-false-negative differential corpus for 1, 32, 33, 4,097, and 20,485
   inserted keys.
7. Benchmark build and lookup separately. Attribute write/compaction improvement
   only to build; current `Db.db_get` does not consult Bloom. Record lookup and
   false-positive results as readiness data for a later read-path integration,
   but do not tune bit budgets in this task.

### Required safety details

- Never shift by 32 or more.
- Never modulo by zero.
- Out-of-range tree paths fail closed as `False`.
- A malformed parsed table must not be accepted merely because a reconstructed
  Bloom filter is well formed.

### Gate

```sh
bend bench/bloom_bench.bend
./proofs/run.sh
```

### Checkpoint

```sh
git add src/Sstable.bend bench/bloom_bench.bend LAWS../proofs/run.sh
git commit -m "perf: replace linear Bloom bit indexing"
```

---

## Task 5: Add sorted constructor and cached metadata

**Files:**

- Modify: `src/Sstable.bend`
- Modify: `src/SstFile.bend`
- Modify: `src/Db.bend`
- Modify: `src/Flush.bend`
- Modify: `src/Recover.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`

### Required APIs

```python
def from_sorted_unique(
  entries: List<&2, MemTable.Entry>,
  level: Nat
) -> Table

def table_smallest(table: Table) -> Maybe<&2, String>
def table_largest(table: Table) -> Maybe<&2, String>
def table_count(table: Table) -> Nat
```

### Steps

1. Extend `Table` with `smallest`, `largest`, and `count`.
2. Implement one-pass metadata derivation over a sorted list; do not reverse the
   list to obtain `largest`.
3. Implement `from_sorted_unique` without calling `build_go`.
4. Keep `Sstable.build` temporarily for unsorted MemTable inputs.
5. Keep v1 parsing through canonicalizing `Sstable.build`, then derive metadata
   from that canonical result. Do not pass raw v1 entries to
   `from_sorted_unique`.
6. Add a v1 fixture containing unsorted duplicate keys and prove M5: parse/build
   preserves newest-first resolution while producing a sorted unique table.
7. Change `table_overlap` to use cached bounds.
8. At recovery, validate every L1+ level as pairwise range-disjoint after all
   listed tables load and before constructing `Db.Db`. Reject overlaps and
   duplicate cross-table keys fail-closed. Pure compaction may assume only this
   validated invariant; malformed-state fixtures must prove rejection.
9. Add M1–M5 and R11, and prove metadata well-formedness for `build`, v1 parse,
   and `from_sorted_unique` separately.
10. Update every `Tbl{...}` match project-wide in one mechanical pass.
11. Keep the existing on-disk codec version in this task; canonical v2 output is
    introduced only in Task 11 with explicit version dispatch.

### Gate

```sh
./proofs/run.sh
bend bench/fuzz.bend
bench/cli_smoke.sh
```

### Checkpoint

```sh
git add src/Sstable.bend src/SstFile.bend src/Db.bend src/Flush.bend src/Recover.bend LAWS../proofs/run.sh
git commit -m "feat: add linear SSTable construction and metadata"
```

---

## Task 6: Correct tombstone safety and replace compaction core

**Files:**

- Modify: `src/Compact.bend`
- Modify: `src/MergeIter.bend`
- Modify: `src/Manifest.bend`
- Modify: `src/Recover.bend`
- Modify: `bench/fault_inject.sh`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`
- Modify: `bench/compaction_bench.bend`

### Steps

1. Before optimizing, correct the current anti-resurrection bug: retain a
   tombstone when its key may exist in any strictly lower level; drop it only
   when closure/disjointness proves no older value can become visible.
2. Correct the existing `compact_live` fixture, pin `get("x") == None` before and
   after compaction, and add T1–T4 anti-resurrection laws. The production path
   must not advance until these pass.
3. Preserve the corrected implementation as `compact_levels_reference`. Keep the
   old inverted behavior only as `legacy_buggy_reference` in a regression that
   demonstrates resurrection; never use it as an oracle.
4. Preserve chronological newest-first order for L0. Validate/prove absorbed L1
   pairwise range disjointness and merge L1 without assigning fictional ages.
5. Replace `tables_entries -> Sstable.build_go` with sorted runs passed through
   the separate L0-precedence and L1-disjoint merge stages.
6. Merge the resulting L0 run as newer than the merged absorbed-L1 run.
7. Remove the second sort by constructing output with
   `Sstable.from_sorted_unique`.
8. Keep tombstones through run merge and apply the corrected safe-drop policy
   afterward.
9. Replace implicit `hd_tbl` output selection with an explicit pure compaction
   plan carrying `outputs`, untouched `remainder`, and selected input names.
   Zero output is a first-class case; never fabricate an empty table or relabel
   the first remainder table as output.
10. Before production switch, implement zero-output publication: exact drift
    check, publish a Manifest removing selected inputs and adding no output,
    sync it durably, then remove old inputs. Fault-inject before/after Manifest
    publication and each deletion. Retaining old tombstones temporarily is
    allowed, but no checkpoint may expose unsafe dropping through one-output IO.
11. Add C1–C11 and zero-output laws/tests before production calls the new
    implementation.
12. Update `MergeIter.merge` only when its source ordering/preconditions are
    explicit and its arbitrary-key/range agreement laws pass.
13. Remove dead quadratic helpers only after project-wide grep proves no caller.

### Mandatory fixtures

- duplicate live key across all five L0 tables;
- newest tombstone over older L0 and L1 values;
- older tombstone overridden by newer live value;
- widening overlap closure across multiple L1 tables;
- non-overlapping remainder before and after the compacted range;
- empty L1 and empty lower levels;
- an all-tombstone compaction producing zero output without consuming remainder;
- lower-level shadow that requires retaining a tombstone;
- hit, miss, lower bound, upper bound, and empty range scans.

### Gate

```sh
./proofs/run.sh
bend bench/compaction_bench.bend
bench/compaction_regression.sh linear-core
bench/fault_inject.sh zero-output
```

The five-run pure compaction must complete within the regression timeout before
continuing.

### Checkpoint

```sh
git add src/Compact.bend src/MergeIter.bend src/Manifest.bend src/Recover.bend bench/compaction_bench.bend bench/fault_inject.sh LAWS../proofs/run.sh
git commit -m "perf: compact SSTables with linear sorted-run merges"
```

---

## Task 7: Make the corrected tombstone policy linear

**Files:**

- Modify: `src/SortedRun.bend`
- Modify: `src/Compact.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`

### Required API

```python
def drop_safe_tombstones(
  compacted: List<&2, MemTable.Entry>,
  lower: List<&2, MemTable.Entry>
) -> List<&2, MemTable.Entry>
```

### Policy clarification

A tombstone may be dropped only when the implementation can prove that no older
value can become visible. For the current policy, retain a tombstone when its key
exists in any strictly lower level; dropping when a lower value exists would
resurrect that value. If the current code or comments state the opposite, fix the
policy and add a regression fixture before optimization.

### Steps

1. Merge lower-level sorted runs once.
2. Walk compacted and lower entries together by key.
3. Always emit live compacted entries.
4. For tombstones, apply the clarified safe-drop rule.
5. Never call linear `member` for each tombstone.
6. Preserve the already-correct Task 6 policy exactly; this task changes only
   complexity.
7. Prove general T1–T4 under sorted/unique and complete-lower-shadow
   preconditions, plus explicit anti-resurrection fixtures.
8. Compare arbitrary-key resolution through the new walk with the corrected
   reference resolver.

### Gate

```sh
./proofs/run.sh
bend bench/compaction_bench.bend
```

### Checkpoint

```sh
git add src/SortedRun.bend src/Compact.bend LAWS../proofs/run.sh
git commit -m "perf: process compacted tombstones linearly"
```

---

## Task 8: Prove bounded output partitioning in a test-only path

**Files:**

- Modify: `src/SortedRun.bend`
- Modify: `src/Compact.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`

### Required API

```python
def partition(
  target: Nat,
  entries: List<&2, MemTable.Entry>
) -> List<&2, List<&2, MemTable.Entry>>
```

### Steps

1. Reject or canonicalize `target = 0` explicitly; never recurse without
   progress.
2. Split in one pass without repeated `List.length` on the remaining tail.
3. Build each non-empty chunk with `from_sorted_unique`.
4. Build a test-only pure partitioned compaction result. Do not connect it to
   production `compact`, Manifest construction, or IO yet: the current IO path
   writes exactly one output and would misclassify later partitions as remainder.
5. Add P1–P4 and extend C1–C11 to zero-, one-, and many-output pure results.
6. Keep partitions sequential in this task; no parallel call yet.
7. Leave production on the proven zero-or-one-output linear path until Task 9
   can publish many outputs atomically.

### Gate

```sh
./proofs/run.sh
bend bench/fuzz.bend
bench/compaction_regression.sh partitioned-pure
```

### Checkpoint policy

Do not create a production integration commit here. The pure test-only
partitioner may be committed only if no production call site can reach it;
otherwise keep Tasks 8 and 9 in one working-tree change and checkpoint only
after the Task 9 crash gate.

---

## Task 9: Integrate and publish multiple outputs atomically

**Files:**

- Modify: `src/Compact.bend`
- Modify: `src/Manifest.bend`
- Modify: `src/Recover.bend`
- Modify: `src/Flush.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`
- Modify: `bench/fault_inject.sh`
- Create: `bench/compact_crash_oracle.bend`
- Modify: `docs/superpowers/specs/2026-09-17-lsm-bend-design.md`

### Naming and concurrency rules

- Allocate one generation counter per output. For output ordinal `i`, use the
  existing accepted dash-shaped name for `flushed + i`; advance `flushed` by the
  exact output count. Zero-output compaction consumes no output generation.
- Extend recovery counter restoration to inspect every level, not only L0, and
  return one greater than the maximum listed/accepted generation.
- Add N1 and N2 for unique names, accepted shapes, multi-output increments,
  zero-output behavior, and restart restoration.
- Before publication, compare exact selected input names and the exact expected
  Manifest snapshot, not only L0/L1 lengths.
- This plan retains the current single-process/no-concurrent-writer model during
  one compaction transaction. Background/concurrent compaction requires a later
  ownership/CAS design; fixed `MANIFEST.tmp` is not concurrency-safe.

### Required IO order

1. Write every output to a unique `.tmp` file.
2. `fsync` every completed output file.
3. Rename every output into its final name.
4. `fsync` the output directory.
5. Reload the Manifest and require exact equality with the snapshot/input-name
   set from which compaction was planned; abort fail-closed on any difference.
6. Write and `fsync` `MANIFEST.tmp` containing all outputs and no removed inputs.
7. Rename Manifest and `fsync` the database directory.
8. Remove old inputs; failures create harmless orphans, never missing live data.
9. Recovery ignores unlisted outputs and fails closed for listed missing/corrupt
   outputs.

### Crash matrix

Inject `kill -9` after each individual output write, file sync, rename, each
aggregate numbered stage, Manifest temp write/sync/rename, and each individual
input deletion. Assert:

- before Manifest publication: old inputs remain authoritative;
- after Manifest publication: all new outputs are authoritative;
- no state exposes only a subset of required inputs or outputs;
- recovery point reads and scans equal the acknowledged oracle;
- repeated recovery is idempotent.

These are empirical crash tests, not Bend proofs over host IO.

### Gate

```sh
bench/fault_inject.sh
./proofs/run.sh
bench/cli_smoke.sh
```

### Checkpoint

```sh
git add src/SortedRun.bend src/Compact.bend src/Manifest.bend src/Recover.bend src/Flush.bend bench/fault_inject.sh bench/compact_crash_oracle.bend LAWS../proofs/run.sh docs/superpowers/specs/2026-09-17-lsm-bend-design.md
git commit -m "test: harden multi-output compaction publication"
```

---

## Task 10: Add pure range parallelism after correctness

**Files:**

- Modify: `src/SortedRun.bend`
- Modify: `src/Compact.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`
- Modify: `bench/compaction_bench.bend`

### Rules

- CPU fork-join uses the installed Bend version's parallel-let syntax over a
  statically balanced recursive split; it does not use `!`.
- A separate `!` entry point is GPU-specific and remains disabled unless a
  native GPU benchmark proves a gain and CPU/GPU agreement is checked.
- File reads, writes, `fsync`, rename, Manifest publication, and cleanup remain
  CPU/IO operations.
- Partition boundaries are computed before dispatch.
- No key may occur in two workers; duplicate resolution happens before or at a
  uniquely owned boundary.
- CPU is the default. GPU execution is benchmark-gated because variable-length
  String comparison is unlikely to map efficiently to GPU hardware.

### Steps

1. Introduce a pure worker over one already-disjoint key range.
2. Dispatch CPU work through balanced binary parallel-let recursion with explicit
   fuel/depth accepted by the installed checker.
3. Concatenate outputs in boundary order.
4. Add A1 for empty, single, uneven, duplicate-boundary, and tombstone fixtures.
5. Compare one, two, four, and eight CPU threads.
6. Add a separate GPU `!` wrapper only after CPU behavior is green; never route
   IO or String-heavy merge to GPU by default.
7. Keep the sequential implementation as the semantic oracle and fallback.
8. Enable CPU parallel or GPU mode only when it beats sequential mode on the
   same workload.

### Gate

```sh
./proofs/run.sh
MYLSM_THREADS=1 bend bench/compaction_bench.bend -o .mylsm/build/compact-bench
.mylsm/build/compact-bench --threads 1
.mylsm/build/compact-bench --threads 8
```

### Checkpoint

```sh
git add src/SortedRun.bend src/Compact.bend bench/compaction_bench.bend LAWS../proofs/run.sh
git commit -m "perf: parallelize disjoint compaction ranges"
```

---

## Task 11: Remove quadratic compatibility paths

**Files:**

- Modify: `src/Sstable.bend`
- Modify: `src/Compact.bend`
- Modify: `src/MergeIter.bend`
- Modify: `src/Flush.bend`
- Modify: tests and documentation referencing `build_go`

### Steps

1. Replace MemTable flush sorting with stable merge sort plus newest-wins
   deduplication. MemTable entries are newest-first; the sort must preserve that
   precedence on equal keys.
2. Introduce an explicit v2 SSTable codec marker whose payload is canonical,
   sorted, and unique. Flush writes `Db.table_entries(tbl)` as v2; compaction
   writes sorted output as v2. Parser dispatch remains: v1 raw payload ->
   canonicalizing `Sstable.build`; v2 canonical payload -> validate strict/unique
   then `from_sorted_unique`. Add v1/v2 round-trip and mixed-recovery fixtures.
3. Route every proven/validated sorted source through `from_sorted_unique`.
4. Remove production calls to `insert_sorted` and `build_go` after all new writes
   are v2 and v1 parsing retains an explicitly isolated compatibility builder.
5. Keep a test-only/reference v1 insertion sort only where migration and
   differential tests require it; name it explicitly as compatibility code.
6. Grep the repository for accidental hot-path `List.append`, repeated
   `List.length`, `List.reverse` for last-key lookup, and linked-list indexing.
7. Update the design spec to replace the old `O(N²)` implementation note.

### Gate

```sh
grep -R "build_go\|insert_sorted" src app bench LAWS../proofs/run.sh
./proofs/run.sh
bend bench/fuzz.bend
bench/cli_smoke.sh
bench/compaction_regression.sh final
```

### Checkpoint

```sh
git add src app bench LAWS../proofs/run.sh docs
git commit -m "refactor: remove quadratic SSTable construction"
```

---

## Task 12: Final million-write acceptance run

### Environment prerequisites

- At least 15% free disk.
- No unrelated CPU-heavy or IO-heavy workload.
- AC power connected.
- Fixed Bend version and commit recorded.
- Same database directory policy for every comparison.
- CPU frequency/thermal state noted where available.

### Runs

```sh
MYLSM_BENCH_RESET=1 MYLSM_THREADS=1 bench/million_writes.sh 20485 .mylsm-20k-t1
MYLSM_BENCH_RESET=1 MYLSM_THREADS=8 bench/million_writes.sh 20485 .mylsm-20k-t8
MYLSM_BENCH_RESET=1 MYLSM_THREADS=8 bench/million_writes.sh 100000 .mylsm-100k
MYLSM_BENCH_RESET=1 MYLSM_THREADS=8 bench/million_writes.sh 1000000 .mylsm-1m
```

Run each completed workload three times on fresh directories and report the
median. Do not reuse a recovered database for a clean-write throughput claim.

### Required report

- total elapsed time;
- acknowledged writes and ops/s;
- p50/p95/p99 write latency if instrumentation supports it;
- total compaction time and maximum single compaction stall;
- number and size of output SSTables per level;
- bytes written and write amplification;
- peak resident memory;
- recovery time and recovered key count;
- proof, fuzz, smoke, and crash-gate results;
- comparison to the pre-change 4,096 result and 30-minute timeout.

### Initial acceptance gates

- 20,485 writes must complete rather than stall at the fifth-table trigger.
- Five-run pure compaction must exhibit non-quadratic scaling.
- 1,000,000 writes must complete within 30 minutes on the same development
  machine; this is only a first regression gate, not a competitiveness claim.
- Recovery must observe exactly 1,000,000 live benchmark keys.
- `./proofs/run.sh` must still print `All terms check.`

### Final checkpoint

```sh
./proofs/run.sh
bend bench/fuzz.bend
bench/cli_smoke.sh
bench/fault_inject.sh
bench/compaction_regression.sh final
git diff --check
git add src bench docs LAWS../proofs/run.sh .gitignore
git commit -m "perf: complete proven linear compaction"
```

---

## Required `proofs/*Proof.bend` structure

Append witnesses in the same order as their laws. Keep the existing witness
names untouched until migration is complete. The final compaction section must
contain, at minimum:

```python
def Laws.key_cmp_refl(key):
  # existing structural String comparison witness

def Laws.key_cmp_eq_iff(a, b):
  # general structural equality/comparison correspondence

def Laws.key_cmp_reverse(a, b):
  # general LT/GT inversion witness

def Laws.key_lt_transitive(a, b, c):
  # general conditional transitivity witness

def Laws.key_le_transitive(a, b, c):
  # general conditional transitivity witness

def Laws.key_trichotomy(a, b):
  # general consistent one-hot classification witness

def Laws.run_merge_empty_left():
  {==}

def Laws.run_merge_empty_right():
  {==}

def Laws.run_merge_lt():
  {==}

def Laws.run_merge_eq_newer():
  {==}

def Laws.run_merge_gt():
  {==}

def Laws.run_merge_sorted(...):
  # explicit structural witness when normalization is insufficient

def Laws.run_merge_unique(...):
  # explicit structural witness when normalization is insufficient

def Laws.run_merge_resolve(...):
  # explicit structural witness when normalization is insufficient

def Laws.run_merge_scan(...):
  # general arbitrary-input/bounds witness plus separate closed fixtures

def Laws.run_merge_many_order(...):
  # general well-formed L0 precedence witness

def Laws.bloom_well_formed(...):
  # prove logical words/bits are covered by the padded power-of-two tree

def Laws.bit_set_hit(...):
  # structural tree witness

def Laws.bloom_add_hit(...):
  # reuse bit_set_hit for both seeded positions

def Laws.bloom_fold_safe(...):
  # induction over entries

def Laws.table_count_exact(...):
  # general constructor output invariant

def Laws.table_smallest_exact(...):
  # general constructor output invariant

def Laws.table_largest_exact(...):
  # general constructor output invariant

def Laws.table_overlap_equiv(...):
  # general constructor/parser metadata equivalence

def Laws.legacy_canonicalize(...):
  # general valid-v1 canonicalization witness plus malformed/closed fixtures

def Laws.shadow_resolve_preserve(...):
  # general explicit two-run structural witness

def Laws.partition_concat(...):
  # induction over target-bounded splitter

def Laws.partition_bound(...):
  # induction over emitted chunks

def Laws.partition_disjoint(...):
  # boundary witness over adjacent chunks

def Laws.compact_linear_live():
  {==}

def Laws.compact_linear_get():
  {==}

def Laws.compact_linear_scan():
  {==}

def Laws.compact_linear_idempotent():
  {==}

def Laws.closure_complete(...):
  # general proof under pairwise-disjoint L1 precondition

def Laws.compact_observational(...):
  # general arbitrary-key/range preservation theorem

def Laws.output_names_unique(...):
  # general output-count/generation witness

def Laws.counter_restore_all_levels(...):
  # general max-generation restoration witness

def Laws.partition_worker_agrees(...):
  # general sequential/parallel worker equivalence witness
```

Ellipses in this planning document are signatures to be resolved during proof
implementation, not code to paste into `proofs/*Proof.bend`. Every final witness must
have a concrete Bend 2 signature accepted by the checker.

## Review checklist

Before declaring the plan implemented, review these questions explicitly:

- Is the installed Bend version recorded, and was its current `bend guide`
  consulted before relying on recursion or parallel syntax?

- Do K1–K6 establish one coherent total order for arbitrary Strings before any
  sorted-run or closure theorem relies on it?
- Does every equality-key branch select the newest entry?
- Can any tombstone removal resurrect an older value?
- Can a partition boundary duplicate or omit a key?
- Can metadata disagree with the actual entry list?
- Can Bloom return `False` for an inserted key?
- Does any hot path retain repeated insertion, append, reverse, or list indexing?
- Are arbitrary-input merge, closure, partition, and observational theorems
  actually checked, rather than represented only by closed fixtures?
- Does exact Manifest drift detection compare identities, not only lengths?
- Can a crash publish only some output tables in the Manifest?
- Are old on-disk tables still readable?
- Are IO properties described as tested rather than formally proven?
- Does the million-write report separate WAL/fsync, flush, compaction, and
  serialization time?

Only after every answer is supported by code, laws, proof witnesses, or an
explicit empirical test may the implementation be called complete.
