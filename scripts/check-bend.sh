set -eu

if [ "$#" -eq 0 ]; then
  exit 0
fi

if [ -n "${BOLT_BIN:-}" ]; then
  bolt_bin=$BOLT_BIN
elif command -v bolt >/dev/null 2>&1; then
  bolt_bin=bolt
else
  printf '%s\n' 'Bolt is required: enter nix develop or set BOLT_BIN.' >&2
  exit 127
fi

if ! command -v "$bolt_bin" >/dev/null 2>&1; then
  printf 'Bolt executable not found: %s\n' "$bolt_bin" >&2
  exit 127
fi

lint_log=$(mktemp "${TMPDIR:-/tmp}/mylsm-lint.XXXXXX")
trap 'rm -f "$lint_log"' EXIT HUP INT TERM

lint_status=0
"$bolt_bin" "$@" > "$lint_log" 2>&1 || lint_status=$?
if [ "$lint_status" -ne 0 ]; then
  cat "$lint_log"
  exit "$lint_status"
fi

result=0
awk '
  /: (error|warning): S002: / { next }
  /: (error|warning): S003: / {
    location = $0
    sub(/: (error|warning): S003: .*/, "", location)
    sub(/:[0-9]+$/, "", location)
    line_number = location
    sub(/^.*:/, "", line_number)
    sub(/:[0-9]+$/, "", location)
    for (line = 0; line < line_number; line++) {
      read_status = (getline header < location)
      if (read_status <= 0) break
    }
    close(location)
    if (read_status > 0 && length(header) <= 200) next
  }
  /: (error|warning): / { print; failed = 1 }
  END { exit failed }
' "$lint_log" || result=1

awk '
  length > 200 {
    printf "%s:%d: line exceeds 200 characters (%d)\n", FILENAME, FNR, length
    failed = 1
  }
  END { exit failed }
' "$@" || result=1

exit "$result"
