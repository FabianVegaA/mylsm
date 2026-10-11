#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-cursor-memory.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
BINARY="$WORK/cursor-memory"

bend "$ROOT/bench/smoke/public_cursor_memory.bend" -o "$BINARY"

measure_scan() {
  local count="$1"
  local database="$WORK/db-$count"
  MYLSM_DB_PATH="$database" MYLSM_CURSOR_MODE=create MYLSM_CURSOR_COUNT="$count" "$BINARY"
  local sst_bytes
  sst_bytes=$(wc -c < "$database/SST.00000001" | tr -d ' ')
  local open_rss
  local scan_rss
  open_rss=$(MYLSM_DB_PATH="$database" MYLSM_CURSOR_MODE=open MYLSM_CURSOR_COUNT="$count" \
    python3 "$ROOT/bench/measure_rss.py" "$WORK/open-$count.log" "$BINARY")
  rg -q 'CURSOR_OPENED' "$WORK/open-$count.log"
  scan_rss=$(MYLSM_DB_PATH="$database" MYLSM_CURSOR_MODE=scan MYLSM_CURSOR_COUNT="$count" \
    MYLSM_CURSOR_SCAN_LIMIT=64 \
    python3 "$ROOT/bench/measure_rss.py" "$WORK/scan-$count.log" "$BINARY")
  rg -q 'CURSOR_RECORDS=64' "$WORK/scan-$count.log"
  open_bytes="${open_rss#max_rss_bytes=}"
  scan_bytes="${scan_rss#max_rss_bytes=}"
  printf 'CURSOR_MEMORY_%s_OPEN=%s\n' "$count" "${open_rss#max_rss_bytes=}"
  printf 'CURSOR_MEMORY_%s_SCAN=%s\n' "$count" "${scan_rss#max_rss_bytes=}"
  printf 'CURSOR_MEMORY_%s_SST_BYTES=%s\n' "$count" "$sst_bytes"
  if (( open_bytes > 33554432 || scan_bytes > 33554432 )); then
    printf 'cursor workload exceeded its 32 MiB process budget: open=%s scan=%s\n' \
      "$open_bytes" "$scan_bytes" >&2
    return 1
  fi
  if (( scan_bytes > open_bytes + 4194304 )); then
    printf 'opening a 64-item cursor exceeded the 4 MiB allowance: open=%s scan=%s\n' \
      "$open_bytes" "$scan_bytes" >&2
    return 1
  fi
}

measure_scan 16000
measure_scan 64000
