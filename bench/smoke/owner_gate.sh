#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
export TMPDIR=${MYLSM_SOCKET_TMPDIR:-/tmp}

(cd "$ROOT/bench/smoke" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest test_owner_transport_oracle)

for smoke in \
  smoke/coordinator_owner_dispatch.sh \
  smoke/coordinator_owner_cursor_dispatch.sh \
  smoke/coordinator_owner_snapshot_dispatch.sh \
  smoke/coordinator_owner_socket.sh \
  smoke/owner_generation.sh \
  smoke/owner_generation_tokens.sh \
  smoke/owner_options.sh \
  smoke/owner_queue.sh \
  smoke/owner_reactor_deadline.sh \
  smoke/owner_reactor_fairness.sh \
  smoke/owner_reactor_write_backpressure.sh \
  smoke/owner_retired_sst.sh \
  smoke/owner_rx_budget.sh \
  smoke/owner_tx_budget.sh \
  smoke/owner_frame_limit.sh \
  smoke/owner_response_limit.sh \
  smoke/owner_stale_endpoint.sh \
  smoke/unix_socket_poll_many.sh \
  crash/coordinator_commit_unknown.sh \
  crash/owner_endpoint_lifecycle.sh
do
  printf 'OWNER GATE RUN %s\n' "$smoke"
  bash "$ROOT/bench/$smoke"
done

printf '%s\n' 'OWNER GATE PASS'
