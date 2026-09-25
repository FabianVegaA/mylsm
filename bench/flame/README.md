# Flame graphs for MyLSM native binaries

Bend has no profiler; on macOS the method is `sample(1)` over a running
native binary plus `bench/flame/sample_fold.py` (stdlib only) to folded
stacks for Brendan Gregg's `flamegraph.pl` (external, not vendored).

## Capture

```sh
# C build needs Apple clang when Homebrew llvm is present (see README)
export CC=/usr/bin/clang
bend bench/million_writes.bend -o .mylsm/build/million-writes

# run in background, sample the WORKER pid (not the /usr/bin/time wrapper)
MYLSM_BENCH_WRITES=1000000 MYLSM_BENCH_DIR=.mylsm-flame-1m \
  .mylsm/build/million-writes --threads 12 &
sample <worker-pid> 15 -file .mylsm/build/flame/sample-writes-1.txt
```

Take one sample per workload phase (early writes, mid compaction, tail);
each 15 s sample at 1 ms holds ~12–13k stacks. Raw `sample-*.txt` files live
under `.mylsm/build/flame/` (gitignored, local study only).

## Fold and render

```sh
python3 bench/flame/sample_fold.py .mylsm/build/flame/sample-writes-1.txt \
  > bench/flame/folded-writes-1.txt
flamegraph.pl bench/flame/folded-writes-1.txt > bench/flame/flame-writes-1.svg
```

`sample_fold.py` keeps the main thread only (the HVM worker pool idles on
condvars), drops `Binary Images`, and emits leaf weights (parents carry
cumulative counts). Folded weights must sum to the sample count
(`awk '{s+=$NF} END {print s}'`); the two committed files sum exactly to
their 12,755 / 12,832 samples. HVM symbols map back: `WL_FID____SRC_<FILE>`
is a Bend def from `src/` (e.g. `WL_FID____SRC_WAL_DASHES` is `Wal.dashes`),
`WL_FID_STRING_APPEND/LENGTH` are Base primitives, `corpus_eval`/`io_loop`
are runtime loops.

## Committed data (2026-09-25, 1M writes, Darwin arm64, Bend 2.0.27)

- `folded-writes-1.txt` (early write phase), `folded-writes-2.txt` (mid).
- Headline (main thread, 1M writes): ~60%+ in HVM runtime scheduling
  (`pool_turn`) plus `WL_FID_LIST_LENGTH` traversals, ~10–25% in `__select`
  IO wait, app compute thinly spread (`STRING_APPEND/LENGTH`,
  `WAL_DASHES`, `COMPACT_IN_GO` all small). The single hottest app-level
  frame family is `List.length` — fuel/size recomputation over long lists
  is the first thing to attack, not hashing.
- Memory (`/usr/bin/time -l` on the same run): 2.7 GB max RSS for ~22 MB
  logical — heap retention is the next thing to study after list churn.
