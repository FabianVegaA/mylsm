#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export MYLSM_ROOT=$ROOT
exec bend "$ROOT/app/cli/main.bend" -- "$@"
