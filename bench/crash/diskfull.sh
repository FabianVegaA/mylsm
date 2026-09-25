#!/usr/bin/env bash
# Disk-full (real ramdisk) plus permissions fault suites.
# Thin launcher: guards, build, run, grep-assertions. All verdicts in Bend.
# Suite 1 (ENOSPC): ramdisk -> small acked run -> fill disk -> writes must
#   fail closed (nonzero exit, no new acks) -> free space -> same keys verify.
# Suite 2 (permissions): chmod matrix over wal.log, one l0 table, MANIFEST
#   and the DB dir; every attempt fails closed; restore + re-verify healthy.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
BUILD_DIR="$ROOT/.mylsm/build"
BINARY="$BUILD_DIR/million-writes"
SOURCE="$ROOT/bench/workload/million_writes.bend"
export CC=/usr/bin/clang

if [[ $(uname -s) != Darwin && $(uname -s) != Linux ]]; then
  echo "unsupported platform: $(uname -s)" >&2
  exit 2
fi

RAMDISK_MNT=""
cleanup() {
  if [[ -n "$RAMDISK_MNT" ]]; then
    if [[ $(uname -s) == Darwin ]]; then
      hdiutil detach "$RAMDISK_MNT" >/dev/null 2>&1 || true
    else
      umount "$RAMDISK_MNT" >/dev/null 2>&1 || true
    fi
    rmdir "$RAMDISK_MNT" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$ROOT/.mylsm-diskfull-work" "$ROOT/.mylsm-diskfull-ramdisk-mnt"
}
trap cleanup EXIT

echo "phase=build status=starting"
bend "$SOURCE" -o "$BINARY"
echo "phase=build status=complete binary=$BINARY"

# --- Suite 1: ENOSPC on a real ramdisk ---
if [[ $(uname -s) == Darwin ]]; then
  RAMDISK_MNT="$ROOT/.mylsm-diskfull-ramdisk-mnt"
  mkdir -p -- "$RAMDISK_MNT"
  DEV=$(hdiutil attach -nomount ram://131072) || { echo "SKIP disk suite: ramdisk attach failed (needs mount privileges)" >&2; DEV=""; }
  if [[ -n "${DEV:-}" ]]; then
    if ! newfs_hfs -v MyLSMDisk "$DEV" >/dev/null 2>&1 || ! mount -t hfs "$DEV" "$RAMDISK_MNT" >/dev/null 2>&1; then
      echo "SKIP disk suite: ramdisk format/mount failed (needs mount privileges)" >&2
      hdiutil detach "$DEV" >/dev/null 2>&1 || true
      RAMDISK_MNT=""
    fi
  else
    RAMDISK_MNT=""
  fi
else
  RAMDISK_MNT="$ROOT/.mylsm-diskfull-ramdisk-mnt"
  mkdir -p -- "$RAMDISK_MNT"
  if ! mount -t tmpfs -o size=64M tmpfs "$RAMDISK_MNT" >/dev/null 2>&1; then
    echo "SKIP disk suite: tmpfs mount failed (needs privileges)" >&2
    RAMDISK_MNT=""
  fi
fi

if [[ -n "$RAMDISK_MNT" ]]; then
  RDDIR="$RAMDISK_MNT/db"
  echo "phase=enosp-prepare status=starting"
  MYLSM_BENCH_RESET=1 MYLSM_BENCH_WRITES=1000 MYLSM_BENCH_DIR="$RDDIR" "$BINARY" --threads 4 >"$BUILD_DIR/diskfull-pre.log" 2>&1
  grep -q '^phase=pre_recovery samples=pass$' "$BUILD_DIR/diskfull-pre.log"
  echo "phase=enosp-prepare status=complete acknowledged=1000"
  # Fill the ramdisk to ENOSPC (dd failure is the expected signal).
  set +e
  dd if=/dev/zero of="$RAMDISK_MNT/filler" bs=1m 2>/dev/null
  set -e
  echo "phase=enosp-full status=confirmed filler_bytes=$(wc -c < "$RAMDISK_MNT/filler" | tr -d ' ')"
  # Writes must now fail closed: nonzero exit, no new acknowledgements.
  set +e
  MYLSM_BENCH_WRITES=5000 MYLSM_BENCH_DIR="$RDDIR" "$BINARY" --threads 4 >"$BUILD_DIR/diskfull-fail.log" 2>&1
  FAIL_STATUS=$?
  set -e
  if [[ "$FAIL_STATUS" -eq 0 ]]; then
    echo "ENOSPC failure not observed: writes succeeded on a full disk" >&2
    exit 1
  fi
  ! grep -q '^phase=pre_recovery samples=pass$' "$BUILD_DIR/diskfull-fail.log" || { echo "fail-closed violation: samples passed while full" >&2; exit 1; }
  echo "phase=enosp-write status=fail-closed exit=$FAIL_STATUS"
  # Free space and prove the pre-fill acknowledged state is invariant.
  rm -f -- "$RAMDISK_MNT/filler"
  MYLSM_BENCH_WRITES=1000 MYLSM_BENCH_DIR="$RDDIR" "$BINARY" --threads 4 >"$BUILD_DIR/diskfull-post.log" 2>&1
  grep -q '^phase=pre_recovery samples=pass$' "$BUILD_DIR/diskfull-post.log"
  grep -q '^phase=post_recovery samples=pass$' "$BUILD_DIR/diskfull-post.log"
  echo "phase=enosp-reopen status=complete acknowledged_invariant=pass"
  echo "DISKFAULT CLEAN"
else
  echo "DISKFAULT SKIP (no ramdisk)"
fi

# --- Suite 2: permissions matrix on a repo-local dir ---
WORK="$ROOT/.mylsm-diskfull-work"
rm -rf -- "$WORK"
echo "phase=perm-prepare status=starting"
MYLSM_BENCH_WRITES=9000 MYLSM_BENCH_DIR="$WORK" "$BINARY" --threads 4 >"$BUILD_DIR/perm-pre.log" 2>&1
grep -q '^phase=pre_recovery samples=pass$' "$BUILD_DIR/perm-pre.log"
echo "phase=perm-prepare status=complete acknowledged=9000"

perm_case() {
  local name=$1 target=$2 mode=$3 count=$4
  chmod "$mode" "$target"
  set +e
  MYLSM_BENCH_WRITES="$count" MYLSM_BENCH_DIR="$WORK" "$BINARY" --threads 4 >"$BUILD_DIR/perm-$name.log" 2>&1
  local st=$?
  set -e
  chmod u+rwX "$target"
  if [[ "$st" -eq 0 ]]; then
    if grep -q '^phase=pre_recovery samples=pass$' "$BUILD_DIR/perm-$name.log"; then
      echo "perm case $name: unexpectedly healthy under restriction" >&2
      return 1
    else
      echo "perm case $name: exited 0 but samples failed" >&2
      return 1
    fi
  fi
  echo "perm_case=$name status=fail-closed exit=$st"
  MYLSM_BENCH_WRITES=100 MYLSM_BENCH_DIR="$WORK" "$BINARY" --threads 4 >"$BUILD_DIR/perm-$name-healthy.log" 2>&1
  grep -q '^phase=pre_recovery samples=pass$' "$BUILD_DIR/perm-$name-healthy.log"
  echo "perm_case=$name restore=healthy"
}

TABLE=$(ls "$WORK"/l0/*.tbl 2>/dev/null | head -1 || true)
perm_case "wal-readonly" "$WORK/wal.log" 400 100
if [[ -n "$TABLE" ]]; then
  perm_case "table-unreadable" "$TABLE" 000 100
else
  echo "perm case table-unreadable: SKIP (no l0 table present)"
fi
if [[ -f "$WORK/MANIFEST" ]]; then
  perm_case "manifest-unreadable" "$WORK/MANIFEST" 000 100
else
  echo "perm case manifest-unreadable: SKIP (no MANIFEST present)"
fi
# Directory denial only bites when the engine must create files: force a
# flush-sized run so table creation + renames hit the read-only dir.
perm_case "dir-readonly" "$WORK" 500 9000
rm -rf -- "$WORK"
echo "PERM CLEAN"
