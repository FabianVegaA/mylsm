# Owner and coordinated clients

## Purpose

A single process holds the filesystem lock and performs a database's durable operations.
Other local processes can send requests over a Unix socket. The
[Bytes/Utf8](durable-api.md) facade represents both paths through local or remote handles.

## Ownership and discovery

Exclusion uses `flock` on an open `LOCK` descriptor. The file remains on disk after
closing; its existence does not demonstrate that the database is busy. The lock is
released when the descriptor closes or the process terminates.

Canonical opening and endpoint discovery determine whether to use an existing owner.
The service process entry point is
[app/owner/mylsm_owner.bend](../../app/owner/mylsm_owner.bend). The protocol includes
version, owner generation, identifier, and operation code.

`open_existing_wait` waits only to acquire the lock after checking the manifest.
It distinguishes the immediate `Busy` result from expiration with `Timeout`;
a successful wait does not grant permission to reinterpret incompatible formats.

Each remote open queries `DescribeOwner` (operation 16) and validates the effective
options codec before returning the handle. `OptionsCodec` uses `MLO6`, u32be version 1,
and 17 u32be fields in 76 bytes. The `Bytes.create_with_options` and
`Bytes.open_existing_with_options` variants and their Utf8 counterparts reject invalid
options before opening. If an owner exists, they compare all 17 fields and return
`InvalidArgument` on a mismatch; they neither start an owner process nor modify the
existing owner's configuration. The current owner publishes defaults. The local path
accepts defaults and rejects unsupported options because it does not yet receive
configurable limits.

## Dispatch and uncertain outcomes

The owner reactor maintains multiple nonblocking connections and advances partial
headers, payloads, and responses according to readiness. Each connection allows one
pending request, without pipelining. Mutations are serialized under the single durable
handle; there are no independent concurrent writers to the files. `EINTR` and
`EAGAIN`/`EWOULDBLOCK` from `poll` or `accept` are treated as transient and return the
loop to waiting.

The owner rejects headers whose payload exceeds 16 MiB before reading or allocating
it. Preflight returns `ResourceLimit` before dispatch when an individual response bound
will not fit. If a producer exceeds its bound after dispatch, the owner responds with
an empty payload: a read receives `ResourceLimit`, and a mutation, which has already
been applied, receives `CommitUnknown`. Mutations respond with empty payloads, so the
second case does not occur in practice. Local clients retain the 1 GiB protocol cap.

The client distinguishes an undispatched request from a mutation whose response was
lost after dispatch. In the latter case, `CommitUnknown` prevents assuming that the
change did not occur. Reopen and query before deciding whether to retry; do not
automatically repeat the mutation.

## Generations and remote resources

Requests and resources are associated with an owner generation. An old handle receives
`StaleOwner` when addressing another generation. Open a new handle to discover the
current owner; do not replay old cursor or snapshot tokens against the new one.

Snapshot and cursor registries live in the owner. Their limits, closure, and SST
retention are described in [scans-and-snapshots.md](scans-and-snapshots.md).
The owner limits snapshots to 64, cursors to 4,096 in total, and cursors per snapshot
to 64. Comprehensive validation of old tokens after restarts remains pending.

## Current constraints

The owner has a runtime FIFO queue bounded by requests and bytes. Complete frames are
admitted in ascending stable-ID order, and at most one request is dispatched per tick.
A head waiting for TX credit retains its position; poll waits for readiness or a deadline
while no work is eligible. A request exceeding the queue budget receives `ResourceLimit`;
saturation receives `Busy`. The `owner_queue.sh` smoke test pauses the owner before
dispatch, admits two 64-byte frames with a budget of 128, rejects the third, cancels the
second upon detecting half-close, and admits a replacement request. Two mutations
overwrite the same key; the final value and absence of the canceled/rejected mutations
are checked before and after restart. The queue budget can be smaller than the frame
cap, so individual admission may reject a transport-valid frame.

The reactor drains readable bytes even when `poll()` also signals hangup. When an
already admitted or queued connection closes, it removes pending requests and closes
the socket before the next dispatch. A dequeued request retains its reservation in an
InFlight state until it produces the frame; it is neither requeued nor canceled after
dispatch.

After validating the 24-byte header, the owner reserves the full RX peak before reading
the payload: `48 + 3 × payload_bytes`, covering header/chunks, the assembled frame,
and the decoded payload while they coexist. Headers use fixed slots bounded by
`max_connections`; each connection also has a 28-byte control frame outside the payload
TX budget. If the individual peak exceeds `receive_bytes`, it responds `ResourceLimit`
and closes; if it fits the total limit but no credit remains, it responds `Busy` and
closes without retaining partial payload. Once the frame is complete, the reservation
passes to queue admission. An additional read on a waiting or queued connection closes
that connection, and POLLIN remains active to detect half-close; this avoids draining
pipelined requests or losing the closure signal.

Monotonic deadlines close partial frames and bound queue waiting and response writing.
Smoke tests cover a silent peer, byte-by-byte fragmentation, partial EOF, a client that
does not read, and concurrent progress. The `owner_tx_budget.sh` and
`owner_rx_budget.sh` fixtures cover TX/FIFO pressure, RX bounds, Busy, ResourceLimit,
and retry after release. Numerical oracles for reservations and peaks, an integrated
ledger/stats view, poll-spin observation, EINTR/EAGAIN injection inside the Owner,
depth metrics, and the Linux reactor matrix remain pending.

The Unix socket path is native. JavaScript effects return an unsupported capability;
Bun FFI locking does not imply support for the Unix server in JavaScript.
See the [effects boundary](../standards/host-effects.md).

## Implementation and checks

- Service and clients: [Owner.bend](../../src/coordinator/Owner.bend),
  [ByteClient.bend](../../src/coordinator/ByteClient.bend), and
  [Client.bend](../../src/coordinator/Client.bend).
- Transport: [Protocol.bend](../../src/coordinator/Protocol.bend),
  [Io.bend](../../src/coordinator/Io.bend), and [UnixSocketIo.bend](../../src/coordinator/UnixSocketIo.bend).
- Contracts: [CoordinatorPolicy.bend](../../laws/CoordinatorPolicy.bend),
  [ClientPolicy.bend](../../laws/ClientPolicy.bend), [QueuePolicy.bend](../../laws/QueuePolicy.bend),
  and [OwnerGeneration.bend](../../laws/OwnerGeneration.bend), with their [witnesses](../../proofs/).
- Integration: [coordinator_owner_socket.sh](../../bench/smoke/coordinator_owner_socket.sh),
  [coordinator_owner_cursor_dispatch.sh](../../bench/smoke/coordinator_owner_cursor_dispatch.sh),
  [owner_frame_limit.sh](../../bench/smoke/owner_frame_limit.sh),
  [owner_generation_client.bend](../../bench/smoke/owner_generation_client.bend),
  [owner_reactor_fairness.sh](../../bench/smoke/owner_reactor_fairness.sh),
  [owner_reactor_deadline.sh](../../bench/smoke/owner_reactor_deadline.sh), and
  [owner_queue.sh](../../bench/smoke/owner_queue.sh).
- Lost responses: [coordinator_commit_unknown.sh](../../bench/crash/coordinator_commit_unknown.sh).
  The [acceptance report](../../bench/results/mylsm-0.6.0.0-acceptance.md) records
  the six exercised failure points and their recovery results.
