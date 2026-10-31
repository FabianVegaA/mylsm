#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
trap 'rm -rf .mylsm-demo-data .mylsm .mylsm-cli-test .mylsm-cli-legacy .mylsm-cli-legacy.log .mylsm-cli-test.log .mylsm-cli-recover.log .mylsm-console-smoke.log .mylsm-cli-export.db .mylsm-cli-attached.log .mylsm-sst-v3-io-smoke.tbl bench-data' EXIT
sh -n scripts/mylsm.sh
printf 'hello\n' | bend bench/smoke/cli_attached.bend
scripts/mylsm.sh doctor
scripts/mylsm.sh check
scripts/mylsm.sh fuzz
scripts/mylsm.sh bench
bend bench/smoke/sst_v3_io.bend
bash bench/smoke/durable_session.sh
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
rm -f .mylsm-cli-test.log .mylsm-cli-recover.log
