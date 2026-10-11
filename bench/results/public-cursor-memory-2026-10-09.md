# Public cursor memory samples

These are exploratory RSS samples for the 0.6.0.0 public byte cursor. They are
not the release benchmark set: three runs exist for each size, and they cover
open plus a 64-item partial scan rather than the full workload matrix.

## Environment

- Date: 2026-10-09 UTC
- OS: macOS 26.6.2, Darwin 25.6.0, arm64
- Runtime: Bend 2.0.36; native executable emitted by `bend <fixture> -o <path>`
- Storage: workspace volume `/dev/disk3s5`, reported as 460 GiB; filesystem details
  and physical device model are not exposed in this environment.
- CPU model, core count, and physical memory could not be queried because the
  managed environment denies those `sysctl` reads.
- Dataset: sorted 4-byte keys, 16-byte values, written in legal batches of at most
  256 mutations, flushed to one generation-four SST, then reopened.
- Scan workload: open the public byte API, create a full-range cursor, read and
  close after 64 records. The open-only workload closes immediately after recovery.
- Process budget: 32 MiB maximum RSS; partial scan may add at most 4 MiB over open.
- RSS source: `resource.getrusage(RUSAGE_CHILDREN).ru_maxrss` in
  `bench/measure_rss.py`. No sync flag or database configuration was changed.

## Samples

| Records | SST bytes | Open RSS run 1 | 64-item scan RSS run 1 | Open RSS run 2 | 64-item scan RSS run 2 | Open RSS run 3 | 64-item scan RSS run 3 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16,000 | 464,156 | 11,681,792 | 11,796,480 | 11,681,792 | 11,829,248 | 11,698,176 | 11,812,864 |
| 64,000 | 1,856,244 | 30,687,232 | 30,425,088 | 27,508,736 | 30,408,704 | 27,508,736 | 27,525,120 |

All three runs passed the fixture's fixed 32 MiB and open-to-partial-scan limits.
RSS increased with dataset size, and the 64,000-record opening varied by about
3 MiB across runs. These samples bound only the tested workload; they do not
establish constant memory across arbitrary database sizes or satisfy the release
gate's five-run statistical requirement.

## Reproduction

```sh
bash bench/smoke/public_cursor_memory.sh
```
