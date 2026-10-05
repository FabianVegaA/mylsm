#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
RUNNER="$ROOT/bench/storage_codec_compare.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-codec-runner-test.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_rejected_without_directory() {
  local label=$1 expected_status=$2
  shift 2
  local output="$TMP/$label"
  set +e
  "$@" "$output" 4 >"$TMP/$label.log" 2>&1
  local status=$?
  set -e
  [[ $status -eq $expected_status ]] || fail "$label exited $status, expected $expected_status"
  [[ ! -e $output ]] || fail "$label created $output"
}

expect_rejected_without_directory invalid_mode 2 "$RUNNER" invalid
expect_rejected_without_directory short_repeat 2 "$RUNNER" baseline
expect_rejected_without_directory unsafe_path 2 env MYLSM_BENCH_MIN_FREE_PERCENT=0 "$RUNNER" baseline /
expect_rejected_without_directory low_disk 2 env MYLSM_BENCH_MIN_FREE_PERCENT=100 "$RUNNER" baseline

git -C "$ROOT" check-ignore -q bench/results/storage-codec-test.md && fail 'Markdown result remains ignored'
git -C "$ROOT" check-ignore -q .mylsm/build/bench/raw.log || fail 'raw benchmark log is not ignored'
MEASURED=$(python3 "$ROOT/bench/measure_rss.py" "$TMP/child.log" python3 -c 'print("child=pass")') || fail 'RSS measurement helper failed'
[[ $MEASURED =~ ^max_rss_bytes=[1-9][0-9]*$ ]] || fail "RSS helper returned invalid measurement: $MEASURED"
grep -q '^child=pass$' "$TMP/child.log" || fail 'RSS helper did not preserve child output'
STATS=$(bend "$ROOT/bench/storage_codec_report.bend" stats 5 1 3 2 4)
[[ $STATS == 'median=3 spread=4 samples=5' ]] || fail "Bend statistics are wrong: $STATS"
GATE=$(bend "$ROOT/bench/storage_codec_report.bend" compare 100 105 1000 1000)
[[ $GATE == 'elapsed_regression_percent_x100=500 rss_ok=true status=pass' ]] || fail "5% boundary should pass: $GATE"
GATE=$(bend "$ROOT/bench/storage_codec_report.bend" compare 100 106 1000 1000)
[[ $GATE == 'elapsed_regression_percent_x100=600 rss_ok=true status=fail' ]] || fail "over 5% regression should fail: $GATE"
GATE=$(bend "$ROOT/bench/storage_codec_report.bend" compare 100 101 1000 1001)
[[ $GATE == 'elapsed_regression_percent_x100=100 rss_ok=false status=fail' ]] || fail "RSS regression should fail: $GATE"
SAMPLES="$TMP/samples.tsv"
REPORT="$TMP/report.md"
printf 'workload\trepeat\tcommit\tdirty\tbend\tos\tarch\tthreads\tdisk_device\tdisk_free_percent\telapsed_ms\trecovery_ms\tthroughput_ops_s\tmax_rss_bytes\tdatabase_bytes\tvalid\n' > "$SAMPLES"
for workload in writes_4097 writes_20485 writes_1000000 compaction_5x4097; do
  for repeat in 1 2 3 4 5; do
    printf '%s\t%s\tcommit\ttrue\tbend 2.0.35\tDarwin\tarm64\t12\tdisk\t32\t10\t1\t100\t20\t30\ttrue\n' "$workload" "$repeat" >> "$SAMPLES"
  done
done
cat > "$REPORT" <<EOF
comparison_valid=true
validated_samples=20
repeats=5
raw_samples=$SAMPLES

| Workload | Metric | Median | Spread | Unit |
| --- | --- | ---: | ---: | --- |
| writes_4097 | elapsed_ms | 10 | 0 | elapsed_ms |
| writes_4097 | recovery_ms | 1 | 0 | recovery_ms |
| writes_4097 | max_rss_bytes | 20 | 0 | max_rss_bytes |
| writes_4097 | database_bytes | 30 | 0 | database_bytes |
| writes_4097 | median_throughput_ops_s | 409700 |  | ops/s |
| writes_20485 | elapsed_ms | 10 | 0 | elapsed_ms |
| writes_20485 | recovery_ms | 1 | 0 | recovery_ms |
| writes_20485 | max_rss_bytes | 20 | 0 | max_rss_bytes |
| writes_20485 | database_bytes | 30 | 0 | database_bytes |
| writes_20485 | median_throughput_ops_s | 2048500 |  | ops/s |
| writes_1000000 | elapsed_ms | 10 | 0 | elapsed_ms |
| writes_1000000 | recovery_ms | 1 | 0 | recovery_ms |
| writes_1000000 | max_rss_bytes | 20 | 0 | max_rss_bytes |
| writes_1000000 | database_bytes | 30 | 0 | database_bytes |
| writes_1000000 | median_throughput_ops_s | 100000000 |  | ops/s |
| compaction_5x4097 | elapsed_ms | 10 | 0 | elapsed_ms |
| compaction_5x4097 | max_rss_bytes | 20 | 0 | max_rss_bytes |
| compaction_5x4097 | database_bytes | 30 | 0 | database_bytes |
EOF
"$RUNNER" --validate "$REPORT" >/dev/null || fail 'valid report was rejected'
sed 's/| writes_4097 | elapsed_ms | 10 |/| writes_4097 | elapsed_ms | 11 |/' "$REPORT" > "$TMP/inconsistent-report.md"
if "$RUNNER" --validate "$TMP/inconsistent-report.md" >/dev/null 2>&1; then
  fail 'report with a median inconsistent with its samples was accepted'
fi
echo 'storage_codec_compare_smoke=pass'
