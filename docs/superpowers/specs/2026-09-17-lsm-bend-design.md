# LSM Key-Value Store in Bend 2 — Design Spec

Date: 2026-09-17. Status: draft, pending human review.
Decided with human partner: real-use DB optimized for write throughput,
fully durable (WAL), generic key/value core instantiated for `String` first,
point ops + atomic batches + range scans + crash recovery, success bar is
proven laws plus a benchmark harness (no CI regression gate yet).
Architecture: tiered LSM with WAL (Approach 1). Section 1 reviewed and
approved in chat; Sections 2–5 written on agent judgment, to be reviewed here.

## 1. Architecture and components (approved)

Five components, each with one job:

1. **MemTable** — the write frontier. In-memory sorted map from key to
   latest value-or-tombstone, with a size cap. Every `put` / `delete` /
   batch lands here first; reads check it first. When full it freezes
   (immutable) and a fresh one takes over, so writes never block on a flush.
2. **WAL (write-ahead log)** — the durability promise. Every mutation is
   appended to a sequential log file before it touches the MemTable.
   Sequential-only appends are the fastest durable write pattern on disk.
   On crash, replay rebuilds the MemTables.
3. **SSTables in tiered levels (L0, L1, …)** — frozen MemTables flush to L0
   as immutable sorted files. When a level holds more than T tables, they
   bulk-merge into the next level. Tiering means tables inside one level may
   overlap, so nothing is ever rewritten inside a level on the write path:
   minimal write amplification (reads pay more, writes pay less). Each table
   carries a **Bloom filter** so point reads skip irrelevant tables cheaply.
4. **Manifest** — small durable file listing which SSTables live at which
   level. Source of truth at startup; updated atomically when a flush or
   compaction completes.
5. **Merge iterator** — the read/scan engine. Merges active + frozen
   MemTables (newest first) with all overlapping SSTables (newest level
   first) by key, resolving duplicates and tombstones into one ordered
   stream that serves both `get` and range scans.

Bend mapping: MemTable over sorted arrays / `Map`; files via affine `File`
handles inside `IO`; compaction parallelized over disjoint key ranges and
Bloom construction parallelized per table; hot loops use `Nat` fuel-bounded
recursion so termination checking holds. Memory discipline is total (see
§3.3): no `@unsafe` anywhere in the repo, single-owner arrays only, explicit
bounds checks (never relying on index wraparound), and no foreign C/JS
memory tricks — host effects are limited to Base `IO` file operations, which
proofs never touch.

## 2. Data flow

### 2.1 Write path (put / delete / batch commit)

One batch (a single `put` counts as a batch of one) flows strictly in order:

1. Serialize the batch to WAL records and append to the active WAL segment.
2. `fsync` once per batch commit (group commit: one sync covers the whole
   batch, never one sync per key).
3. Apply the batch to the active MemTable (insert or tombstone per key).
4. Acknowledge the commit to the caller. A commit is durable exactly when it
   is acknowledged: no ack without a synced WAL record.
5. If the MemTable reached its size cap, freeze it and open a fresh active
   table plus a fresh WAL segment. The frozen table waits for flush; writes
   continue uninterrupted.

Nothing on this path reads existing data: no read-modify-write, no in-place
file updates. That is the whole write-speed argument.

### 2.2 Read path (get)

Search order is strictly newest-first, first match wins:

1. Active MemTable, then frozen MemTables newest-first.
2. L0 tables newest-first, then L1, L2, … oldest level last.
3. Each SSTable is consulted only if its Bloom filter says "maybe present"
   (a Bloom filter never reports a false negative).
4. A tombstone match means "not found", even if older versions exist below.
5. Exhausting all sources means "not found".

### 2.3 Range scan

The merge iterator heap-merges all sources from Section 2.2 in key order,
emits each key once (newest version wins), suppresses tombstoned keys, and
stops at the range end. `get(k)` is observably equivalent to scanning the
single-key range `[k, k]`.

### 2.4 Flush

When a frozen MemTable exists and no flush is running for it:

1. Dump its sorted contents to a new L0 SSTable file (data blocks plus
   Bloom filter), written to a temp name.
2. Rename into place, append the table to the Manifest atomically.
3. Delete the WAL segment that only that MemTable needed.

Flush never blocks writers: it touches only the frozen table.

### 2.5 Compaction (tiered)

When level L holds more than T tables (T is a per-level constant fixed in
this spec, tuned later by benchmark, default T = 4):

1. Pick all tables of L, merge-sort them into new tables for L+1 whose key
   ranges are pairwise disjoint (range partitioning enables parallelism:
   one worker per output range).
2. Write outputs to temp names, atomically swap the Manifest entry
   (add outputs, remove inputs), then delete input files.
3. Compactions at different levels and disjoint ranges may run concurrently;
   two compactions never share an input table (a table is claimed by the
   Manifest update that removes it).

No work here sits on the write path: compaction only rewrites data
bulk-wise, downward, in the background.

### 2.6 Recovery (startup)

1. Read the Manifest; open every listed SSTable (a missing file is a fatal
   startup error, never silently ignored).
2. Replay every WAL segment newer than the last flushed one, in order,
   rebuilding MemTables. Each record carries a checksum; a torn tail record
   (crash mid-append) is truncated and discarded — only synced prefix data
   is replayed, which by the write-path rule is exactly the acknowledged set.
3. Resume normal operation with the rebuilt active MemTable.

## 3. Generic types and laws

### 3.1 Types

The core is generic over a key type `K` with a total-order comparison
`cmp : K -> K -> Cmp` and a value type `V` (both `Data`-kinded so entries
are freely reusable inside iterators and filters). The first instantiation
is `K = String`, `V = String`, using deterministic byte-wise comparison.
Adding a numeric-key instantiation later must not change the core: only the
`cmp` argument and serialization change.

Module layout: `src/MemTable.bend`, `src/Wal.bend`, `src/Sstable.bend`,
`src/Manifest.bend`, `src/MergeIter.bend`, `src/Db.bend` (public API:
`put`, `get`, `delete`, `write_batch`, `scan`), plus `LAWS.bend` (human-owned
claims) and `PROOF.bend` (agent-owned proofs) at the repo root.

### 3.2 Laws (all stated in LAWS.bend, all proven in PROOF.bend)

Every public def gets at least one law; representation invariants are
encoded as types where possible (e.g. a `SortedRun` type whose constructors
can only build ordered sequences, so SSTable sortedness is checked, not
merely asserted). Proofs are developed before or alongside the code they
cover — a module is done only when its laws check, not when its code runs.

Observable-behavior laws:

1. **Read-your-writes**: after an acknowledged `put(k, v)`, `get(k)` returns
   `v` until a later acknowledged write to `k`.
2. **Batch atomicity**: a batch's mutations become visible all at once; no
   reader ever observes a partial batch.
3. **Delete semantics**: after an acknowledged `delete(k)`, `get(k)` reports
   not-found until a later acknowledged `put(k, _)`.
4. **Scan order and completeness**: a scan over `[lo, hi]` yields every live
   key in range exactly once, in `cmp` order, and no key outside the range.
5. **Get-scan agreement**: `get(k)` equals the single-key scan result.
6. **Flush/compaction preservation**: flush and compaction change no
   observable read or scan result (they are pure reorganization).
7. **Recovery equivalence**: the post-recovery observable state equals the
   pre-crash acknowledged state — every acked write present, no unacked
   write required present.

Structural / representation laws:

8. **SSTable sortedness**: every table's key sequence is strictly ordered by
   `cmp` (carried by the `SortedRun` type; the law states the type erases to
   the on-disk order).
9. **WAL codec round-trip**: decode(encode(batch)) == batch for all batches,
   so replay can never misread a synced record.
10. **Merge-iterator refinement**: the iterator over any source set yields
    exactly what a naive sequential model (apply all mutations newest-first
    to an empty map) yields.
11. **Compaction multiset preservation**: compaction outputs contain exactly
    the live entries of the inputs — no loss, no duplication, newest version
    wins per key.
12. **Tiering invariant**: within a level above L0, output table ranges are
    disjoint; the Manifest always lists exactly the SSTable files on disk.
13. **Manifest round-trip**: parse(serialize(manifest)) == manifest.
14. **Bloom safety**: a Bloom filter never rejects a key the table contains
    (no false negatives; false positives only cost a read).

`bend PROOF.bend` printing "All terms check." is the commit gate for every
change, per repo house rules.

### 3.3 Memory-safety rules (no unsafe, by construction)

Bend already frees every affine value at its `match` and reference-counts
only `+` (`Data`) copies; the spec additionally forbids every escape hatch:

- No `@unsafe` def in the repo — not in DB core, not in proofs, not in the
  benchmark harness. Termination is proven for all recursion (structural or
  `Nat`-fuel-bounded).
- Arrays are always single-owner `Array<T>`; no `Array.clone` aliasing to
  fake shared mutation; every index is explicitly bounds-checked against the
  known size — the language's index wraparound is never load-bearing.
- No custom foreign C/JS effects for memory or I/O tricks. The only host
  code is Base's `File`/`IO` operations; all proofs stay in pure Bend and
  never touch host code.
- `+` (reusable) annotations appear only on `Data` values and only where the
  design says sharing is needed (iterator cursors, filter bits); the default
  everywhere else is affine.

## 4. Error handling and crash semantics

- **Commit boundary**: acknowledged = synced in WAL. Anything not yet acked
  may vanish on crash; anything acked must survive. No exceptions.
- **Torn writes**: per-record checksums in the WAL; recovery truncates the
  first record that fails its checksum and everything after it.
- **Manifest atomicity**: Manifest updates go to a temp file plus atomic
  rename; a crash mid-update leaves either the old or the new Manifest,
  never a mixture. Orphaned temp files are deleted at startup.
- **I/O errors**: file effects answer `Result`; every failure surfaces to
  the caller as a DB error value. Errors are never swallowed, and a failed
  batch reports failure without partial application (atomicity holds across
  crashes and I/O errors alike).
- **Concurrency**: one writer at a time through the MemTable/WAL path
  (batching makes this cheap); flush and compaction run concurrently via
  `IO.fork` but touch disjoint state; the program is deadlock-free by
  construction (no cyclic channel waits; joins always have a matching fork).
- **Termination/proofs**: all recursion is structurally decreasing or
  `Nat`-fuel-bounded; `@unsafe` is forbidden everywhere in the repo (see
  §3.3), with no harness exception.

## 5. Testing and benchmark harness

- **Correctness**: the fourteen laws above plus the `PROOF.bend` gate are
  the test suite. No hand-written unit-test suite duplicates what a proof
  states; property checks exist only as scaffolding while a proof is being
  built. Proofs are written before or alongside code, never after.
- **Benchmark harness** (`bench/`): measures sustained write throughput in
  ops/sec for (a) single-key sequential puts and (b) fixed-size batches
  (e.g. 100 keys), on the developer's machine, reporting threads, disk,
  and dataset size alongside every number.
- **Target policy**: the first harness run calibrates and records the
  baseline in `bench/BASELINE.md`; afterwards no commit may land below
  90% of baseline throughput on the same hardware profile. If a design
  change (e.g. level fan-in T, MemTable cap) moves the number, the baseline
  is re-recorded deliberately, never silently.
- **Read/scan performance** is measured and reported but has no gate:
  tiering explicitly trades read amplification for write speed.

## 6. Explicitly out of scope (YAGNI)

Compression, snapshots, TTL, secondary indexes, multi-batch transactions,
network server, GPU execution (revisit only with benchmark evidence of a
uniform numeric bottleneck), and any key type beyond the generic core plus
the `String` instantiation.
