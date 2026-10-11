# MyLSM 0.6.0.0 storage and exchange formats

## Version identities

The public package version is `0.6.0.0`. The database manifest generation written by 0.6 is `5`; the version strings are not interchangeable. The supported migration source is the durable API package `0.5.0.0`, whose current on-disk storage identity is format `0.4.0.0` (generation 3). Generation 4 remains readable for databases already written by earlier 0.6 development builds, but new databases, flushes, compactions, restores, and migrations publish generation 5 manifests. The generation-4 WAL and SST record encodings remain unchanged inside generation-5 databases. The backup exchange format has its own version field and is independent of package and database versions.

The 0.6 reader accepts manifest generations 4 and 5 for normal open. Storage format 0.4.0.0 / generation 3 is accepted only by inspection and the explicit migration path; normal open never silently interprets generation 3 using the byte comparator. Unknown generations fail before recovery sweep, repair, file deletion, or data writes.

## Canonical key order

Keys are arbitrary byte strings, compared lexicographically as unsigned bytes. At the first differing position, the smaller byte sorts first. When one key is a prefix of the other, the shorter key sorts first. Empty key sorts before every nonempty key. There is no Unicode normalization or locale collation.

These vectors are normative:

| Left | Right | Result |
| --- | --- | --- |
| empty | `00` | less |
| `00` | `0000` | less |
| `7f` | `80` | less |
| `610062` | `610062` | equal |
| `61` | `6100` | less |
| `ff` | `00` | greater |

The same comparison governs MemTables, Bloom hashing inputs, SST ordering and indexes, WAL replay, range/prefix cursors, compaction, backup, and restore. Text API keys are UTF-8 encoded and use this byte order; that order is not presented as linguistic sorting.

## Public API namespaces

The public surface is split into `MyLSM.Utf8` and `MyLSM.Bytes`. Each namespace exposes `create`, `open`, `get`, `put`, `delete`, `write_batch`, `scan_range`, `scan_prefix`, `snapshot`, `stats`, `backup`, and `close` where applicable. The UTF-8 namespace accepts strings and validates text at its boundary. The byte namespace accepts and returns `Bytes.Bytes` directly and never decodes or re-encodes key/value contents.

Scans return an owned cursor with `seek`, `next`, and `close`; snapshots expose `get`, `scan_range`, `scan_prefix`, and `close`. Range scans use optional lower and upper byte bounds. Prefix scans accept an arbitrary byte prefix. Both namespaces return the same cursor lifecycle and ordering semantics, while the UTF-8 cursor enters terminal error on invalid stored text.

## Key and value limits

All limits count encoded bytes. The maximum encoded mutation record, including its tag and length fields, is 1 GiB, consistent with the current codec ceiling. A multi-mutation WAL frame is limited to 1 MiB; a single-mutation frame is limited to the record ceiling plus the existing 36-byte frame overhead. A public batch contains 1 to 256 mutations. Empty batches are invalid. The implementation rejects overflow and limit violations before WAL append or result publication.

The empty key is valid. Empty values are valid and differ from a missing key. Embedded zero bytes and invalid UTF-8 are valid in the byte API. The UTF-8 API validates incoming text and returns `InvalidUtf8` if a stored byte key/value cannot be decoded for a text read. No conversion replaces or drops bytes.

## Generation 5 manifest and generation 4 record encodings

Generation 5 changes the manifest publication layout while retaining the generation-4 WAL and SST byte encodings. Generation-4 manifests continue to use their original single `SST` name and are read without rewriting them. A generation-5 manifest contains a monotonically increasing SST file identifier and refers to immutable names `SST.<8 lowercase hexadecimal digits>`; publication writes a new SST, syncs it, then atomically publishes the manifest. This keeps the previous generation available for retained readers and crash recovery. The current writer uses file identifier 1 for a new database and increments it for each flush or compaction, failing on U32 exhaustion.

The file markers distinguish the record encodings from the manifest-generation field:

| File | Magic | Encoding |
| --- | --- | --- |
| Manifest | ASCII `MYLSM4M` followed by NUL | Generation-4 legacy layout or generation-5 file identifier, big-endian fields and checksum |
| WAL | ASCII `MYLSM4W` followed by NUL | Length-delimited mutation frames with byte keys/values and frame checksums |
| SSTable | ASCII `MYLSM4S` followed by NUL | Ordered blocks with byte-key records, block checksums, separator index, footer `END4`, and root checksum |

All integer fields are unsigned big-endian. Every length is checked against its containing frame/file and configured maximum before allocation or slicing. SST blocks target 1 MiB maximum. A reader validates a block checksum before exposing any record in that block. The index begins with `IDX4`, a big-endian block count, and one fixed 16-byte record per block: block offset, block length, separator offset, and separator length. Separator offsets are relative to the packed separator region immediately following the records; each separator is the first key in its block. The footer is `END4`, total entry count, serialized index length, and the 32-byte root checksum. The index length locates the index from the end of the file without walking earlier blocks. A range cursor binary-searches the separators, reads the selected index record and separator positionally, then starts at the corresponding block. The root checksum covers the exact serialized index bytes, including all separators. SST indexes and filter metadata are seekable and may be paged; the file layout must not require retaining all decoded entries or the complete index in memory.

The manifest stores the comparator generation so future comparison changes can be rejected or migrated explicitly. The generation-4 legacy manifest's path component is validated as metadata, not treated as a user key.

## Ordering, duplicates, and tombstones

Each source is strictly ordered and contains no duplicate logical keys after canonicalization. During merge, the newest visible mutation wins for a key. A newest tombstone suppresses older values and is not emitted by a scan or logical backup. Restore rejects unsorted or duplicate exchange entries rather than choosing a winner.

Range scans use `[lower, upper)`, with either bound optional. Prefix scans compare the exact prefix bytes. If a prefix has no finite successor in the key space, the cursor checks prefix membership directly rather than wrapping a computed bound.

## Backup exchange format

Backup format version 1 is independent of database manifest generation 5. It contains a fixed magic, version, bounded blocks of strictly ordered key/value byte pairs, per-block counts and checksums, a total record count, and a final marker/checksum. Tombstones and database history are not exported. A successful backup represents one retained snapshot exactly.

Restore validates the entire stream incrementally: version, lengths, resource limits, strict key order, checksums, total count, and final marker. It writes a sibling temporary database in manifest generation 5, syncs and reopens it, and atomically publishes only after all checks pass. Existing destinations are rejected.

## Migration

Migration reads durable API 0.5.0.0 databases whose storage generation is 3. It verifies the legacy Manifest, WAL, and SST files using their generation 3 codecs, then emits logical entries in generation 5 manifests and generation-4 byte record encodings using canonical byte order. The source remains unchanged. Package version and storage generation are reported separately. Formats older than generation 3 are unsupported.

An interrupted or failed migration does not publish a final destination. A successful migration verifies entry count, exact key/value bytes after legacy UTF-8 decoding, and the newly written checksums before publication.

## Formal evidence boundary

The generation 5 manifest layout, generation-4 WAL/SST encodings, bounds, and error choices are pure Bend decisions and receive laws and witnesses where their inputs can be modeled without host effects. `bend-kit-bytes` supplies the underlying packed byte comparison implementation; closed byte-order vectors exercise its documented unsigned lexicographic behavior, but they do not constitute a proof of that dependency or of host IO.
