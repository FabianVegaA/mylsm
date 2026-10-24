{
  runCommand,
  coreutils,
  gnugrep,
  mylsm,
}:

runCommand "mylsm-installation-check"
  {
    nativeBuildInputs = [
      mylsm
      coreutils
      gnugrep
    ];
  }
  ''
    mkdir work
    cd work
    export MYLSM_THREADS=1
    mylsm --help > help.log
    grep -q 'Usage: mylsm' help.log
    mylsm doctor > doctor.log
    grep -qx '  CPU threads: 1' doctor.log
    mylsm demo > demo.log
    grep -qx 'MYLSM DEMO OK' demo.log
    printf 'put saved value\nthreads 2\nruntime\nget saved\nexit\n' |
      mylsm repl --dir 'database with spaces' > first.log
    grep -qx 'restarting with threads=2' first.log
    grep -q 'threads=2' first.log
    grep -qx 'value' first.log
    printf 'get saved\nexit\n' |
      mylsm repl --dir 'database with spaces' > reopened.log
    grep -qx 'value' reopened.log
    for command in check fuzz bench build run; do
      status=0
      mylsm "$command" > rejected.log 2>&1 || status=$?
      test "$status" -eq 2
      grep -q 'command requires the development checkout' rejected.log
    done
    if MYLSM_DEVICE=gpu mylsm repl --dir forbidden > gpu.log 2>&1; then
      exit 1
    fi
    grep -q 'CPU execution only' gpu.log
    test ! -e forbidden
    if MYLSM_THREADS=0 mylsm repl --dir invalid > invalid.log 2>&1; then
      exit 1
    fi
    test ! -e invalid
    status=0
    mylsm repl --unknown > usage.log 2>&1 || status=$?
    test "$status" -eq 2
    grep -q 'usage: mylsm repl' usage.log
    status=0
    mylsm repl --dir "" > empty.log 2>&1 || status=$?
    test "$status" -eq 2
    grep -q 'REPL directory cannot be empty' empty.log
    touch $out
  ''
