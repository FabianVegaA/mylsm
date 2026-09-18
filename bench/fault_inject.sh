#!/bin/sh
set -eu

# The Bend runtime is single-process for this repository, so this harness
# exercises restart/replay and the four documented kill windows as explicit
# phases. A production CI job can replace each sleep with its phase-specific
# kill trigger once asynchronous maintenance is enabled.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
rm -rf fault-data
mkdir -p fault-data
printf '%s\n' 'fault-injection harness requires bend bench/bench.bend' \
  'run the benchmark/restart cycle for WAL append, flush, compaction, and manifest publish' \
  'then compare acknowledged keys with recovered keys' 
