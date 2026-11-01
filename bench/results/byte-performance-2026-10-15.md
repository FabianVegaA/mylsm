# MyLSM.Bytes performance results

## Environment and method

Maintenance and phase measurements compared baseline `d9ea63a0f360d921943cb4b3a85639b241a55f59` with candidate `6a031894a8af50d93cfb669c3b24196441db8c6c`. Sorting and cursor data were collected from their isolated clean commits, identified in each raw `metadata.txt`. All series use the same Apple arm64 machine, Bend 2.0.37, Apple Clang 19.1.7, the default native build, and one thread. Four ABBA/BAAB blocks were alternated, retaining eight samples per version and workload. Raw results, logs, and metadata are under `bench/results/byte-performance-raw/`; the normalized table is in `byte-performance-2026-10-15.tsv`.

The public maintenance cases use an SST fixture with 16 000 keys and a delta of 128 or 4 096 keys. The fixture was prepared once, closed, and copied before each sample. Timing covers `flush` or `compact`; the database is then closed and reopened, and its visible statistics are checked. The runner also records peak RSS and bytes on disk.

## Results

| Workload | Baseline median (range) | Candidate median (range) | Change | Samples won |
| --- | ---: | ---: | ---: | ---: |
| `order_unique`, 4 096 × 32 B | 26.5 ms (26–28) | 1 ms (1–2) | −96.2% | 8/8 |
| `order_unique`, 8 192 × 32 B | 121 ms (120–126) | 3 ms (2–6) | −97.5% | 8/8 |
| `order_unique`, 8 192 × 4 096 B | 142.5 ms (141–146) | 3 ms (2–6) | −97.9% | 8/8 |
| `scan_open`, delta 4 096 | 33.5 ms (33–36) | 1.5 ms (1–2) | −95.5% | 8/8 |
| `scan_next`, delta 4 096 × 4 096 B | 40.5 ms (40–42) | 2 ms (1–3) | −95.1% | 8/8 |
| `flush`, delta 128 | 5 246 ms (5 168–5 437) | 80.5 ms (78–90) | −98.5% | 8/8 |
| `compact`, delta 128 | 5 257.5 ms (5 162–5 432) | 80 ms (75–86) | −98.5% | 8/8 |
| `flush`, delta 4 096 | 5 427 ms (5 396–5 486) | 82.5 ms (80–94) | −98.5% | 8/8 |
| `compact`, delta 4 096 | 5 421.5 ms (5 369–5 625) | 81.5 ms (79–90) | −98.5% | 8/8 |

For maintenance, final bytes on disk match across versions for each workload: 1 585 152 bytes with delta 128 and 1 781 760 bytes with delta 4 096. Median RSS rises from 22 470 656 to 22 642 688 bytes with delta 128 and from 25 034 752 to 25 427 968 bytes with delta 4 096; these are increases below 2%, not a memory improvement.

The isolated phases with a 16 000-entry fixture produced:

| Phase | Baseline median (range) | Candidate median (range) |
| --- | ---: | ---: |
| `ByteSstIo.read` | 3 120.5 ms (2 766–3 712) | 52 ms (43–250) |
| `ordered_entries`, 4 096 | 27 ms (27–31) | 1 ms (1–2) |
| `ByteSstFile.encode_file` | 18 ms (17–25) | 19 ms (17–21) |

These phases are measured separately and are not added together to estimate `flush`. Peak RSS per phase changes by less than 1% for reading and encoding; the sorting workload takes less than 200 ms, and its RSS is noisier. The observed data do not demonstrate a memory reduction from an incremental writer.

## Decisions

- **Balanced sorting: accept.** The large cases and the public `scan_open` operation comfortably exceed the timing improvement threshold and win all eight samples. The implementation preserves newest-mutation priority and has laws/witnesses in `laws/ByteMemTable.bend` and `proofs/ByteMemTableProof.bend`.
- **Avoid value copies while advancing the cursor: accept.** `scan_next` with 4 096-byte values improves by 95.1% and wins 8/8; cursor smokes and laws/witnesses pass. The equality of `Bytes.copy.bytes` still depends on the Base primitive and is not claimed as a Bend theorem.
- **Incremental SST writer: do not implement in this iteration.** The sorting candidate already reduces public maintenance time by approximately 98.5%; RSS shows no material regression that streaming needs to address, and no writer variant demonstrates the 15% RSS reduction required by the plan without a timing regression. Changing the format or publication without that evidence would increase risk without a measured improvement.

## Evidence limitations

The maintenance fixture inserts new keys; it contains no replacements or tombstones. `scan_mixed` was not run. Benchmark validation checks counts, lengths, statistics after reopening, and structural checksums, not a cryptographic digest of each value. Many small cases take less than 200 ms and were not repeated within a single timed window; comparisons of those cases are therefore not used to accept changes. `bend update` could not query the remote release because DNS failed for `bend-lang.com`; both sides used the installed and recorded version, 2.0.37.
