#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
trap 'rm -rf .mylsm-demo-data .mylsm .mylsm-cli-test .mylsm-cli-test.log .mylsm-cli-recover.log .mylsm-console-smoke.log .mylsm-cli-export.db' EXIT
sh -n bin/mylsm
bin/mylsm doctor
bin/mylsm check
printf 'hello\n' | MYLSM_TEST_ENV=world bend bench/console_smoke.bend >.mylsm-console-smoke.log
grep '^line=hello$' .mylsm-console-smoke.log
grep '^env=world$' .mylsm-console-smoke.log
rm -f .mylsm-console-smoke.log
MYLSM_DEVICE=cpu bin/mylsm demo
MYLSM_DEVICE=auto bin/mylsm demo
printf 'put a 1\nput "hello world" "value with spaces"\nget "hello world"\nexport .mylsm-cli-export.db\ndel "hello world"\nimport .mylsm-cli-export.db\nget "hello world"\ntiming once\nget a\ntime get a\nstats\nscan a z\nmaintain\nexit\n' |
  MYLSM_DEVICE=cpu bin/mylsm repl --dir .mylsm-cli-test >.mylsm-cli-test.log

grep '^OK$' .mylsm-cli-test.log
grep '^1$' .mylsm-cli-test.log
grep '^time_ms=' .mylsm-cli-test.log
grep '^a=1$' .mylsm-cli-test.log
grep '^value with spaces$' .mylsm-cli-test.log
grep '^OK export$' .mylsm-cli-test.log
grep '^OK import$' .mylsm-cli-test.log
printf 'get a\nexit\n' |
  MYLSM_DEVICE=cpu bin/mylsm repl --dir .mylsm-cli-test >.mylsm-cli-recover.log
grep '^1$' .mylsm-cli-recover.log
rm -f .mylsm-cli-test.log .mylsm-cli-recover.log
