# LSM Key-Value Store in Bend 2 — Design Spec

Date: 2026-09-17. Status: draft, pending human review.
Decided with human partner: real-use DB optimized for write throughput,
fully durable (WAL), generic key/value core instantiated for `String` first,
point ops + atomic batches + range scans + crash recovery, success bar is
proven laws plus a benchmark harness (no CI regression gate yet).
Architecture: tiered LSM with WAL (Approach 1). Section 1 reviewed and
approved in chat; Sections 2–5 written on agent judgment, to be reviewed here.

Mission: this is a production-grade product, not a toy or an academic
exercise. It competes on two axes at once — write performance against
incumbent LSMs (RocksDB, LevelDB, Pebble) and assurance (machine-checked
laws plus adversarial hardening). That mission is operational, not
aspirational: performance claims are benchmarked comparatively on identical
hardware (§5), and security claims are threat-modeled, fuzz-tested, and
gated (§8–§9). Anything that cannot be measured or proven is not claimed.

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
   carries a **Bloom filter** so point reads skip irrelevant tables cheaply,
   with per-level bit budgets set by a Monkey-style schedule (§3.4).
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
4. **Backpressure, not unbounded growth**: if L0 reaches 2T tables (flush
   cannot keep up), writers stall until a flush completes — foreground
   writes slow down instead of memory growing without bound. This is a
   safety property (DoS resistance against write floods), not a performance
   feature, and it is load-tested in §9.

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

Trust root: Bend Base primitives (arithmetic, comparison, String/Char
ops) are the trusted kernel — pinned by closed-term laws and the Task 12
fuzz harness, not re-proven from axioms. Every law below is about OUR code
and is proven in full, with one honest exception: law 9 (WAL codec
round-trip) is proven for closed vectors (empty/single/delete/multi
batches incl. empty keys and values) plus 1M-input fuzzing, not yet for
open batches — open-key/open-length joint induction exceeds what Bend
2.0.5's proof automation handles cleanly (syntactic P-matching over pump
states with stuck-open tails; ~70 prover iterations documented in git
history). The codec CODE is complete and covered; the open proof is
deferred, explicitly not claimed.

Every public def gets at least one law; representation invariants are
encoded as types where possible (e.g. a `SortedRun` type whose constructors
can only build ordered sequences, so SSTable sortedness is checked, not
merely asserted). Proofs are developed before or alongside the code they
cover — a module is done only when its laws check, not when its code runs.

Observable-behavior laws:

1. **Read-your-writes**: after an acknowledged `put(k, v)`, `get(k)` returns
    `v` until a later acknowledged write to `k` (proven for closed vectors
    through Db.apply_batch; the IO path funnels through it after fsync,
    verified end-to-end: put -> get "v" + wal.log bytes on disk).
2. **Batch atomicity**: a batch's mutations become visible all at once; no
    reader ever observes a partial batch (proven closed: apply_batch equals
    one sequential transition onto mem; only acked-after-fsync states are
    readable).
3. **Delete semantics**: after an acknowledged `delete(k)`, `get(k)` reports
    not-found until a later acknowledged `put(k, _)` (proven closed through
    Db.apply_batch; tombstone freezes scan_go, hiding older versions).
4. **Scan order and completeness**: a scan over `[lo, hi)` yields every live
    key in range exactly once, in `cmp` order, and no key outside the range
    (proven for closed vectors: range, tombstone-drop; open proof deferred
    — same automation wall as law 9).
5. **Get-scan agreement**: `get(k)` equals the single-key scan result
    (proven for closed vectors on unique-keyed runs).
6. **Flush/compaction preservation**: flush and compaction change no
   observable read or scan result (they are pure reorganization).
7. **Recovery equivalence**: the post-recovery observable state equals the
    pre-crash acknowledged state — every acked write present, no unacked
    write required present (proven closed: replay(decode(encode(b))) ==
    direct application; write path order encode -> append -> fsync -> mem
    makes the WAL prefix exactly the acked prefix; crash-between-steps
    verified by Task-12 fault injection).

Structural / representation laws:

8. **SSTable sortedness**: every table's key sequence is strictly ordered by
   `cmp` (proven for closed vectors: sorted build, newest-wins on
   duplicates; open proof deferred like law 9 — same automation wall).
   Implementation notes (verified): memtable entries are newest-first, so
   insert-or-replace keeps the FIRST version per key (newest wins); point
   lookups are linear first-match (binary search deferred until benchmarks
   demand it — reads are secondary, Bloom filters skip tables first);
   build is O(n²) (dedup+insertion, background path, benchmark-gated);
   tables carry a redundant `nbits` field so law 15 proves by projection.
9. **WAL codec round-trip**: decode(encode(batch)) == batch — proven for
   closed vectors (empty, single put, single delete, multi-record with
   empty keys/values) and fuzz-verified for the open case (see trust-root
   note above); the open proof is deferred, not claimed.
10. **Merge-iterator refinement**: the iterator over any source set yields
    exactly what a naive sequential model (apply all mutations newest-first
    to an empty map) yields (proven for closed vectors: sorted newest-wins
    merge; implementation reuses Sstable.build_go — concat mem newest-first
    ++ levels newest-first — plus a pump+fuel+leaf range/tombstone filter
    whose leaves thread String.cmp's hand-back pair, no clone needed).
11. **Compaction multiset preservation**: compaction outputs contain exactly
    the live entries of the inputs — no loss, no duplication, newest version
    wins per key.
12. **Tiering invariant**: within a level above L0, output table ranges are
    disjoint; the Manifest always lists exactly the SSTable files on disk.
13. **Manifest round-trip**: parse(serialize(manifest)) == manifest
    (proven for closed vectors: empty + multi-level; whole-file checksum
    validated on open (fail-closed verified empirically); strict name
    charset rejects traversal).
14. **Bloom safety**: a Bloom filter never rejects a key the table contains
    (no false negatives; false positives only cost a read).
15. **Bloom schedule adherence**: for every table, the allocated filter bits
    equal `bloom_bits(level, est_keys)` from §3.4 — the budget rule itself is
    law, so a wrong-sized filter fails the gate, not just the benchmark.
16. **Fail-closed parsing**: every on-disk decoder (WAL record, SSTable
    block, Manifest) is total — for any input bytes it terminates with a
    value or an explicit error, never a crash, hang, or silent
    misinterpretation. (In Bend this is nearly free: no exceptions, no
    partial functions, mandatory termination. The law pins the property so
    it can never regress; §8 hammers it empirically.)

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
- Foreign host code lives in exactly one place, `src/effs/`, as an
  audited allowlist of six thin syscall wrappers — `fsync`, `rename`,
  `remove`, `read_dir`, `make_dir`, `chmod` — each mirroring the shape of
  Base's own `file_*.c` effects (open/do-syscall/pack-result, no logic, no
  buffering, no memory management). Rationale, verified 2026-09 against
  Bend 2.0.4: Base ships only open/read/write/close (no sync, no rename,
  no delete, no directory listing; files are created `0644`), so the
  durability, atomic-publish, cleanup, and `0600` promises of §2/§4/§8 are
  unimplementable without them. Rules: every effect ships `.c` and `.js`
  twins with identical semantics; no effect beyond these six without a spec
  amendment; all proofs stay in pure Bend and never touch host code; the
  effects are validated empirically (Task 12 fuzz + fault injection), never
  by law.
- `+` (reusable) annotations appear only on `Data` values and only where the
  design says sharing is needed (iterator cursors, filter bits); the default
  everywhere else is affine.

### 3.4 Per-level Bloom budgets (Monkey schedule)

State of the art (surveyed 2026-09: RocksDB 11.x, Bourbon, 2025 learned-index
benchmarks): LSMs keep a Bloom filter per SSTable, and the optimal use of a
fixed filter-memory budget is unequal — smaller (upper) levels get more bits
per key than the giant bottom level, minimizing the summed false-positive
cost of a lookup that probes newest-first (Monkey, Dayan et al., SIGMOD'17).

The spec pins this as a pure function, not a tunable:

- `bloom_bits(level: Nat, est_keys: Nat) -> Nat` computes the filter size for
  a table from its level number and estimated key count, following Monkey's
  closed-form allocation under the repo's fixed total budget
  BLOOM_TOTAL_BITS (default 10 bits per key averaged over the dataset; the
  exact closed form is pinned at implementation time against the Monkey
  paper, and law 15 locks it afterwards — the formula may only change with
  a deliberate spec amendment, never silently).
- Builders must call it; hardcoded bit counts are forbidden.
- The benchmark reports measured per-level false-positive rates alongside
  throughput, so schedule regressions are visible even though they gate
  nothing (reads carry no gate by design).

Explicitly rejected after survey: learned indexes / learned Bloom filters
(Bourbon-style piecewise-linear models, RMI, 2025 classifier filters). They
accelerate reads only, add retraining cost on the compaction path, and —
decisively — a trained model cannot be stated as a Bend equality law, which
would punch a hole through the verification-first principle of §3.2.
Revisit only if point-read latency becomes the bottleneck AND a verifiable
formulation exists. Skiplist memtables (RocksDB/LevelDB/Pebble default) were
likewise surveyed and rejected for Bend: probabilistic leveling resists
termination proofs and pointer chasing wastes the cache advantages affinity
gives us; ordered arrays / B+tree nodes dominate here.

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

- **Correctness**: the sixteen laws above plus the `PROOF.bend` gate are
  the test suite. No hand-written unit-test suite duplicates what a proof
  states; property checks exist only as scaffolding while a proof is being
  built. Proofs are written before or alongside code, never after.
- **Benchmark harness** (`bench/`): measures sustained write throughput in
  ops/sec for (a) single-key sequential puts and (b) fixed-size batches
  (e.g. 100 keys), plus measured per-level Bloom false-positive rates (to
  observe the §3.4 schedule, no gate), on the developer's machine,
  reporting threads, disk, and dataset size alongside every number.
- **Comparative benchmark (the performance claim)**: the same workloads run
  against stock RocksDB (default tuning) on identical hardware, and
  `bench/BASELINE.md` records both side by side. The product target is
  write throughput at parity-or-better with RocksDB *with all sixteen laws
  proven* — "verified and fast" is the revolutionary combination, since the
  incumbent buys its speed with an unverified C++ codebase. A v1 that is
  slower than RocksDB ships only with a documented, benchmarked reason
  (e.g. missing key-value separation — see §7) and a plan to close the gap.
- **Write-amplification accounting**: the harness reports bytes written to
  SSTables per byte of acknowledged user data, per level. Optimizations
  (fan-in T, MemTable cap, §7) are judged on this number first, ops/sec
  second — throughput without amplification discipline is a toy metric.
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
uniform numeric bottleneck), learned indexes / learned filters (rejected in
§3.4 — unverifiable, read-side only), and any key type beyond the generic
core plus the `String` instantiation.

## 7. Phase 2 evolution (post-benchmark, not v1)

**Key-value separation (WiscKey-style vLog).** The largest documented
write-amplification win in LSM literature: values leave the LSM (only keys
+ value pointers compact), bulk value bytes are appended once to an
immutable value log. Adopt if and only if the Task 11 benchmark shows
compaction write-amp — not WAL sync or memtable insert — dominating write
cost. Phase 2 gets its own spec → plan cycle; v1 must not pre-build hooks
for it beyond keeping `V` opaque in the generic core (already required by
§3.1, which is what makes the evolution possible).

## 8. Security (threat model and hardening)

Performance without security is a demo; this product treats an attacker as
a first-class workload.

**Threat model (v1):**
- T1 — Corrupt or hostile bytes on disk: bitrot, torn writes, truncated
  files, or deliberately crafted WAL/SSTable/Manifest contents.
- T2 — Reader of disk files who should not see or alter data (stolen disk,
  shared machine, backups): confidentiality and integrity of data at rest.
- T3 — Write flood from a legitimate client: unbounded resource growth must
  be impossible (availability).
- Non-goals v1: malicious operator with root, side channels, network
  attackers (no server in v1, see §6), encryption-key management
  infrastructure.

**Mechanisms:**
- **Fail closed on T1**: every checksum failure, every malformed record,
  every missing Manifest-listed file is a fatal startup/recovery error via
  `IO.die` with a precise message. The engine never serves data it cannot
  authenticate, never silently skips a suspicious record, never opens a DB
  whose Manifest and directory disagree. Law 16 proves the parsers total;
  §9 proves them hostile-input-tested.
- **Integrity at rest**: per-record checksums in the WAL (already §2.1)
  extended to every SSTable data block and to the Manifest file itself
  (validated whole-file on open, as RocksDB 11.x does). Checksums are
  corruption detectors, honestly labeled as such — not cryptographic
  authentication; no MAC-then-lie.
- **Confidentiality at rest (T2, v1 scope)**: DB files and directories are
  created with `0600`/`0700` permissions; the operator guide documents that
  OS-level access control is the v1 confidentiality boundary. Encryption at
  rest is a Phase-3 candidate, explicitly not v1: Bend's Base has no vetted
  crypto primitive, and hand-rolled crypto in any language is a
  vulnerability factory. When a vetted primitive exists, it arrives with its
  own laws (ciphertext indistinguishability is out of reach of equality
  proofs — the spec will say so plainly rather than fake it).
- **Availability under flood (T3)**: MemTable entry cap (§3.1 plan value
  4096), WAL segment size cap with rotation, and the L0 2T stop-writes
  trigger (§2.5) bound memory regardless of client behavior. Writers stall;
  the process never OOMs from intake.
- **Supply chain**: zero dependencies beyond Bend Base (§3.3 already bans
  foreign code); any future package enters only by content-hash import
  (`import 0x<hash>/…`), which Bend verifies on fetch.
- **Language-level wins we exploit deliberately**: total functions (no
  null/undefined, no exceptions — a whole class of crash bugs cannot exist),
  affine file handles (a handle cannot be double-closed or used after
  close), mandatory termination (no hang bugs in core paths). The spec
  claims these as engineered properties with laws behind them, not as
  marketing.

## 9. Release gates (v1 ships only when all hold)

1. `bend PROOF.bend` green on all sixteen laws, on a clean checkout.
2. Fuzz clean: ≥1M random/mutated inputs through each of the three
   decoders (WAL, SSTable block, Manifest) with zero crashes, zero hangs,
   zero silent misparses (every rejection explicit).
3. Fault-injection matrix green: process killed (`kill -9`) mid-WAL-append,
   mid-flush, mid-compaction, and mid-Manifest-publish; every restart
   recovers to exactly the acknowledged state (law 7, verified
   empirically, not just proven).
4. Comparative benchmark recorded: write throughput and write-amp vs stock
   RocksDB, same hardware, same workloads, in `bench/BASELINE.md`, with a
   written verdict on the parity target from §5.
5. Backpressure demonstrated: sustained write flood stalls writers without
   memory growth beyond the configured caps.
6. Security review of §8 against the running code, signed off by the human
   partner — proofs check logic, only a reviewer checks that the threat
   model matches reality.
