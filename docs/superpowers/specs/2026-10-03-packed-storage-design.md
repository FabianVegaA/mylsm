# MyLSM Packed Storage Refactor — Design Spec

**Date:** 2026-10-03
**Status:** Implemented for MyLSM 0.4.0.0
**Decision:** Target release `0.4.0.0`; move all persistent codecs to packed
bytes using `bend-kit-bytes`, and break on-disk compatibility to optimize
runtime cost and parser safety.
**Related:** `docs/superpowers/specs/2026-09-24-bend-hub-refactor-design.md`,
`bench/BASELINE.md`, `AGENTS.md`, and the local `/Users/fvega/dev/bend-kit`
checkout (`bba96d622670fd9ab9bbc08c72fd77f81c8052c2`).

## 1. Mission and approved intent

Deliver this refactor as MyLSM `0.4.0.0`. Replace text-oriented persistent
storage codecs and UTF-8 file streaming with byte-oriented formats and bounded
packed-byte processing. The goals are lower
encoding/decoding cost, fewer intermediate Strings and copies, strict bounds
on untrusted disk input, and a smaller parser attack surface. Existing database
files may become unreadable: there is no migration tool and no compatibility
reader for prior WAL, Manifest, or SSTable encodings.

The BendHub package checkout is local and mutable. The recorded versions are
`bend-kit-bytes@0.3.2.0` and `bend-kit-files@0.1.1.0`; their package hashes
and API pins are recorded in `tools/hub-dependencies.json`. UTF-8 storage
conversion is implemented in Bend over the single directly imported bytes
type: encoding@0.3.0.0 returns a nominal Bytes@0.3.0.0 that cannot be consumed
without a second Bytes import or an unnecessary buffer-to-String-to-buffer
copy. At the inspected
checkout, bytes provides packed
`Bytes`, bounded `Cursor` reads/writes/regions, and laws/proofs; encoding
provides UTF-8 conversion; files provides packed `read.words`/`write.words`
and filesystem helpers. These are code dependencies, not proof of host IO.

Public database operations continue to accept and return Bend `String` keys
and values. The new persistent representation encodes them as UTF-8 bytes.
The `0.4.0.0` release must not open `0.3.x` database files as an empty database
or silently accept the old encodings. Release notes and CLI diagnostics name
the incompatible storage generation and direct operators to back up or remove
the old directory before using `0.4.0.0`.
The format change applies to all persisted formats, including SSTables, WAL,
and Manifest, so there is one binary parsing discipline throughout storage.

## 2. Design choices

### 2.1 Persistent format

Introduce one new, explicitly versioned binary generation (format generation
3). Each file begins with a fixed magic and version, uses a single documented
byte order, and has length-delimited fields. No delimiter scanning or decimal
integer parsing is used in storage files. Parsers reject unknown versions,
truncation, overflow, lengths beyond configured caps, invalid UTF-8 in text
fields, duplicate/out-of-order SST keys, checksum mismatch, and trailing bytes.
Every parse result is decided and fails closed.

All integer fields are unsigned big-endian. The byte-level schemas are:

- SST: 8-byte magic `MYLSM3S\0`; `u32 level`; `u32 total_entries`;
  `u32 block_count`; then blocks; then footer `END3`, `u32 total_entries`,
  and 32-byte SHA-256. Each block is `u32 payload_length`, `u32 entry_count`,
  payload, and 32-byte SHA-256 over the block's two length fields and payload.
  Each payload record is `u8 tag` (`0=put`, `1=delete`), `u32 key_length`,
  key UTF-8 bytes, and, for puts, `u32 value_length` and value UTF-8 bytes.
  The footer digest covers the exact SST header and the ordered sequence of
  block digests; it binds level, declared count, order, and all block contents.
  Blocks are at most 1 MiB of payload; a record larger than this limit is
  encoded alone in a block up to the configured per-record cap. Header,
  block, count, and per-record caps are checked before allocation.
- WAL: 8-byte magic `MYLSM3W\0`; then frames. A frame is `u32 frame_length`
  (bytes after this field, including digest), `u32 mutation_count`, records
  with the same tags/lengths as SST, and 32-byte SHA-256 over the frame length
  field and frame payload before the digest. A frame may not exceed 1 MiB
  unless one record requires the larger configured per-record cap.
- Manifest: 8-byte magic `MYLSM3M\0`; `u32 generation`; `u32 level_count`;
  for each level, `u32 file_count`, then each file name as `u32 byte_length`
  and UTF-8 bytes; final 32-byte SHA-256 covers every preceding byte. The
  entire Manifest is capped at 1 MiB.

The block/frame target is 1 MiB; one oversized record may occupy a block/frame
up to the explicit per-record cap, which is fixed at 1 GiB to retain the
existing maximum value size. Aggregate lengths use checked arithmetic and
must fit the U32 cursor address space. SST block order and records are
validated incrementally without retaining the full encoded table as a String.
A table is visible only after complete validation and the existing temp-file,
fsync, atomic-rename, directory-fsync publication protocol.

WAL is a sequence of length-delimited frames. Recovery replays only complete,
valid frames. A trailing suffix too short to contain a frame length, or a final
frame whose declared end lies past EOF, is an uncommitted torn append: recovery
discards it, truncates the WAL to the last valid frame boundary, and fsyncs the
truncation before allowing any later append. A complete frame with a bad
digest, invalid field, or impossible length is corruption and fails closed;
it is never skipped. This preserves crash recovery for incomplete, unacknowledged
appends while preventing replay across corrupt complete frames. A keyless
digest cannot distinguish malicious truncation from a torn append; the trust
boundary is stated in §2.1. WAL append still fsyncs the complete frame before
changing in-memory state.

Manifest is a bounded binary structure containing generation metadata and
level/file entries, with a digest over the exact preceding bytes. File names
remain generated, validated UTF-8 path components; parsing must reject empty,
absolute, separator-containing, dot, and dot-dot names before path joining.
Missing Manifest semantics remain unchanged; malformed or unreadable existing
Manifest data is never treated as an empty database.

The format uses SHA-256 for accidental-corruption detection and binding of
metadata to content. A keyless digest does **not** authenticate data against
an attacker who can edit the database directory. It cannot distinguish a
malicious truncation of the final WAL frame from a torn append. The spec makes
no authenticity claim. Digests are per block/frame plus one SST/Manifest
binding digest; they are not computed per field.

### 2.2 Byte pipeline and ownership

Use `bend-kit-bytes` `Bytes` and `Cursor` for packed buffers, endian-aware
fixed-width fields, bounded regions, and checked cursor movement. Implement
UTF-8 encoding and strict decoding in Bend over that same Bytes type; public
keys/values and Manifest names are converted only at storage boundaries.
Invalid UTF-8 is a format error; replacement characters are not accepted.

Adapt the existing pure SHA-256 kernel in `src/hub_sha/sha256.bend` to hash
packed bytes directly. The current kernel accepts a list of octets, so its
storage path must be revised to consume the packed representation without
materializing a per-byte list or passing binary data through String. Retain
NIST vectors and prove the packed adapter agrees with the existing digest on
those vectors and storage fixtures. Hashing remains pure Bend and therefore
inside the proofable codec boundary.

Serialization computes encoded lengths before allocation, checks aggregate
limits with overflow-safe arithmetic, allocates at most the configured block
or frame cap, then fills the packed buffer. Parsing uses cursors/regions and
does not slice/copy payloads unless ownership requires it. Linear buffer and
cursor ownership is threaded explicitly. No per-byte `List<U32>` or String
round-trip is permitted on the hot path.

SST recovery reads and validates bounded blocks incrementally. WAL recovery
reads bounded frames, applies each verified frame before fetching the next,
and preserves existing replay ordering. The MemTable continues to own String
keys/values; conversion occurs once at the storage boundary. No full-file
buffer is allowed for SST or WAL. Manifest may be read as one bounded buffer
under a small explicit cap.

### 2.3 Host effects and trust boundary

Adopt pinned `bend-kit-files` packed read/write effects only after comparing
the C and JS implementations and verifying their ownership/error contracts.
Use their `read.words` and `write.words` as raw bounded transfers; perform
framing, validation, branching, and byte transformation in Bend. Existing
`Fs.fsync`, atomic `rename`, `chmod`, directory creation/enumeration, and
`CrashPoint` semantics remain in our adapter unless an audited package API
matches them exactly. In particular, never replace durability behavior with a
convenience file helper that omits directory fsync.

All foreign filesystem operations remain an explicit empirical trust root.
The package's C/JS implementations are not proved by Bend laws. No `@unsafe`
is introduced. Preserve comments that identify host IO, filesystem ordering,
package primitives, and crash tests as outside theorem guarantees. The files
package must not become a dependency of pure law or proof modules.

### 2.4 Pins and dependencies

Pin immutable hashes for bytes and files, and use those pins consistently.
Verify every transitive dependency and the actual imported API at the pinned
content hash; do not rely on the local `main` checkout or floating package
names. The encoding package is not imported because its nominal Bytes type
cannot be used with the selected bytes release without an extra direct Bytes
version. Record package release versions, hashes, Bend minimum version, and
source commit in the toolchain/package manifest. No package source is copied
into MyLSM. Upgrades re-run all proof, lint, runtime, crash, and bench gates.

## 3. Scope

In scope:

- Replace text SST serialization, parser, and recovery stream with the new
  binary block format.
- Replace WAL encoding, framing, append, and replay input with binary frames.
- Replace Manifest serialization and parsing with the bounded binary format.
- Introduce one storage byte adapter over pinned file word transfers while
  preserving the existing durability and crash protocol.
- Add laws/proofs for pure format decisions and runtime checks for effects.
- Delete old format readers, writers, laws, fixtures, and dead UTF-8 chunk
  adapters after all call sites move.
- Measure throughput, allocations/RSS, and recovery behavior against the
  recorded baseline using the same workload and hardware.

Out of scope:

- Changing public `String` key/value APIs or MemTable ordering semantics.
- Network streaming or `bend-kit-stream`; it is not a storage parser and
  would add wire dependencies unrelated to local SST/WAL IO.
- Replacing fsync/rename/crash injection with third-party convenience APIs.
- Authenticated storage, encryption-at-rest, or recovery from hostile
  directory writers; SHA-256 alone provides no authenticity.
- Supporting, detecting, or migrating older on-disk generations.

## 4. Module boundaries and data flow

| Module | Responsibility after refactor |
|---|---|
| `src/StorageBytes.bend` | Pinned bytes type, checked String↔UTF-8 conversion, size caps, shared pure format helpers. No IO policy. |
| `src/hub_sha/*.bend` | Pure SHA-256 implementation over packed bytes; no String/list conversion of binary payloads. |
| `src/SstFile.bend` | Pure bounded block encoder and incremental parser state over `Bytes`; record order, length, version, checksum decisions. |
| `src/SstStreamIo.bend` | Bounded file reads that feed the pure SST parser and preserve file-handle ownership. |
| `src/Wal.bend` | WAL mutation and batch data types. |
| `src/WalV3.bend` | Binary WAL frame layout and codec. |
| `src/Manifest.bend` | Pure binary metadata codec and filename/path-component validation. |
| `src/Fs.bend` / `src/effs/*` | Packed file read/write bridge plus metadata and durability effects. |
| `src/DbIo.bend`, `src/Flush.bend`, `src/CompactIo.bend`, `src/Recover.bend` | Orchestrate bounded IO and preserve write/replay/publish order; do not parse byte layouts in host code. |

Data path: public String mutations → UTF-8 encode → bounded binary WAL frame
→ append → close/fsync → update memory. Flush/compaction encode sorted entries
into bounded SST blocks → write temporary file → fsync → atomic rename → fsync
directory → publish binary Manifest with the same ordering as today. Recovery
validates Manifest, then each SST block and WAL frame from bounded byte reads;
only verified records enter database state.

## 5. Laws, proofs, and executable evidence

Create or update laws by domain. Each corresponding proof imports its law
module as `Laws` and only witness dependencies. Cover at minimum:

- Cursor reads/writes preserve position and contents on insufficient bounds;
  regions cannot cross their parent limits.
- UTF-8 valid round trips and strict rejection of malformed, overlong,
  surrogate, and truncated encodings.
- Binary codec round trips for empty, boundary-length, multiblock, put/delete,
  and multi-frame values; exact byte fixtures pin the selected version.
- Every malformed tag, overflow, impossible count/length, truncation point,
  checksum corruption, wrong ordering, and trailing byte is rejected.
- Incremental chunk boundaries yield the same parser result as whole-buffer
  parsing, for all closed fixtures and any open theorem accepted by Bend.
- WAL replay preserves record order; frame boundaries prevent cross-frame
  field reads; only complete validated frames are applied.
- Manifest path validation rejects traversal and absolute names before IO.

Distinguish quantified pure theorems from closed regression fixtures. If a
general theorem is blocked by the checker, document that limitation and add
adversarial executable coverage; do not imply the fixture proves the general
claim. Package proofs may be relied on for the pinned pure bytes primitives,
but not for our composition, encoding validity policy, or host effects.

## 6. Performance and security acceptance gates

Benchmarks are mandatory before and after each codec/IO slice and on the final
`0.4.0.0` candidate. Save a pre-change baseline from the parent revision and
post-change results with the same machine, compiler/toolchain, storage medium,
dataset, cache state, and tuning as `bench/BASELINE.md`. Run each case at least
five times and report median plus spread; do not compare unlike environments
or select the best sample. Measure write throughput/latency, get and recovery
throughput, compaction throughput, peak RSS, and bytes allocated/copied where
measurable. Keep raw results and commands with the benchmark report.

The performance gate is a no-regression gate: no more than 5% median
regression in any primary workload, and no increase in peak RSS. The packed
codec must also show repeatable improvement in at least one target workload
(SST encode/recovery or WAL encode/replay); otherwise it has not demonstrated
its purpose and must be optimized or dropped. Any regression above threshold
blocks release until corrected or the design is revised and approved. The
release report compares `0.4.0.0` directly with the recorded pre-refactor
baseline.

Security gate: no decoder trap on the directed malformed corpus or fuzz run;
all lengths checked before allocation; configured caps fail closed; malformed
UTF-8 and path traversal are rejected; crashes at every WAL append and SST /
Manifest publish checkpoint preserve acknowledged writes and reopen either
the last valid state or a reported corruption error. No torn/corrupt acknowledged
frame is silently ignored. An incomplete WAL tail is explicitly discarded,
truncated, and synced before subsequent writes; a complete invalid frame is
reported as corruption.

Repository gates from `AGENTS.md` remain mandatory: targeted proof checks,
`./proofs/run.sh` with no timeouts/failures, `../bolt/bin/bolt.bin` with zero
errors/warnings after the specified filters, header width ≤200, and all
relevant smoke/fuzz/crash checks. Re-run the complete matrix after any package
or toolchain pin change.

## 7. Rollout and destructive format break

The implementation plan will use gated slices, with each slice leaving a
buildable repository:

1. Pin and API-audit bytes/encoding/files; verify package proof and C/JS
   parity; prototype benchmark adapters without replacing production IO.
2. Add byte adapter and String boundary laws; test packed reads/writes plus
   existing fsync/rename crash protocol.
3. Implement the binary SST block codec and proofs; switch flush, compaction,
   streaming recovery, and fixtures together; remove text SST generation.
4. Implement WAL frames and replay; preserve fsync-before-memory ordering;
   run restart/crash matrix.
5. Implement binary Manifest and strict file-name checks; switch publication
   and recovery; run the complete database matrix.
6. Remove old text formats and UTF-8 chunk effects, then run full proofs,
   lint, fuzz, crash tests, and comparative benchmarks.

There is no dual-read period and no automatic conversion. Release notes and
CLI output for `0.4.0.0` must clearly say that existing database directories
need to be removed or backed up before opening with the new version. The
implementation must never silently interpret an old-format file as an
empty/new database.

## 8. Risks and implementation constraints

- **Package version skew:** `files/check.bend` in the inspected checkout
  imports bytes `0.3.1.0` while its directory is `0.3.2.0`. Pin/hash audit
  must prove one coherent API graph before adoption.
- **Signed/limited lengths:** the package cursor uses `U32` positions. The
  1 GiB record cap leaves headroom under its address limit; check every
  conversion and use block/frame IO rather than whole-file cursors.
- **Cursor trust:** package docs warn that callers must preserve packed layout
  and region invariants. Every constructor and transition used by MyLSM must
  be checked for bounds and linear ownership.
- **Digest streaming:** confirm an audited byte-oriented SHA-256 implementation
  that processes header plus ordered block digests without String conversion.
  Do not hash a lossy UTF-8 rendering or allocate the whole table merely to
  call a String hash API.
- **Filesystem twins:** compare errors, partial writes, EOF, close behavior,
  and byte order in C and JS. Host behavior remains empirically tested.
- **Compatibility loss:** old files are intentionally rejected; operator
  messaging and tests must prevent accidental fresh-database interpretation.
- **Performance trade-off:** more checksums can cost CPU. Digest at bounded
  blocks/frames and use benchmark evidence to select limits.

No issue above permits weakening the safety contract. If a pin lacks a needed
capability, keep a small audited adapter or select another package API rather
than placing format decisions or unchecked pointer logic in C/JS.
