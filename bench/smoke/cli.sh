#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
trap 'rm -rf .mylsm-demo-data .mylsm .mylsm-cli-test .mylsm-cli-legacy .mylsm-cli-legacy.log .mylsm-cli-bulk .mylsm-cli-bulk.db .mylsm-cli-bulk.log .mylsm-cli-empty .mylsm-cli-empty.db .mylsm-cli-empty.log .mylsm-cli-limit .mylsm-cli-limit.log .mylsm-cli-test.log .mylsm-cli-recover.log .mylsm-console-smoke.log .mylsm-cli-export.db .mylsm-cli-attached.log .mylsm-sst-v3-io-smoke.tbl bench-data' EXIT
sh -n scripts/mylsm.sh
printf 'hello\n' | bend bench/smoke/cli_attached.bend
scripts/mylsm.sh doctor
scripts/mylsm.sh check
scripts/mylsm.sh fuzz
scripts/mylsm.sh bench
bend bench/smoke/sst_v3_io.bend
printf 'hello\n' | MYLSM_TEST_ENV=world bend bench/smoke/console.bend >.mylsm-console-smoke.log
grep '^line=hello$' .mylsm-console-smoke.log
grep '^env=world$' .mylsm-console-smoke.log
rm -f .mylsm-console-smoke.log
MYLSM_DEVICE=cpu scripts/mylsm.sh demo
MYLSM_DEVICE=auto scripts/mylsm.sh demo
printf 'threads 2\nput a 1\nput "hello world" "value with spaces"\nget "hello world"\nexport .mylsm-cli-export.db\ndel "hello world"\nimport .mylsm-cli-export.db\nget "hello world"\ntiming once\nget a\ntime get a\nstats\nscan a z\nflush\ncompact\nmaintain\nexit\n' |
  MYLSM_DEVICE=cpu scripts/mylsm.sh repl --dir .mylsm-cli-test >.mylsm-cli-test.log

grep '^restarting with threads=2$' .mylsm-cli-test.log
grep '^OK$' .mylsm-cli-test.log
grep '^1$' .mylsm-cli-test.log
grep '^time_ms=' .mylsm-cli-test.log
grep '^a=1$' .mylsm-cli-test.log
grep '^value with spaces$' .mylsm-cli-test.log
grep '^OK export$' .mylsm-cli-test.log
grep '^OK import$' .mylsm-cli-test.log
grep '^entries=2 ' .mylsm-cli-test.log
grep '^OK flush$' .mylsm-cli-test.log
grep '^OK compact$' .mylsm-cli-test.log
grep '^error: unknown command: maintain$' .mylsm-cli-test.log
printf 'get a\nexit\n' |
  MYLSM_DEVICE=cpu scripts/mylsm.sh repl --dir .mylsm-cli-test >.mylsm-cli-recover.log
grep '^1$' .mylsm-cli-recover.log
MYLSM_DB_PATH=.mylsm-cli-legacy bend bench/smoke/legacy_sst_io.bend >/dev/null
legacy_before=$(cd .mylsm-cli-legacy && find . -type f -exec cksum {} + | sort)
if printf 'get a\nexit\n' | MYLSM_DEVICE=cpu scripts/mylsm.sh repl --dir .mylsm-cli-legacy >.mylsm-cli-legacy.log 2>&1; then
  cat .mylsm-cli-legacy.log
  exit 1
fi
grep -q 'database uses the 0.5 format; run migrate_legacy first' .mylsm-cli-legacy.log
legacy_after=$(cd .mylsm-cli-legacy && find . -type f -exec cksum {} + | sort)
[ "$legacy_before" = "$legacy_after" ]
repl() {
  MYLSM_DEVICE=cpu scripts/mylsm.sh repl --dir "$1"
}
puts() {
  i=$1
  while [ "$i" -lt "$2" ]; do printf 'put k%s v%s\n' "$i" "$i"; i=$((i + 1)); done
}
printf '%s\nexit\n' "$(puts 0 150)" | repl .mylsm-cli-bulk >.mylsm-cli-bulk.log
printf '%s\nexport .mylsm-cli-bulk.db\nexit\n' "$(puts 150 300)" | repl .mylsm-cli-bulk >.mylsm-cli-bulk.log
grep -q '^OK export$' .mylsm-cli-bulk.log
[ "$(stat -c %a .mylsm-cli-bulk.db 2>/dev/null || stat -f %Lp .mylsm-cli-bulk.db)" = 600 ]
rm -rf .mylsm-cli-bulk
printf 'import .mylsm-cli-bulk.db\nget k299\nexit\n' | repl .mylsm-cli-bulk >.mylsm-cli-bulk.log
grep -q '^OK import$' .mylsm-cli-bulk.log
grep -q '^v299$' .mylsm-cli-bulk.log
printf 'export .mylsm-cli-empty.db\nexit\n' | repl .mylsm-cli-empty >.mylsm-cli-empty.log
printf 'import .mylsm-cli-empty.db\nexit\n' | repl .mylsm-cli-empty >.mylsm-cli-empty.log
grep -q '^OK import$' .mylsm-cli-empty.log
helps=$(i=0; while [ "$i" -lt 255 ]; do printf 'help\n'; i=$((i + 1)); done)
printf '%s\nput zz 1\n' "$helps" | MYLSM_BATCH_CAP=4 repl .mylsm-cli-limit >.mylsm-cli-limit.log
grep -q '^session command limit reached$' .mylsm-cli-limit.log
printf 'get zz\nexit\n' | repl .mylsm-cli-limit >.mylsm-cli-limit.log
grep -q '^1$' .mylsm-cli-limit.log
rm -f .mylsm-cli-test.log .mylsm-cli-recover.log
