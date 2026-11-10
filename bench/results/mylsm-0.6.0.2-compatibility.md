# MyLSM 0.6.0.2 compatibility evidence

Validation date: 2026-11-09. Host: Darwin 25.6.0 arm64.
Base revision: `eefd74145aedbd331acca297ca781888a3f6d56c`, with the release changes.
Bend: 2.0.40, Nix input `222de9901d4e3551c2b347da02e02a10098a28b2`.
ez: 1.15.0, Nix input `376d36dadb613d957baed1521036c6f10c398a91`.
All commands below run inside `nix develop` unless noted otherwise.
The corrected runtime matrix passes all 14 cases. Release compatibility is accepted
for the exercised Darwin arm64 scope below.

## Regression and correction

The unchanged `owner_options.sh` fixture passes with Bend 2.0.39 and fails
with Bend 2.0.40. The owner exits with `runtime fail-stop` after a client connects.
An instrumented copy of the generated C identifies `ERR_RFCS` in `span_fade`,
called while `ConnectionStore.event.count.keep` traverses readiness events.
The custom polling effect manually constructed list nodes with unsealed child
constructor terms. This violated the native runtime's sharing invariant.

The effect now constructs both ready events and list nodes with `io_node`,
which applies the constructor's reference-sharing metadata. An extended
`unix_socket_poll_many` smoke shares the returned list, counts and retains one
copy, and checks the original copy's event identity and flags. It fails with
`runtime fail-stop` before the C correction and passes afterwards. No law,
witness, safety check, or error classification was weakened. The corrected smoke
also passes with Bend 2.0.39, retaining the declared minimum version.

## Completed checks

| Command / group | Observed result |
| --- | --- |
| `bend version` | `bend 2.0.40`, from the pinned Nix store path |
| `bash proofs/run.sh` | `SUMMARY PASS=84 FAIL=0 TIMEOUT=0 TOTAL=84`; every module uses `--verdict` |
| `lefthook run pre-commit --all-files` | Pass after whitespace-only SHA core formatting |
| `nix flake check --print-build-logs` | Pass on aarch64-darwin; package builds and installed CLI checks pass |
| `bash bench/smoke/unix_socket_poll_many.sh` | Regression fails before the fix and passes after it |

The global lint run initially found 143 overlong lines in vendored SHA core.
Formatting preserves all non-comment tokens; the provenance note records the
whitespace changes and retains the NIST-vector/trust limitation. The SHA stream
smoke and its formal module pass after formatting.

The decoder corpus passes with `FUZZ CLEAN: 1000000 inputs decided (seed 123456789)`;
the directed grammar corpus passes with `GRAMMAR CLEAN: 708 directed cases on verdict`.
These are executable fixtures, not quantified proofs.

## Storage and host checks

The following 16 checks pass:

- `bench/smoke/shared_utf8_bytes.sh`
- `bench/smoke/byte_block_reader.sh` (positioned reads, EOF, invalid offsets, truncated/corrupt blocks, SST recovery)
- `bench/smoke/public_bytes_sst.sh`
- `bench/smoke/public_backup_file.sh`
- `bench/smoke/public_utf8_backup_file.sh`
- `bench/smoke/public_restore_io.sh`
- `bench/smoke/sha256_stream.sh`
- `bench/smoke/unknown_wal_no_mutation.sh`
- `bench/smoke/legacy_wal_replay.sh`
- `bench/smoke/legacy_sst_io.sh`
- `bench/smoke/db_lock_js_unsupported.sh`
- `bench/smoke/rename_noreplace_js_unsupported.sh`
- `bench/crash/durable_commit.sh`
- `bench/crash/backup_publish.sh`
- `bench/crash/migration_publish.sh`
- `bun bench/smoke/js_bun_ffi.js`

`bench/smoke/effs.bend` compiled to native C execution and JavaScript passes
under native execution, Node and Bun (`SMOKE OK` in each fresh working directory).
All three public examples (`bytes_basic`, `utf8_basic`, `snapshot_scan`) compiled
to JavaScript pass under Bun, each with its own fresh database.

## Corrected runtime matrix

Command: `python3 scripts/validate.py --suite runtime --output bench/results/compat-0.6.0.2/runtime-fixed`.
All 14 cases exit zero and match their required completion markers.

| Case | Result | Seconds |
| --- | --- | ---: |
| `options_codec` | PASS | 0.288 |
| `owner_options` | PASS | 56.902 |
| `owner_generation_tokens` | PASS | 75.187 |
| `owner_retired_sst` | PASS | 18.413 |
| `unix_socket_poll_many` | PASS | 63.713 |
| `owner_reactor_deadline` | PASS | 46.373 |
| `owner_reactor_fairness` | PASS | 54.595 |
| `owner_reactor_write_backpressure` | PASS | 51.566 |
| `owner_queue` | PASS | 48.573 |
| `coordinator_owner_dispatch` | PASS | 1.786 |
| `owner_tx_budget` | PASS | 190.973 |
| `owner_rx_budget` | PASS | 45.754 |
| `owner_endpoint_lifecycle` | PASS | 47.403 |
| `restore_publish` | PASS | 20.162 |

The initial matrix stopped after reproducing the owner reference-count failure;
its failures are retained separately from this complete corrected run.
The runner's source digest was captured before documentation and provenance-note
edits. No executable source changed after this run started.
The release validation archive contains logs and `source-files.sha256` for the
final source files, including Nix pins and test fixtures. Its manifest SHA-256 is
`09e150b180e195181b9607184c3feb7e19e780041c58ee54b8d6a04684b06136`.

## Limits

This is Darwin arm64 evidence, not Linux or GPU acceptance. JavaScript effects
do not implement the owner's Unix sockets; Node capability-rejection tests do
not claim full database support without Bun FFI. Runtime and crash fixtures are
empirical evidence for their executed cases. Formal laws cover pure decisions;
they do not prove Bend Base, the compiler, host IO or filesystem durability.
Existing performance limitations from the 0.6 acceptance report remain; no new
performance guarantee is made. Storage formats, dependency hashes and public API
contracts are unchanged.
