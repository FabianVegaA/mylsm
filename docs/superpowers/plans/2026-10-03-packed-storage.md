# MyLSM 0.4.0.0 Packed Storage Implementation Record

**Status:** Implemented. The canonical design is in `docs/superpowers/specs/2026-10-03-packed-storage-design.md`; production code is the source of truth for current module boundaries.

The 0.4.0.0 cutover uses one packed storage generation for SST, WAL, and Manifest. The previous text SST reader and its UTF-8 chunk IO effect have been removed. There is no compatibility reader or migration path for older database directories.

## Source layout

- `src/StorageBytes.bend` owns packed-byte limits, checked arithmetic, big-endian fields, and strict UTF-8 boundary conversion.
- `src/SstFile.bend` owns SST block encoding, streaming parser state, length and order validation, and checksums; `src/SstStreamIo.bend` owns bounded file reads.
- `src/Wal.bend` owns WAL mutation and batch types plus v3 frame encoding/decoding; `src/DbIo.bend` handles durable appends and repair IO.
- `src/Manifest.bend` owns the binary metadata codec and filename validation.
- `app/interchange.bend` stores version-2 exports as hex-encoded, checksummed WAL v3 frames and rejects version-1 exports.
- `src/Fs.bend` adapts packed reads/writes from pinned `bend-kit-files` and keeps durability and platform effects at the host boundary.
- Each domain law lives under `laws/` and its witnesses under `proofs/`; `PROOF.bend` imports all proof modules and `proofs/run.sh` checks them individually.
- `mylsm.bend` exposes `open_recovering` for effectful recovery of persisted databases; `open` remains the pure empty-handle constructor.

The direct packed buffer import is `bend-kit-bytes@0.3.2.0`. `bend-kit-files@0.1.1.0` internally depends on its own nominal bytes type for host transfers. MyLSM converts that boundary in `Fs.bend`; no second bytes package is directly imported into storage codecs. `bend-kit-encoding` is not used: its published encoding result uses an incompatible nominal bytes type, so the strict UTF-8 conversion remains in Bend.

## Validation evidence

- `./proofs/run.sh` and `./bin/mylsm check`: 22 passed, 0 failed, 0 timeouts. `bend PROOF.bend` reports all proofs checked; `bend PROOF.bend --verdict` currently fails because the TypeScript implementation and BendTT kernel disagree.
- `bend mylsm.bend --check-only` reports foreign/unsafe dependencies because the public facade now includes filesystem recovery. A consumer fixture builds and runs; `bend PROOF.bend --check-only` and `bend bench/smoke/sst_v3_io.bend` pass.
- `./bin/mylsm fuzz`: one million inputs decided, clean.
- `bench/crash/fault_inject.sh`: 200 crash cases passed; `bench/crash/diskfull.sh`: ENOSPC recovery and all four permission recovery cases passed.
- CLI smoke and storage codec smoke passed in an isolated temporary copy.
- Both five-run benchmark reports validate. Candidate medians improved across all four workloads; one-million writes moved from 252254 ms to 144745 ms, with peak RSS from 2502393856 to 972242944 bytes.
- Bolt reports zero errors and warnings after comments were approved and added; the width check for lines over 200 characters is clean.

The SHA-256 laws prove the pure Bend codec decisions, not the Bend Base primitives, package implementations, host IO, filesystem durability, or compiler/kernel correspondence. Crash, CLI, and fuzz runs are executable evidence for their concrete inputs, not quantified theorems.
