# SSTable v2, Linear Recovery, and Formalization Plan

> **For agentic workers:** follow `AGENT.md`. Run `bend guide` before Bend work,
> keep load-bearing pure rules in `laws/*.bend`, add corresponding witnesses to
> `proofs/*Proof.bend`, run `./proofs/run.sh` before committing, parallelize only
> independent work with disjoint write sets, and do not use `@unsafe`.

## Goal

Replace the unary-length SSTable v1 codec with a compact, versioned SSTable v2
format whose serialization and parsing are linear in the encoded data size,
while preserving fail-closed recovery, v1 compatibility, newest-value and
tombstone semantics, sorted/unique table invariants, crash publication ordering,
and the existing Manifest naming scheme.

The implementation is complete only when a database produced by the durable
1,000,000-write benchmark can be reopened and its first, middle, and last keys
verified within the recovery gate.

## Implementation status (2026-09-19)

Implemented:

- canonical decimal framing and the pure SSTable v2 codec;
- v2-only production writes with canonical flush entries;
- version-dispatched v1/v2 reads;
- a single-pass legacy v1 parser without split/join or append accumulation;
- UTF-8-boundary-safe positional streaming for both formats;
- mixed-format natural migration through compaction;
- closed codec, corruption, dispatch, tombstone, and compatibility laws with
  witnesses;
- successful 20,485-write and 1,000,000-write durable recovery gates.

Measured results:

- preserved v1 1M recovery: 68.66 seconds with matching samples and level shape;
- v2 1M run: 1,048,023 ms measured writes, 1,087.20 seconds real time, post-restart
  samples passed; isolated reopen-and-reopen validation completed in 30.83 seconds;
- v2 L1: 29,175,202 bytes versus 103,339,329 bytes for v1.

Still incomplete:

- the aggregate `./proofs/run.sh` gate exceeds 15 minutes without diagnostics;
- not every quantified theorem in the matrix has an accepted general proof;
- crash injection and the complete corruption/chunk-boundary matrix remain
  empirical follow-up work.

## Observed failure and baseline

On Bend 2.0.11, the current implementation completed 1,000,000 durable writes:

```text
writes_completed=1000000
elapsed_ms=710660
phase=pre_recovery samples=pass
phase=pre_recovery mem_entries=332 l0_tables=4 l1_tables=1
```

The resulting `l1-288.tbl` was 103,339,329 bytes. Recovery first failed because
`Flush.read_file` read only one MiB. Chunked complete-file reading fixed that
truncation, but reopening still failed to finish within 30 minutes.

SSTable v1 encodes lengths in unary dashes and repeatedly uses whole-string
`split`, `join`, `take`, and `drop`. The v2 design must remove both the size
amplification and repeated full-string reshaping.

## Scope

### In scope

- A precise, versioned SSTable v2 wire format.
- Decimal length framing with bounded parsing and no unary lengths.
- A single-pass pure parser that consumes the input structurally.
- A chunk-aware IO decoder that does not repeatedly concatenate prefixes.
- Incremental checksum calculation over exactly the serialized body.
- v1 read compatibility and v2-only writes.
- Natural v1-to-v2 migration when a v1 table is compacted or rewritten.
- Explicit size/count/key/value limits and fail-closed errors.
- Pure laws and proof witnesses for the codec and table invariants.
- Corruption, truncation, compatibility, recovery, and performance gates.

### Out of scope

- Changing Manifest syntax or table filenames.
- Compressing keys or values.
- Block indexes, memory mapping, prefix compression, or caching table blocks.
- Background IO or GPU storage parsing.
- Proving host filesystem, `fsync`, rename, or crash behavior in Bend.
- Deleting v1 support before an explicit migration release.

## Non-negotiable invariants

1. **Fail closed:** malformed, truncated, oversized, unsorted, duplicate-key, or
   checksum-invalid v2 input is rejected.
2. **No resurrection:** tombstones round-trip as entries and continue to hide
   older values.
3. **Sorted unique tables:** successful v2 parsing produces a strict sorted run
   with no duplicate keys.
4. **Exact count:** the header entry count equals the number of decoded entries.
5. **No trailing data:** after the declared entries and checksum, no bytes/chars
   remain.
6. **Crash ordering unchanged:** table temp write, table sync, rename, directory
   sync, Manifest temp write, Manifest sync, rename, directory sync, then orphan
   cleanup.
7. **Compatibility:** existing valid v1 tables remain readable.
8. **Bounded resource use:** every recursive parser and IO loop has explicit fuel
   derived from declared limits or input length.
9. **CPU storage path:** disk IO and parsing remain CPU-only.

---

## Wire format

### Canonical grammar

SSTable v2 is an ASCII-framed sequence over Bend `String` values:

```text
file       := body "#" checksum-decimal
body       := "S2;" level-decimal ";" entry-count-decimal ";" entries
entries    := entry repeated exactly entry-count times
put-entry  := "P;" key-length-decimal ";" value-length-decimal ";" key value
del-entry  := "D;" key-length-decimal ";" key
entry      := put-entry | del-entry
```

Examples:

```text
S2;0;2;P;1;1;avD;1;b#<checksum>
S2;1;1;D;3;key#<checksum>
```

The checksum is `Manifest.mhash(body, 7)` rendered with `U32.show`. Retaining the
existing hash avoids introducing a second unaudited checksum primitive in this
milestone. A later format version may adopt a stronger checksum.

### Character-count rule

`key-length` and `value-length` count Bend `Char` elements, exactly matching
`String.length`, `String.take`, and structural String consumption. The v2 pure
codec must not mix UTF-8 byte counts with Bend character counts.

The chunked IO layer must preserve complete Bend strings as returned by the Bend
`File` effect. If the runtime can split a multi-byte character across reads, add
an audited C/JS byte-stream effect with decoder carry before claiming arbitrary
Unicode streaming support. ASCII fixtures alone are not sufficient evidence.

### Canonical decimal rule

- At least one digit is required.
- Only `0` through `9` are accepted.
- `0` is canonical.
- Leading zeroes are rejected for non-zero values.
- Overflow beyond the configured `Nat`/`U32` limit is rejected before allocation
  or traversal.
- A semicolon terminates every decimal field except the final checksum.

### Limits

Define named constants in `src/SstFileV2.bend`:

```text
max_file_chars   = 4 GiB equivalent logical limit
max_entries      = 16,777,216
max_key_chars    = 16 MiB
max_value_chars  = 1 GiB
max_level        = 255
read_chunk_chars = 1 MiB
```

The exact constants may be lowered after benchmarking, but they must be explicit,
validated before consuming payloads, covered by boundary fixtures, and shared by
whole-string and chunked parsers.

---

## Architecture

### Module boundaries

Create:

- `src/Decimal.bend`
  - canonical decimal rendering/parsing helpers;
  - overflow-aware accumulator;
  - delimiter-consuming parser state.
- `src/SstFileV2.bend`
  - v2 encoder;
  - pure cursor parser;
  - checksum fold;
  - strict sorted/unique validation;
  - conversion to `Sstable.Table`.
- `src/SstStream.bend`
  - chunk-aware decoder state;
  - bounded file-read loop;
  - incremental checksum and entry assembly;
  - no production dependence on whole-file `String.split`.

Retain:

- `src/SstFile.bend` as the public version dispatcher and v1 compatibility
  implementation;
- `src/Flush.bend` for publication helpers, not format-specific parsing;
- `src/Recover.bend` for Manifest traversal and table loading.

### Public API

`src/SstFile.bend` should expose:

```text
serialize(entries, level)       -> v2 String
parse(string)                   -> dispatch v2 or v1
parse_v1(string)                -> legacy compatibility
parse_v2(string)                -> pure v2 parser
version_of_prefix(string)       -> V1 | V2 | Unknown
```

`src/SstStream.bend` should expose:

```text
read_table(path) -> IO(Result<Error, Sstable.Table>)
```

Production recovery uses `SstStream.read_table`; pure proofs use
`SstFileV2.parse` over complete strings. Both parsers must share the same pure
field/entry transition helpers so the IO path is not a separate semantics.

### Pure cursor parser

Do not implement v2 parsing with whole-input `String.split` or by repeatedly
calling `String.drop` from the original input. Use a consuming cursor:

```text
type Cursor:
  Cur{rest: String, consumed: Nat, hash: U32}
```

Each successful helper returns the unconsumed suffix and updated hash. Parsing a
key/value consumes exactly the declared number of characters once. The parser
must be structurally recursive over the consumed string or explicitly
fuel-bounded.

Recommended pure transitions:

```text
consume_literal(cursor, "S2;")
consume_decimal(cursor, limit)
consume_char(cursor, expected)
consume_exact(cursor, length)
consume_entry(cursor)
consume_entries(cursor, declared_count)
consume_checksum(cursor)
```

The checksum fold includes every character before `#` and excludes `#` plus the
checksum digits.

### Sorted/unique validation

V2 writers receive canonical sorted unique entries. The decoder must not assume
hostile input is canonical.

While decoding, carry the previous key:

```text
None          -> first key accepted
Some(previous)-> require previous < current
```

Reject equality and descending keys immediately. After successful validation,
construct the table with `Sstable.from_sorted_unique`, avoiding the `O(N log N)`
canonicalization required for arbitrary v1 input.

V1 parsing continues through `Sstable.build` because historical v1 files may
contain raw or unsorted entries.

### Chunk-aware IO state

The streaming decoder carries:

```text
DecoderState{
  phase,
  pending_input,
  decimal_accumulator,
  remaining_entries,
  remaining_key,
  remaining_value,
  previous_key,
  reversed_entries,
  checksum,
  fuel
}
```

A chunk transition consumes as much input as possible and returns either:

```text
NeedMore{state}
Finished{table}
Rejected{error}
```

At EOF, only `Finished` is accepted. EOF in any other phase is truncation.

Use reversed entry accumulation and one final `List.reverse`; never append one
entry to the tail of a growing list. Do not concatenate all chunks into one
String in production recovery.

### Error model

Introduce a pure error enum or stable error codes for:

- unknown version;
- malformed decimal;
- decimal overflow;
- invalid level;
- entry count exceeded;
- invalid entry tag;
- key/value length exceeded;
- truncated key/value/header/checksum;
- unsorted or duplicate key;
- checksum mismatch;
- trailing data;
- file read failure.

The public IO boundary may map these to the existing `(U32 & String)` error, but
pure tests should distinguish failure classes without comparing prose.

---

## Compatibility and migration

### Read dispatch

Dispatch from the smallest prefix necessary:

```text
"S2;" -> v2
"T"   -> v1
other -> reject
```

Do not try v1 after a malformed file declares `S2;`; malformed v2 must fail
closed rather than being reinterpreted.

### Write policy

After this change:

- flush writes v2;
- compaction writes v2;
- benchmark fixtures write v2;
- v1 serializer remains available only to compatibility tests, not production
  publication.

### Natural migration

When compaction reads v1 inputs and publishes outputs, outputs are v2. Manifest
publication remains atomic, so a database may safely contain a mixture of v1 and
v2 table files until all old tables are compacted.

Add an optional explicit migration command only after natural migration is green.
It is not required for this milestone.

### Existing 1M fixture

Preserve `.mylsm-million-write-data` while developing the fast v1 compatibility
reader. It is a valuable 99 MiB regression fixture, but it remains generated data
and must not be committed.

Recovery of that fixture must first become bounded with the optimized v1 parser.
After v2 writes are enabled, generate a fresh 1M v2 fixture and compare:

- file size;
- write duration;
- recovery duration;
- sampled values;
- level shape.

---

## Formalization boundary

### Mechanized in Bend

- canonical decimal parsing/rendering behavior;
- v2 entry round-trip;
- v2 table round-trip for arbitrary well-formed canonical entries where the
  checker accepts the quantified theorem;
- parser determinism and total decision;
- declared count exactness;
- exact payload-length consumption;
- no trailing input acceptance;
- checksum agreement for encoder output;
- corruption rejection fixtures;
- tombstone preservation;
- strict ordering and uniqueness of accepted output;
- metadata count/smallest/largest agreement;
- v1/v2 observable point-read equivalence on shared fixtures;
- version dispatch separation;
- whole-input and chunk-transition agreement for bounded chunk fixtures.

### Empirical, not called formally proven

- host `File.read` behavior and Unicode chunk boundaries;
- filesystem durability and atomic rename;
- wall-clock linear complexity;
- memory high-water mark;
- kill, disk-full, permission, and hardware failures;
- scheduler behavior.

Closed fixtures supplement quantified laws but do not replace them. If Bend
2.0.11 cannot accept a required general theorem, record the exact blocker and
leave that matrix row incomplete.

---

## Formalization matrix

Every row requires a law in `laws/*.bend`, a same-name witness in `proofs/*Proof.bend`, and
non-vacuous fixtures where applicable.

| ID | Law | Required statement |
| --- | --- | --- |
| D1 | `decimal_zero_roundtrip` | Parsing rendered zero returns zero and no suffix. |
| D2 | `decimal_roundtrip` | Rendering then parsing an arbitrary bounded Nat returns it. |
| D3 | `decimal_canonical` | Accepted non-zero decimal has no leading zero. |
| D4 | `decimal_reject_empty` | Empty numeric field is rejected. |
| D5 | `decimal_reject_char` | Non-digit before delimiter is rejected. |
| D6 | `decimal_overflow_closed` | Accumulation beyond the limit is rejected. |
| V1 | `sst2_put_accept` | Put entry-transition wires entry/previous/phase (no-stream kernel; end-to-end parse diverges in the checker — see note below). |
| V2 | `sst2_del_accept` | Tombstone entry-transition wires entry/previous/phase (same no-stream kernel). |
| V3 | `sst2_entries_roundtrip` | Canonical sorted unique entries round-trip in order. |
| V4 | `sst2_table_roundtrip` | Encoding/parsing a canonical table preserves the table. |
| V5 | `sst2_count_exact` | Accepted count equals decoded list length. |
| V6 | `sst2_tombstone_preserve` | Delete remains a tombstone after round-trip. |
| V7 | `sst2_sorted` | Every accepted table is strictly sorted. |
| V8 | `sst2_unique` | Every accepted table has unique keys. |
| V9 | `sst2_metadata_exact` | Parsed metadata equals decoded entries. |
| V10 | `sst2_checksum_encoder` | Encoder checksum equals checksum fold over its body. |
| V11 | `sst2_checksum_reject_decision`, `sst2_checksum_value_accept/reject` | Checksum mismatch rejects and matching checksum accepts at the decision kernel (no-stream; end-to-end tamper vectors are runtime-covered). |
| V12 | `sst2_truncated_reject` | Truncation at header/key/value/checksum fixtures is rejected. |
| V13 | `sst2_trailing_reject` | Valid file plus trailing data is rejected. |
| V14 | `sst2_duplicate_reject` | Equal keys reject at the order decision (no-stream kernel). |
| V15 | `sst2_descending_reject` | Descending keys reject at the order decision (same kernel). |
| V16 | `sst2_version_dispatch` | `S2;` selects only v2 and `T` selects only v1 (routing passthrough + tag laws in DispatchV1/V2). |
| V17 | `sst2_v1_v2_reject_agree` | Both versions agree on malformed input; accept-equivalence is runtime-covered. |
| V18 | `sst2_feed_routes_v1/v2`, `sst2_finish_unknown` | Chunk feed routes versions and unknown version fails (no-stream kernel). |
| V19 | `sst2_chunk_boundary` | Splits inside decimal/key/value/checksum fields preserve results. |
| V20 | `sst2_parser_decides` | Parser returns `Some` or `None` for every input. |

Do not claim a general complexity theorem unless the cost model is explicitly
represented. Complexity remains a code-structure review plus benchmark claim.

## Checker limitation: no `{==}` over hashed streams

The Bend checker does not share across sequentially-chained `U32.mul`
terms: `U32.to_nat` applied to a hash accumulated over 4+ bytes diverges in
`{==}` elaboration (2 chars: 0.3s, 3 chars: 2.4s, 4 chars: >400s), while the
runtime evaluates the same terms in milliseconds. Closed laws therefore
never normalize end-to-end `parse` over a hashed stream — not even a ~13-byte
minimal body. Two source refactors keep everything else tractable without
changing semantics: `Sstable.bhash_n` folds bytes with Horner (`u32_byte`
covers at most two U32 ops per `to_nat`, exact same mod), and both SstFile
checksum sites compare via `Sstable.u32_to_nat_exact` (exact same value).
Stream-level accept paths are covered at runtime (bench smoke + fault
injection); the decision kernels (checksum, ordering, dispatch, chunk
routing) are pinned by closed unit laws.

---

## Implementation phases

### Phase 0 — Reproduce and instrument

1. Keep the existing 1M v1 database unchanged.
2. Add recovery phase timing around:
   - file reads;
   - checksum validation;
   - v1 framing parse;
   - WAL decode;
   - table/Bloom construction.
3. Add maximum resident set size collection to the benchmark script where the
   platform provides it.
4. Confirm no timeout child remains after each failed gate.

**Exit:** the current >30-minute recovery time is attributed to measured phases,
not inference alone.

### Phase 1 — Decimal core

Files:

- create `src/Decimal.bend`;
- update `laws/*.bend` and `proofs/*Proof.bend`.

Tasks:

1. Implement canonical `Nat.show`-compatible rendering or a project-owned
   renderer if proving Base compatibility is impractical.
2. Implement delimiter-aware bounded parsing without `String.split`.
3. Add D1–D6 laws and boundary fixtures.
4. Fuzz empty, leading-zero, huge, and malformed fields.

**Exit:** decimal laws check independently and malformed fields fail closed.

### Phase 2 — Pure v2 codec

Files:

- create `src/SstFileV2.bend`;
- adapt `src/SstFile.bend` dispatcher;
- update `laws/*.bend`, `proofs/*Proof.bend`, and `bench/fuzz.bend`.

Tasks:

1. Build serialization from a reversed list of fragments plus one join.
2. Implement consuming cursor transitions.
3. Validate count, limits, tags, sortedness, uniqueness, checksum, and EOF.
4. Construct successful tables with `Sstable.from_sorted_unique`.
5. Add V1–V16 and V20 laws/fixtures.

**Exit:** pure v2 round-trips and rejects the corruption matrix.

### Phase 3 — Fast v1 compatibility parser

Files:

- refactor `src/SstFile.bend` v1 path;
- retain old parser as a reference helper only if needed by differential tests.

Tasks:

1. Replace v1 whole-input split/join reshaping with a consuming structural parser.
2. Preserve exact legacy acceptance semantics where safe.
3. Differential-test old and new v1 parsers over fuzz fixtures.
4. Recover the preserved 99 MiB `l1-288.tbl` under a bounded gate.
5. Verify first/middle/last keys from the existing 1M database.

**Exit:** existing v1 database reopens without timeout and without format rewrite.

### Phase 4 — Chunk-aware production recovery

Files:

- create `src/SstStream.bend`;
- update `src/Recover.bend`;
- narrow `Flush.read_file` to small metadata/reference use or remove it from table
  recovery.

Tasks:

1. Implement `NeedMore/Finished/Rejected` decoder transitions.
2. Feed chunks directly from `File.read`.
3. Carry partial decimal and key/value state across boundaries.
4. Fold checksum incrementally.
5. Bound IO recursion with explicit fuel and limits.
6. Add V18–V19 fixtures splitting every field type.

**Exit:** production recovery does not materialize the complete encoded SSTable
String and chunk boundaries do not affect results.

### Phase 5 — Switch writers to v2

Files:

- update `src/Flush.bend`;
- update `src/Compact.bend`;
- update benchmark fixtures and documentation.

Tasks:

1. Change flush serialization to v2.
2. Change compaction serialization to v2.
3. Preserve publication and Manifest drift protocols exactly.
4. Verify mixed v1/v2 manifests.
5. Verify compaction of v1 inputs produces v2 output.

**Exit:** all new tables are v2; mixed databases recover correctly.

### Phase 6 — Recovery and crash gates

Add fixtures for:

- empty table;
- one Put;
- one Delete;
- Unicode key/value;
- maximum accepted decimal boundary;
- malformed and overflowing decimal;
- truncated header, key, value, and checksum;
- checksum mutation;
- duplicate and descending keys;
- unknown version;
- mixed v1/v2 levels;
- crash before and after table rename;
- crash before and after Manifest rename;
- disk-full and permission errors.

**Exit:** corruption never silently produces a table and valid mixed databases
remain readable.

### Phase 7 — Benchmark gates

Run in this order:

```sh
bend src/Decimal.bend
bend src/SstFileV2.bend
bend src/SstFile.bend
bend src/SstStream.bend
bend src/Recover.bend
./proofs/run.sh
bend bench/fuzz.bend
bench/cli_smoke.sh
MYLSM_BENCH_RESET=1 bench/compaction_regression.sh final
MYLSM_BENCH_RESET=1 bench/million_writes.sh 20485 .mylsm-v2-20k
MYLSM_BENCH_RESET=1 bench/million_writes.sh 1000000 .mylsm-v2-1m
```

Record:

- v1 and v2 SSTable bytes;
- write elapsed time and throughput;
- recovery elapsed time;
- peak memory;
- first/middle/last sample results;
- L0/L1 shape;
- Bend version, commit, OS, CPU count, disk free percentage.

Initial acceptance targets on the same machine:

- v2 1M L1 file materially smaller than the 103,339,329-byte v1 file;
- 1M durable writes complete within 30 minutes;
- recovery and sample verification complete within 120 seconds;
- no correctness gate uses exit status alone;
- benchmark starts with at least 15% disk free.

If recovery exceeds 120 seconds, keep the milestone incomplete and report phase
timings rather than relaxing the gate silently.

---

## Test strategy

### Differential tests

For generated bounded canonical entries:

1. serialize v1 and v2;
2. parse each format;
3. compare point resolution for present, deleted, and absent keys;
4. compare scans and metadata;
5. compact mixed inputs and verify v2 output.

### Corruption tests

For every valid closed fixture, mutate:

- each header delimiter;
- every decimal digit class;
- entry tag;
- key/value boundary;
- checksum digit;
- final character;
- appended trailing character.

Each mutation must either remain a different valid canonical file by design or be
rejected. No mutation may silently change values while preserving the old
checksum.

### Chunk-boundary tests

Feed the same file as:

- one chunk;
- one character per chunk;
- split inside every decimal;
- split between tag and delimiter;
- split inside key/value;
- split immediately before `#`;
- split inside checksum digits.

All chunkings must agree with the pure parser.

---

## Documentation updates

Update:

- `README.md` with format compatibility and recovery expectations;
- `bench/BASELINE.md` with v1/v2 size and recovery measurements;
- the linear-compaction plan to mark versioned migration complete only after all
  gates pass;
- the design spec with the exact v2 grammar and limits.

Do not describe the host streaming path as formally proven. Do not call the
formalization complete while any required quantified law or `proofs/*Proof.bend` gate is
incomplete.

## Commit sequence

Use small reviewable commits only after their gates pass:

1. `Add bounded decimal codec laws`
2. `Add pure SSTable v2 codec`
3. `Make legacy SSTable parsing linear`
4. `Stream SSTable recovery by chunks`
5. `Write SSTable v2 from flush and compaction`
6. `Add mixed-format recovery and corruption gates`
7. `Record SSTable v2 million-write results`

Do not combine a format switch with an unvalidated parser rewrite in one commit.

## Completion checklist

- [ ] V2 grammar and limits are implemented exactly as documented.
- [ ] New flushes and compactions write v2 only.
- [ ] Valid v1 tables remain readable.
- [ ] Existing 99 MiB v1 regression database reopens under its gate.
- [ ] Mixed v1/v2 manifests recover correctly.
- [ ] V2 parser is consuming and does not use whole-file split/join reshaping.
- [ ] Production recovery consumes chunks without building the encoded file as one String.
- [ ] Checksum is folded over exactly the body.
- [ ] Sortedness, uniqueness, count, metadata, and tombstones are preserved.
- [ ] Every matrix law has a `laws/*.bend` declaration and `proofs/*Proof.bend` witness, or
      the milestone explicitly remains incomplete with the blocker documented.
- [ ] `./proofs/run.sh` passes.
- [ ] Fuzz, smoke, corruption, differential, and crash gates pass.
- [ ] 1M writes and post-restart samples pass within the recorded gates.
- [ ] No `@unsafe` is introduced.
- [ ] Generated databases and `test-data/` are not committed.
