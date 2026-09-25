#!/usr/bin/env bash
# Memory soak gate (Phase 2C): K fixed-size write cycles to fresh dirs,
# max RSS sampled per cycle via /usr/bin/time -l. Cycle 1 warms
# caches/allocators; cycles 2..K must stay within +-20% of their median.
# Prints MEMSOAK STABLE with the series or exits nonzero naming the rogue.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build"
BINARY="$BUILD_DIR/million-writes"
SOURCE="$ROOT/bench/workload/million_writes.bend"
export CC=/usr/bin/clang
CYCLES=${MYLSM_MEMSOAK_CYCLES:-5}
COUNT=${MYLSM_MEMSOAK_WRITES:-20000}

command -v bend >/dev/null 2>&1 || { echo "bend is required" >&2; exit 127; }
case "$CYCLES" in ''|*[!0-9]*|0|1) echo "MYLSM_MEMSOAK_CYCLES must be an integer >= 2" >&2; exit 2 ;; esac

echo "phase=build status=starting"
bend "$SOURCE" -o "$BINARY"
echo "phase=build status=complete binary=$BINARY"

SERIES=""
cycle=1
while (( cycle <= CYCLES )); do
  dir="$ROOT/.mylsm-memsoak-cycle-$cycle"
  rm -rf -- "$dir"
  /usr/bin/time -l env MYLSM_BENCH_WRITES="$COUNT" MYLSM_BENCH_DIR="$dir" "$BINARY" --threads 4 >"$BUILD_DIR/memsoak-cycle-$cycle.log" 2>&1
  grep -q '^phase=pre_recovery samples=pass$' "$BUILD_DIR/memsoak-cycle-$cycle.log" || { echo "cycle $cycle failed correctness" >&2; exit 1; }
  rss=$(awk '/maximum resident set size/ {print $1}' "$BUILD_DIR/memsoak-cycle-$cycle.log")
  case "$rss" in ''|*[!0-9]*) echo "cycle $cycle: no RSS reading" >&2; exit 1 ;; esac
  SERIES="$SERIES $rss"
  echo "memsoak cycle=$cycle count=$COUNT max_rss_bytes=$rss"
  rm -rf -- "$dir"
  cycle=$((cycle + 1))
done

# Stability over cycles 2..K: every value within +-20% of the median.
python3 - "$SERIES" <<'EOF'
import statistics, sys
vals = [int(x) for x in sys.argv[1].split()]
tail = vals[1:]
med = statistics.median(tail)
lo, hi = med * 0.8, med * 1.2
bad = [(i + 2, v) for i, v in enumerate(tail) if v < lo or v > hi]
print(f"memsoak cycles=2..{len(vals)} median_rss={int(med)} band=[{int(lo)},{int(hi)}]")
if bad:
    print(f"memsoak UNSTABLE: {bad}", file=sys.stderr)
    sys.exit(1)
print("MEMSOAK STABLE")
EOF
