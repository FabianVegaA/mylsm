import Base
import ../ByteDurableDb.bend as ByteDb
import ../StorageBytes.bend as StorageBytes
import ../ResourceOptions.bend as ResourceOptions
import ./Operation.bend as Operation
import ./OptionsCodec.bend as OptionsCodec
import ./Protocol.bend as Protocol
import ./CoordinatorPolicy.bend as Policy
import ./ClientPolicy.bend as ClientPolicy
import ./ResponseBoundPolicy.bend as ResponseBound
import ./OwnerGeneration.bend as Generation
import ./Io.bend as Io
import ./UnixSocketIo.bend as UnixSocket
import ./UnixSocketTypes.bend as SocketTypes
import ./ConnectionStore.bend as Connections
import ./ConnectionPolicy.bend as ConnectionPolicy
import ./RequestQueue.bend as RequestQueue
import ./TransportBudgetPolicy.bend as TxPolicy
import ./TransportObservation.bend as Observation
import ./QueuePolicy.bend as QueuePolicy
import ./OwnerSnapshotStore.bend as SnapshotStore
import ./OwnerCursorStore.bend as CursorStore
import ../scan/VisibleCursor.bend as VisibleCursor
import ../scan/RangeCursor.bend as RangeCursor
import ../ByteMemTable.bend as ByteMemTable
import ../ByteManifest.bend as ByteManifest
import ../ByteManifestIo.bend as ByteManifestIo
import ./CursorCodec.bend as CursorCodec
import ./StatsCodec.bend as StatsCodec
import ../Fs.bend as Fs
import ../CrashPoint.bend as CrashPoint
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Retains request identifiers while the owner prepares a response.
def nat.duplicate.pair.from(copies: Nat & Nat) -> Nat & Nat:
  match copies:
    case (first, second): (first, second)

def nat.duplicate.sigma(+value: Nat) -> Nat & Nat:
  (value, value)

def nat.sigma(first: Nat, second: Nat) -> Nat & Nat:
  Tuple{first, second}

# Carries the state for ReplyContext.
type ReplyContext is Type:
  ReplyContext{version: U32 & U32,
    generation: U32 & U32, request_id: U32 & U32,
    options: ResourceOptions.Options}

# Carries the durable handle and owner resources through one completed request.
type DispatchResult is Type:
  DispatchResult{handle: ByteDb.Handle, snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, response: Protocol.Response}

# Owns the listening socket, durable handle, endpoint, and lifecycle state.
type ServiceState is Type:
  Serving{server: File, handle: ByteDb.Handle, endpoint: String,
    generation: U32, options: ResourceOptions.Options,
    snapshots: SnapshotStore.Store, cursors: CursorStore.Store}
  ReactorServing{server: File, handle: ByteDb.Handle, endpoint: String,
    generation: U32, options: ResourceOptions.Options,
    snapshots: SnapshotStore.Store, cursors: CursorStore.Store,
    connections: List<&1, Connections.Connection>, next_connection_id: U32,
    accepted_sequence: Nat, queue: RequestQueue.Queue}
  Stopping{server: File, handle: ByteDb.Handle, endpoint: String,
    reason: String, cursors: CursorStore.Store}

# Carries one bounded owner-cursor read across visible-source steps.
type CursorReadState is Type:
  CursorReadNeed{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, context: ReplyContext, cursor_id: U32,
    release_id: U32, cursor: VisibleCursor.Cursor}
  CursorReadStep{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, context: ReplyContext, cursor_id: U32,
    release_id: U32, step: VisibleCursor.Step}

# Carries the state for ReactorContext.
type ReactorContext is Type:
  ReactorContext{handle: ByteDb.Handle, endpoint: String,
    generation: U32, options: ResourceOptions.Options,
    snapshots: SnapshotStore.Store, cursors: CursorStore.Store,
    connections: List<&1, Connections.Connection>,
    next_connection_id: U32, accepted_sequence: Nat,
    queue: RequestQueue.Queue}

# Carries the state for ReactorPollPrepared.
type ReactorPollPrepared is Type:
  ReactorPollPrepared{metadata: List<&1, Connections.Metadata>,
    context: ReactorContext, interests: List<SocketTypes.PollInterest>,
    timeout_ms: U32}

# Carries the state for PollTimeoutInput.
type PollTimeoutInput is Type:
  PollTimeoutInput{interests: List<SocketTypes.PollInterest>,
    has_connections: Bool, queue_active: Bool}

# Carries the state for EncodedDispatch.
type EncodedDispatch is Type:
  EncodedDispatch{handle: ByteDb.Handle, snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, bytes: Bytes.Bytes,
    reservation: TxPolicy.FrameReservation}

# Carries the state for CursorHeadBudget.
type CursorHeadBudget is Type:
  CursorHeadBudget{cursors: CursorStore.Store,
    queue: RequestQueue.Queue, bound: TxPolicy.BoundDecision}

# Carries the state for ResponseBoundRequest.
type ResponseBoundRequest is Type:
  ResponseBoundRequest{request: Protocol.Request,
    bound: TxPolicy.BoundDecision}

# Carries the state for ResponseBoundState.
type ResponseBoundState is Type:
  ResponseBoundState{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store, cursors: CursorStore.Store,
    result: ResponseBoundRequest}

# Carries the state for ResponsePreflightConnection.
type ResponsePreflightConnection is Type:
  ResponsePreflightConnection{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store, cursors: CursorStore.Store,
    connection: Connections.Connection, new_cursor: Maybe<&2, U32>}

# Carries the state for ResponsePreflight.
type ResponsePreflight is Type:
  PreflightBounded{request: Protocol.Request,
    bound: TxPolicy.BoundDecision}
  PreflightGet{request: Protocol.Request, key: Bytes.Bytes}
  PreflightStats{request: Protocol.Request}
  PreflightSnapshotGet{request: Protocol.Request, snapshot_id: U32,
    key: Bytes.Bytes}
  PreflightCursorNext{request: Protocol.Request, cursor_id: U32}

# Carries the state for ResponsePreflightState.
type ResponsePreflightState is Type:
  PreflightScanning{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store,
    remaining: List<&1, Connections.Connection>,
    retained: List<&1, Connections.Connection>, response_bytes: U32,
    capacity: Nat, seen_cursor_ids: List<&2, U32>}
  PreflightMeasured{result: ResponsePreflightConnection,
    remaining: List<&1, Connections.Connection>,
    retained: List<&1, Connections.Connection>, response_bytes: U32,
    capacity: Nat, seen_cursor_ids: List<&2, U32>}

# Carries the state for ResponsePreflightResult.
type ResponsePreflightResult is Type:
  PreflightReady{handle: ByteDb.Handle, snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store,
    connections: List<&1, Connections.Connection>}
  PreflightFuelExhausted{state: ResponsePreflightState}

# Carries the state for ResponsePreflightResources.
type ResponsePreflightResources is Type:
  ResponsePreflightResources{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store, cursors: CursorStore.Store,
    connections: List<&1, Connections.Connection>}

# Carries the state for ReactorAdmissionState.
type ReactorAdmissionState is Type:
  AdmissionScanning{remaining: List<&1, Connections.Connection>,
    retained: List<&1, Connections.Connection>, queue: RequestQueue.Queue,
    accepted_sequence: Nat, response_deadline: Nat,
    max_count: Nat, max_bytes: Nat, response_bytes: U32}
  AdmissionEvaluated{result: Connections.AdmissionResult,
    remaining: List<&1, Connections.Connection>,
    retained: List<&1, Connections.Connection>,
    accepted_sequence: Nat, response_deadline: Nat,
    max_count: Nat, max_bytes: Nat, response_bytes: U32}

# Carries the state for ReactorAdmissionResult.
type ReactorAdmissionResult is Type:
  AdmissionReady{connections: List<&1, Connections.Connection>,
    queue: RequestQueue.Queue, accepted_sequence: Nat}
  AdmissionFuelExhausted{state: ReactorAdmissionState}

# Carries the state for ReactorCleanupResult.
type ReactorCleanupResult is Type:
  ReactorCleaned{connections: List<&1, Connections.Connection>,
    queue: RequestQueue.Queue}

# Carries the state for ReactorCloseAction.
type ReactorCloseAction is Type:
  CloseConnection{id: U32, socket: File, cancelled: List<&1, RequestQueue.Pending>}

# Carries the state for ReactorCleanupState.
type ReactorCleanupState is Type:
  CleanupScanning{remaining: List<&1, Connections.Connection>,
    retained: List<&1, Connections.Connection>,
    actions: List<&1, ReactorCloseAction>, queue: RequestQueue.Queue}
  CleanupCancelled{remaining: List<&1, Connections.Connection>,
    retained: List<&1, Connections.Connection>,
    actions: List<&1, ReactorCloseAction>, id: U32, socket: File,
    result: RequestQueue.CancelResult}

# Carries the state for ReactorCleanupFoldResult.
type ReactorCleanupFoldResult is Type:
  CleanupFolded{connections: List<&1, Connections.Connection>,
    actions: List<&1, ReactorCloseAction>, queue: RequestQueue.Queue}
  CleanupFuelExhausted{state: ReactorCleanupState}

# Carries the state for ReactorReadState.
type ReactorReadState is Type:
  ReadScanning{remaining: List<&1, Connections.Connection>,
    retained: List<&1, Connections.Connection>,
    events: List<&2, SocketTypes.ReadyEvent>, now: Nat,
    max_payload_bytes: Nat, queue_deadline_ms: Nat,
    rx_limit: Nat, rx_used: Nat}
  ReadProcessed{remaining: List<&1, Connections.Connection>,
    retained: List<&1, Connections.Connection>,
    events: List<&2, SocketTypes.ReadyEvent>, now: Nat,
    max_payload_bytes: Nat, queue_deadline_ms: Nat,
    rx_limit: Nat, rx_used: Nat,
    processed: Connections.Connection & Nat}

# Carries the state for ReactorReadResult.
type ReactorReadResult is Type:
  ReadCompleted{connections: List<&1, Connections.Connection>}
  ReadFuelExhausted{state: ReactorReadState}

# Carries the state for ReactorAcceptState.
type ReactorAcceptState is Type:
  AcceptPolling{server: File, context: ReactorContext}
  AcceptObserved{context: ReactorContext,
    pair: File & Result<&1, &1, UnixSocket.Error, File>}
  AcceptInstalled{pair: File & ReactorContext}

# Carries the state for ConnectionDeadline.
type ConnectionDeadline is Data:
  HasDeadline{at: Nat}
  NoDeadline{}

def reactor.state(server: File, context: ReactorContext) -> ServiceState:
  match context:
    case ReactorContext{handle, endpoint, generation, +options, snapshots,
      cursors, connections, next_connection_id, accepted_sequence, queue}:
      ReactorServing{server, handle, endpoint, generation, options,
        snapshots, cursors, connections, next_connection_id,
        accepted_sequence, queue}

def reactor.payload.connection(
  pair: Connections.Connection & Connections.PayloadStatus
) -> Connections.Connection:
  match pair:
    case (connection, _): connection

def protocol.u32.duplicate.pair(+value: U32) -> U32 & U32:
  (value, value)

def reactor.close.connection(
  connection: Connections.Connection
) -> Connections.Connection:
  match connection:
    case Connections.Connection{id, socket, poll_events, _}:
      Connections.Connection{id, socket, poll_events, Connections.Closing{}}

def reactor.phase.deadline(phase: Connections.Phase) -> ConnectionDeadline:
  match phase:
    case Connections.ReadingHeader{_, _, deadline_ms}:
      HasDeadline{deadline_ms}
    case Connections.ReadingPayload{_, _, _, _, deadline_ms}:
      HasDeadline{deadline_ms}
    case Connections.AwaitingAdmission{_, deadline_ms, _}:
      HasDeadline{deadline_ms}
    case Connections.WaitingAdmission{pending}:
      match pending:
        case RequestQueue.Pending{_, _, deadline_ms, _, _, _}:
          HasDeadline{deadline_ms}
    case Connections.WritingResponse{_, _, deadline_ms, _}:
      HasDeadline{deadline_ms}
    case _:
      NoDeadline{}

def reactor.expire.decision(
  connection: Connections.Connection,
  decision: ConnectionPolicy.DeadlineDecision
) -> Connections.Connection:
  match decision:
    case ConnectionPolicy.Continue{}: connection
    case ConnectionPolicy.Expire{}: reactor.close.connection(connection)

def reactor.expire.connection(
  connection: Connections.Connection,
  +now: Nat
) -> Connections.Connection:
  match connection:
    case Connections.Connection{id, socket, poll_events,
      Connections.ReadingHeader{chunks, received_bytes, +deadline_ms}}:
      reactor.expire.decision(
        Connections.Connection{id, socket, poll_events,
          Connections.ReadingHeader{chunks, received_bytes, deadline_ms}},
        ConnectionPolicy.deadline(now, deadline_ms))
    case Connections.Connection{id, socket, poll_events,
      Connections.ReadingPayload{header, chunks, expected_bytes,
        received_bytes, +deadline_ms}}:
      reactor.expire.decision(
        Connections.Connection{id, socket, poll_events,
          Connections.ReadingPayload{header, chunks, expected_bytes,
            received_bytes, deadline_ms}},
        ConnectionPolicy.deadline(now, deadline_ms))
    case Connections.Connection{id, socket, poll_events,
      Connections.AwaitingAdmission{request, +deadline_ms, encoded_bytes}}:
      reactor.expire.decision(
        Connections.Connection{id, socket, poll_events,
          Connections.AwaitingAdmission{request, deadline_ms, encoded_bytes}},
        ConnectionPolicy.deadline(now, deadline_ms))
    case Connections.Connection{id, socket, poll_events,
      Connections.WritingResponse{encoded, written_bytes, +deadline_ms,
        reservation}}:
      reactor.expire.decision(
        Connections.Connection{id, socket, poll_events,
          Connections.WritingResponse{encoded, written_bytes, deadline_ms,
            reservation}},
        ConnectionPolicy.deadline(now, deadline_ms))
    case connection:
      connection

def reactor.header.control(
  connection: Connections.Connection,
  status_code: U32,
  deadline_ms: Nat
) -> Connections.Connection:
  match connection:
    case Connections.Connection{+id, socket, _,
      Connections.ReadingPayload{header, _, _, _, _}}:
      Connections.Connection{id, socket, 4,
        Connections.WritingResponse{
          Protocol.header.control(header, status_code), 0, deadline_ms,
          TxPolicy.tx.frame.control(id)}}
    case connection:
      reactor.close.connection(connection)

def reactor.header.payload.reserved(
  connection: Connections.Connection,
  expected_payload_bytes: U32,
  +max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  decision: TxPolicy.RxReservationDecision
) -> Connections.Connection:
  match expected_payload_bytes:
    case 0:
      reactor.payload.connection(Connections.payload.empty(connection,
        max_payload_bytes, queue_deadline_ms))
    case _:
      match decision:
        case TxPolicy.ReserveFrame{_}: connection
        case TxPolicy.WaitForFrameCredit{_}:
          reactor.header.control(connection, 3, queue_deadline_ms)
        case TxPolicy.RejectFrame{_}:
          reactor.header.control(connection, 5, queue_deadline_ms)

def reactor.header.payload(
  connection: Connections.Connection,
  expected_payload_bytes: U32 & U32,
  +max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> Connections.Connection:
  match expected_payload_bytes:
    case (phase_expected, reserve_expected):
      reactor.header.payload.reserved(connection, phase_expected,
        max_payload_bytes, queue_deadline_ms,
        TxPolicy.rx.frame.reserve(rx_used,
          TxPolicy.rx.frame.peak(U32.to_nat(reserve_expected)),
          rx_limit))

def reactor.header.progress(
  pair: Connections.Connection & Connections.HeaderStatus,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> Connections.Connection:
  match pair:
    case (connection, status):
      match status:
        case Connections.HeaderPayload{expected_payload_bytes}:
          reactor.header.payload(connection,
            protocol.u32.duplicate.pair(expected_payload_bytes),
            max_payload_bytes, queue_deadline_ms, rx_used, rx_limit)
        case Connections.HeaderRejected{_}: reactor.close.connection(connection)
        case _:
          connection

def reactor.read.header.available(
  id: U32,
  socket: File,
  +poll_events: U32,
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: U32,
  deadline_ms: Nat,
  measured: Bytes.Bytes & U32,
  +max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> Connections.Connection:
  match measured:
    case (bytes, length):
      match length:
        case 0:
          Connections.Connection{id, socket, poll_events,
            Connections.Closing{}}
        case _:
          reactor.header.progress(Connections.header.received(
            Connections.Connection{id, socket, poll_events,
            Connections.ReadingHeader{chunks, received_bytes,
                deadline_ms}}, bytes, max_payload_bytes),
            max_payload_bytes, queue_deadline_ms, rx_used, rx_limit)

def reactor.read.header(
  id: U32,
  poll_events: U32,
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: U32,
  deadline_ms: Nat,
  pair: File & Io.ReadAttempt,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> Connections.Connection:
  match pair:
    case (socket, attempt):
      match attempt:
        case Io.ReadAvailable{bytes}:
          reactor.read.header.available(id, socket, poll_events, chunks,
            received_bytes, deadline_ms, Bytes.length(bytes),
            max_payload_bytes, queue_deadline_ms, rx_used, rx_limit)
        case Io.ReadInterrupted{}:
          Connections.Connection{id, socket, poll_events,
            Connections.ReadingHeader{chunks, received_bytes, deadline_ms}}
        case Io.ReadWouldBlock{}:
          Connections.Connection{id, socket, poll_events,
            Connections.ReadingHeader{chunks, received_bytes, deadline_ms}}
        case Io.ReadFailed{_}:
          Connections.Connection{id, socket, poll_events,
            Connections.Closing{}}

def reactor.read.header.budgeted(
  id: U32,
  socket: File,
  poll_events: U32,
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: U32,
  deadline_ms: Nat,
  read_bytes: Nat,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> IO(Connections.Connection):
  match read_bytes:
    case 0n:
      IO.pure(Connections.Connection,
        Connections.Connection{id, socket, poll_events,
          Connections.ReadingHeader{chunks, received_bytes, deadline_ms}})
    case 1n+_:
      do IO<Connections.Connection>:
        attempt : File & Io.ReadAttempt <- Io.read.nonblocking(socket,
          U32.from_nat(read_bytes))
        return reactor.read.header(id, poll_events, chunks, received_bytes,
          deadline_ms, attempt, max_payload_bytes, queue_deadline_ms,
          rx_used, rx_limit)

def reactor.read.payload.progress(
  pair: Connections.Connection & Connections.PayloadStatus
) -> Connections.Connection:
  match pair:
    case (Connections.Connection{id, socket, poll_events, phase}, status):
      match status:
        case Connections.PayloadRejected{_}:
          Connections.Connection{id, socket, poll_events,
            Connections.Closing{}}
        case _:
          Connections.Connection{id, socket, poll_events, phase}

def reactor.read.payload.available(
  id: U32,
  socket: File,
  poll_events: U32,
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  expected_bytes: U32,
  received_bytes: U32,
  deadline_ms: Nat,
  measured: Bytes.Bytes & U32,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat
) -> Connections.Connection:
  match measured:
    case (bytes, length):
      match length:
        case 0:
          Connections.Connection{id, socket, poll_events,
            Connections.Closing{}}
        case _:
          reactor.read.payload.progress(Connections.payload.received(
            Connections.Connection{id, socket, poll_events,
              Connections.ReadingPayload{header, chunks, expected_bytes,
                received_bytes, deadline_ms}}, bytes, max_payload_bytes,
            queue_deadline_ms))

def reactor.read.payload(
  id: U32,
  poll_events: U32,
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  expected_bytes: U32,
  received_bytes: U32,
  deadline_ms: Nat,
  pair: File & Io.ReadAttempt,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat
) -> Connections.Connection:
  match pair:
    case (socket, attempt):
      match attempt:
        case Io.ReadAvailable{bytes}:
          reactor.read.payload.available(id, socket, poll_events, header, chunks,
            expected_bytes, received_bytes, deadline_ms, Bytes.length(bytes),
            max_payload_bytes, queue_deadline_ms)
        case Io.ReadInterrupted{}:
          Connections.Connection{id, socket, poll_events,
            Connections.ReadingPayload{header, chunks, expected_bytes,
              received_bytes, deadline_ms}}
        case Io.ReadWouldBlock{}:
          Connections.Connection{id, socket, poll_events,
            Connections.ReadingPayload{header, chunks, expected_bytes,
              received_bytes, deadline_ms}}
        case Io.ReadFailed{_}:
          Connections.Connection{id, socket, poll_events,
            Connections.Closing{}}

def reactor.read.payload.budgeted(
  id: U32,
  socket: File,
  poll_events: U32,
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  expected_bytes: U32,
  received_bytes: U32,
  deadline_ms: Nat,
  read_bytes: Nat,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat
) -> IO(Connections.Connection):
  match read_bytes:
    case 0n:
      IO.pure(Connections.Connection,
        Connections.Connection{id, socket, poll_events,
          Connections.ReadingPayload{header, chunks, expected_bytes,
            received_bytes, deadline_ms}})
    case 1n+_:
      do IO<Connections.Connection>:
        attempt : File & Io.ReadAttempt <- Io.read.nonblocking(socket,
          U32.from_nat(read_bytes))
        return reactor.read.payload(id, poll_events, header, chunks,
          expected_bytes, received_bytes, deadline_ms, attempt,
          max_payload_bytes, queue_deadline_ms)

def reactor.read.connection(
  connection: Connections.Connection,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> IO(Connections.Connection):
  match connection:
    case Connections.Connection{id, socket, +poll_events, phase}:
      match phase:
        case Connections.ReadingHeader{chunks, +received_bytes, deadline_ms}:
          reactor.read.header.budgeted(id, socket, poll_events, chunks,
            received_bytes, deadline_ms,
            ConnectionPolicy.read.chunk(
            U32.to_nat(U32.sub(24, received_bytes)), 24n),
            max_payload_bytes, queue_deadline_ms, rx_used, rx_limit)
        case Connections.ReadingPayload{header, chunks, +expected_bytes,
          +received_bytes, deadline_ms}:
          reactor.read.payload.budgeted(id, socket, poll_events, header,
            chunks, expected_bytes, received_bytes, deadline_ms,
            ConnectionPolicy.read.chunk(
              U32.to_nat(U32.sub(expected_bytes, received_bytes)),
              U32.to_nat(U32.sub(expected_bytes, received_bytes))),
            max_payload_bytes, queue_deadline_ms)
        case _:
          IO.pure(Connections.Connection,
            Connections.Connection{id, socket, poll_events,
              Connections.Closing{}})

def reactor.read.hangup(
  id: U32,
  socket: File,
  poll_events: U32,
  phase: Connections.Phase,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> IO(Connections.Connection):
  match phase:
    case Connections.ReadingHeader{_, _, _}:
      reactor.read.connection(
        Connections.Connection{id, socket, poll_events, phase},
        max_payload_bytes, queue_deadline_ms, rx_used, rx_limit)
    case Connections.ReadingPayload{_, _, _, _, _}:
      reactor.read.connection(
        Connections.Connection{id, socket, poll_events, phase},
        max_payload_bytes, queue_deadline_ms, rx_used, rx_limit)
    case _:
      IO.pure(Connections.Connection,
        Connections.Connection{id, socket, poll_events,
          Connections.Closing{}})

def reactor.read.ready(
  id: U32,
  socket: File,
  poll_events: U32,
  phase: Connections.Phase,
  status: UnixSocket.PollStatus,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> IO(Connections.Connection):
  match status:
    case UnixSocket.Readable{}:
      reactor.read.connection(
        Connections.Connection{id, socket, poll_events, phase},
        max_payload_bytes, queue_deadline_ms, rx_used, rx_limit)
    case UnixSocket.ReadableFailed{}:
      reactor.read.hangup(id, socket, poll_events, phase,
        max_payload_bytes, queue_deadline_ms, rx_used, rx_limit)
    case UnixSocket.Failed{}:
      IO.pure(Connections.Connection,
        Connections.Connection{id, socket, poll_events,
          Connections.Closing{}})
    case UnixSocket.Idle{}:
      IO.pure(Connections.Connection,
        Connections.Connection{id, socket, poll_events, phase})

def reactor.write.sent.advanced(
  id: U32,
  socket: File,
  +poll_events: U32,
  deadline_ms: Nat,
  bytes: Bytes.Bytes,
  reservation: TxPolicy.FrameReservation,
  offset: U32,
  is_complete: Bool
) -> Connections.Connection:
  match is_complete:
    case True{}:
      Connections.Connection{id, socket, poll_events, Connections.Closing{}}
    case False{}:
      Connections.Connection{id, socket, poll_events,
        Connections.WritingResponse{bytes, offset, deadline_ms, reservation}}

def reactor.write.sent.progress(
  id: U32,
  socket: File,
  +poll_events: U32,
  deadline_ms: Nat,
  total: U32,
  +_written_bytes: U32,
  bytes: Bytes.Bytes,
  reservation: TxPolicy.FrameReservation,
  decision: ConnectionPolicy.Progress
) -> Connections.Connection:
  match decision:
    case ConnectionPolicy.Advanced{+offset}:
      reactor.write.sent.advanced(id, socket, poll_events, deadline_ms,
        bytes, reservation, offset, U32.is_eq(offset, total))
    case ConnectionPolicy.Waiting{offset}:
      Connections.Connection{id, socket, poll_events,
        Connections.WritingResponse{bytes, offset, deadline_ms, reservation}}
    case ConnectionPolicy.InvalidProgress{}:
      Connections.Connection{id, socket, poll_events, Connections.Closing{}}

def reactor.write.progress(
  id: U32,
  socket: File,
  poll_events: U32,
  deadline_ms: Nat,
  +total: U32,
  +written_bytes: U32,
  reservation: TxPolicy.FrameReservation,
  attempt: Io.WriteAttempt
) -> Connections.Connection:
  match attempt:
    case Io.NonblockingWriteSent{bytes, sent}:
      reactor.write.sent.progress(id, socket, poll_events, deadline_ms,
        total, written_bytes, bytes, reservation,
        ConnectionPolicy.progress(written_bytes, sent, total))
    case Io.NonblockingWriteInterrupted{bytes}:
      Connections.Connection{id, socket, poll_events,
        Connections.WritingResponse{bytes, written_bytes, deadline_ms,
          reservation}}
    case Io.NonblockingWriteWouldBlock{bytes}:
      Connections.Connection{id, socket, poll_events,
        Connections.WritingResponse{bytes, written_bytes, deadline_ms,
          reservation}}
    case Io.NonblockingWriteFailed{_, _}:
      Connections.Connection{id, socket, poll_events,
        Connections.Closing{}}

def reactor.write.result(
  id: U32,
  poll_events: U32,
  deadline_ms: Nat,
  total: U32,
  written_bytes: U32,
  reservation: TxPolicy.FrameReservation,
  pair: File & Io.WriteAttempt
) -> Connections.Connection:
  match pair:
    case (socket, attempt):
      reactor.write.progress(id, socket, poll_events, deadline_ms, total,
        written_bytes, reservation, attempt)

def reactor.write.connection(
  id: U32,
  socket: File,
  poll_events: U32,
  encoded: Bytes.Bytes,
  +written_bytes: U32,
  deadline_ms: Nat,
  reservation: TxPolicy.FrameReservation
) -> IO(Connections.Connection):
  match encoded:
    case Bytes.Bytes{+total, _}:
      do IO<Connections.Connection>:
        attempt : File & Io.WriteAttempt <- Io.write.nonblocking(socket,
          written_bytes, U32.sub(total, written_bytes), encoded)
        return reactor.write.result(id, poll_events, deadline_ms, total,
          written_bytes, reservation, attempt)

def reactor.poll.result(
  id: U32,
  socket: File,
  poll_events: U32,
  phase: Connections.Phase,
  flags: U32,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> IO(Connections.Connection):
  match phase:
    case Connections.WritingResponse{encoded, written_bytes, deadline_ms,
        reservation}:
      reactor.write.connection(id, socket, poll_events, encoded,
        written_bytes, deadline_ms, reservation)
    case _:
      reactor.read.ready(id, socket, poll_events, phase,
        UnixSocket.poll.status(flags), max_payload_bytes, queue_deadline_ms,
        rx_used, rx_limit)

def reactor.ready.connection(
  id: U32,
  socket: File,
  poll_events: U32,
  phase: Connections.Phase,
  readiness: Connections.EventReadiness,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> IO(Connections.Connection):
  match readiness:
    case Connections.EventReady{flags}:
      reactor.poll.result(id, socket, poll_events, phase,
        flags, max_payload_bytes, queue_deadline_ms, rx_used, rx_limit)
    case Connections.EventNotReady{}:
      IO.pure(Connections.Connection,
        Connections.Connection{id, socket, poll_events, phase})

def reactor.receive.free.result(limit: Nat, used: Nat,
  within_limit: Bool) -> Nat:
  match within_limit:
    case True{}: Nat.sub(limit, used)
    case False{}: 0n

def reactor.receive.free(+limit: Nat, +used: Nat) -> Nat:
  reactor.receive.free.result(limit, used, Nat.is_le(used, limit))

def reactor.receive.used.after(
  counted: Connections.Connection & Nat,
  used_before: Nat,
  bytes_before: Nat
) -> Connections.Connection & Nat:
  match counted:
    case (connection, bytes_after):
      (connection, Nat.add(Nat.sub(used_before, bytes_before), bytes_after))

def reactor.poll.expired.connection(
  connection: Connections.Connection,
  events: List<&2, SocketTypes.ReadyEvent>,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_used: Nat,
  rx_limit: Nat
) -> IO(Connections.Connection):
  match connection:
    case Connections.Connection{+id, socket, +poll_events, phase}:
      reactor.ready.connection(id, socket, poll_events, phase,
        Connections.event.find(id, events), max_payload_bytes,
        queue_deadline_ms, rx_used, rx_limit)

def reactor.poll.expired.measured(
  measured: Connections.Connection & Nat,
  events: List<&2, SocketTypes.ReadyEvent>,
  +now: Nat,
  +max_payload_bytes: Nat,
  +queue_deadline_ms: Nat,
  rx_limit: Nat,
  +rx_used: Nat
) -> IO(Connections.Connection & Nat):
  match measured:
    case (connection, bytes_before):
      do IO<Connections.Connection & Nat>:
        expired : Connections.Connection <- IO.pure(
          Connections.Connection, reactor.expire.connection(connection, now))
        processed : Connections.Connection <- reactor.poll.expired.connection(
          expired, events, max_payload_bytes, queue_deadline_ms,
          rx_used, rx_limit)
        counted : Connections.Connection & Nat <- IO.pure(
          Connections.Connection & Nat,
          Connections.receive.bytes.connection(processed))
        return reactor.receive.used.after(counted, rx_used, bytes_before)

def reactor.poll.expired(
  connection: Connections.Connection,
  events: List<&2, SocketTypes.ReadyEvent>,
  +now: Nat,
  +max_payload_bytes: Nat,
  +queue_deadline_ms: Nat,
  rx_limit: Nat,
  rx_used: Nat
) -> IO(Connections.Connection & Nat):
  reactor.poll.expired.measured(
    Connections.receive.bytes.connection(connection), events, now,
    max_payload_bytes, queue_deadline_ms, rx_limit, rx_used)

def reactor.poll.one(
  connection: Connections.Connection,
  events: List<&2, SocketTypes.ReadyEvent>,
  +now: Nat,
  +max_payload_bytes: Nat,
  +queue_deadline_ms: Nat,
  rx_limit: Nat,
  rx_used: Nat
) -> IO(Connections.Connection & Nat):
  reactor.poll.expired(connection, events, now, max_payload_bytes,
    queue_deadline_ms, rx_limit, rx_used)

def reactor.read.state.connections(
  state: ReactorReadState
) -> List<&1, Connections.Connection>:
  match state:
    case ReadScanning{remaining, retained, _, _, _, _, _, _}:
      Connections.append.connections(
        Connections.reverse.connections(retained, Nil{}), remaining)
    case ReadProcessed{remaining, retained, _, _, _, _, _, _, processed}:
      match processed:
        case (connection, _):
          Connections.append.connections(
            Connections.reverse.connections(retained, Nil{}),
            Con{connection, remaining})

def reactor.read.loop(
  fuel: Nat,
  state: ReactorReadState
) -> IO(ReactorReadResult):
  match fuel:
    case 0n:
      IO.pure(ReactorReadResult, ReadFuelExhausted{state})
    case 1n+rest:
      match state:
        case ReadScanning{remaining, retained, +events, +now,
          +max_payload_bytes, +queue_deadline_ms, +rx_limit, +rx_used}:
          match remaining:
            case Nil{}:
              IO.pure(ReactorReadResult, ReadCompleted{
                Connections.reverse.connections(retained, Nil{})})
            case Con{connection, tail}:
              do IO<ReactorReadResult>:
                processed : Connections.Connection & Nat <-
                  reactor.poll.one(connection, events, now,
                    max_payload_bytes, queue_deadline_ms, rx_limit, rx_used)
                next_result : ReactorReadResult <- reactor.read.loop(rest,
                  ReadProcessed{tail, retained, events, now,
                    max_payload_bytes, queue_deadline_ms, rx_limit, rx_used,
                    processed})
                return next_result
        case ReadProcessed{remaining, retained, events, now,
          max_payload_bytes, queue_deadline_ms, rx_limit, _, processed}:
          match processed:
            case (connection, used_after):
              reactor.read.loop(rest,
                ReadScanning{remaining, Con{connection, retained}, events,
                  now, max_payload_bytes, queue_deadline_ms, rx_limit,
                  used_after})

def serve.reactor.read.start(
  metrics: Connections.ReceiveCount,
  events: List<&2, SocketTypes.ReadyEvent>,
  now: Nat,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat,
  rx_limit: Nat
) -> IO(ReactorReadResult):
  match metrics:
    case Connections.ReceiveCount{connections, bytes, count}:
      reactor.read.loop(Nat.add(Nat.mul(count, 2n), 1n),
        ReadScanning{connections, Nil{}, events, now, max_payload_bytes,
          queue_deadline_ms, rx_limit, bytes})

def reactor.cleanup.fold.loop(
  fuel: Nat,
  state: ReactorCleanupState
) -> ReactorCleanupFoldResult:
  match fuel:
    case 0n: CleanupFuelExhausted{state}
    case 1n+rest:
      match state:
        case CleanupScanning{remaining, retained, actions, queue}:
          match remaining:
            case Nil{}:
              CleanupFolded{Connections.reverse.connections(retained, Nil{}),
                actions, queue}
            case Con{connection, tail}:
              match connection:
                case Connections.Connection{+id, socket, _,
                    Connections.Closing{}}:
                  reactor.cleanup.fold.loop(rest, CleanupCancelled{tail,
                    retained, actions, id, socket,
                    RequestQueue.cancel_connection(queue, id)})
                case connection:
                  reactor.cleanup.fold.loop(rest, CleanupScanning{tail,
                    Con{connection, retained}, actions, queue})
        case CleanupCancelled{remaining, retained, actions, id, socket, result}:
          match result:
            case RequestQueue.CancelResult{queue, cancelled, _, _}:
              reactor.cleanup.fold.loop(rest, CleanupScanning{remaining,
                retained, Con{CloseConnection{id, socket, cancelled}, actions},
                queue})

def reactor.cleanup.fold(
  counted: List<&1, Connections.Connection> & Nat,
  queue: RequestQueue.Queue
) -> ReactorCleanupFoldResult:
  match counted:
    case (connections, count):
      reactor.cleanup.fold.loop(Nat.add(Nat.mul(count, 2n), 1n),
        CleanupScanning{connections, Nil{}, Nil{}, queue})

def reactor.cleanup.actions(
  remaining: List<&1, ReactorCloseAction>,
  result: ReactorCleanupResult
) -> IO(ReactorCleanupResult):
  match remaining:
    case Nil{}: IO.pure(ReactorCleanupResult, result)
    case Con{action, tail}:
      match action:
        case CloseConnection{id, socket, cancelled}:
          do IO<ReactorCleanupResult>:
            _observed : Unit <- Observation.closed(id)
            _closed : Unit <- File.close(socket)
            _discarded : Unit = RequestQueue.cancelled.discard(cancelled)
            reactor.cleanup.actions(tail, result)

def reactor.cleanup.finish(
  result: ReactorCleanupFoldResult
) -> IO(ReactorCleanupResult):
  match result:
    case CleanupFolded{connections, actions, queue}:
      reactor.cleanup.actions(actions, ReactorCleaned{connections, queue})
    case CleanupFuelExhausted{_}:
      IO.die(ReactorCleanupResult, 1,
        "owner connection cleanup iteration exhausted")

def reactor.cleanup.closed(
  connections: List<&1, Connections.Connection>,
  queue: RequestQueue.Queue
) -> IO(ReactorCleanupResult):
  reactor.cleanup.finish(reactor.cleanup.fold(
    Connections.count.connections(connections), queue))

def reactor.queue.empty() -> RequestQueue.Queue:
  RequestQueue.empty()

def reply.options.pair(
  context: ReplyContext
) -> ReplyContext & ResourceOptions.Options:
  match context:
    case ReplyContext{versions, generations, request_ids, +options}:
      (ReplyContext{versions, generations, request_ids, options}, options)

def reply.response(
  context: ReplyContext,
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes
) -> Protocol.Response:
  match context:
    case ReplyContext{versions, generations, request_ids, _}:
      match versions:
        case (version, _):
          match generations:
            case (generation, _):
              match request_ids:
                case (request_id, _):
                  Protocol.Response{version, generation, request_id, status,
                    payload}

def error.kind(error: ByteDb.Error) -> Policy.FailureKind:
  match error:
    case ByteDb.Busy{}: Policy.BusyFailure{}
    case ByteDb.Timeout{}: Policy.TimeoutFailure{}
    case ByteDb.NotFound{}: Policy.NotFoundFailure{}
    case ByteDb.AlreadyExists{}: Policy.AlreadyExistsFailure{}
    case ByteDb.InvalidArgument{}: Policy.InvalidArgumentFailure{}
    case ByteDb.UnsupportedPlatform{}: Policy.UnsupportedPlatformFailure{}
    case ByteDb.ResourceLimit{}: Policy.ResourceLimitFailure{}
    case ByteDb.Corruption{_}: Policy.CorruptionFailure{}
    case ByteDb.Io{_, _}: Policy.IoFailure{}
    case ByteDb.CommitUnknown{_, _}: Policy.CommitUnknownFailure{}

def reply.status(status: Policy.ReplyStatus) -> Protocol.ResponseStatus:
  match status:
    case Policy.SuccessStatus{}: Protocol.Success{}
    case Policy.InvalidArgumentStatus{}: Protocol.InvalidArgument{}
    case Policy.AlreadyExistsStatus{}: Protocol.AlreadyExists{}
    case Policy.UnsupportedPlatformStatus{}: Protocol.UnsupportedPlatform{}
    case Policy.NotFoundStatus{}: Protocol.NotFound{}
    case Policy.BusyStatus{}: Protocol.Busy{}
    case Policy.TimeoutStatus{}: Protocol.Timeout{}
    case Policy.ResourceLimitStatus{}: Protocol.ResponseResourceLimit{}
    case Policy.CorruptionStatus{}: Protocol.Corruption{}
    case Policy.IoStatus{}: Protocol.IoFailure{}
    case Policy.CommitUnknownStatus{}: Protocol.CommitUnknown{}

def error.status(error: ByteDb.Error) -> Protocol.ResponseStatus:
  reply.status(Policy.failure.status(error.kind(error)))

def write.response(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>,
  context: ReplyContext
) -> IO(ByteDb.Handle & Protocol.Response):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<ByteDb.Handle & Protocol.Response>:
        _after_apply : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("owner.after_apply")
        _before_response : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("owner.before_response")
        _checkpoint : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("owner.after_mutation.before_response")
        return (handle, reply.response(context, Protocol.Success{}, Bytes.new(0)))
    case (handle, Fail{error}):
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, error.status(error), Bytes.new(0))))

def get.response(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>,
  context: ReplyContext
) -> ByteDb.Handle & Protocol.Response:
  match pair:
    case (handle, Fail{error}):
      (handle, reply.response(context, error.status(error), Bytes.new(0)))
    case (handle, Done{None{}}):
      (handle, reply.response(context, Protocol.NotFound{}, Bytes.new(0)))
    case (handle, Done{Some{value}}):
      (handle, reply.response(context, Protocol.Success{}, value))

def stats.response.encoded(
  handle: ByteDb.Handle,
  context: ReplyContext,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> ByteDb.Handle & Protocol.Response:
  match result:
    case Done{payload}:
      (handle, reply.response(context, Protocol.Success{}, payload))
    case Fail{_}:
      (handle, reply.response(context, Protocol.ResponseResourceLimit{},
        Bytes.new(0)))

def stats.response(
  handle: ByteDb.Handle,
  stats: ByteDb.Stats,
  context: ReplyContext
) -> ByteDb.Handle & Protocol.Response:
  match stats:
    case ByteDb.Stats{entries, payload_bytes}:
      stats.response.encoded(handle, context,
        StorageBytes.from_string(Nat.show(entries) ++ ":" ++
          Nat.show(payload_bytes) ++ ":0:0:0"))

def stats.response.owner.result(
  pair: ByteDb.Handle & Protocol.Response,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> DispatchResult:
  match pair:
    case (handle, response): DispatchResult{handle, snapshots, cursors, response}

def stats.response.owner.metrics(
  handle: ByteDb.Handle,
  context: ReplyContext,
  entries: Nat,
  payload_bytes: Nat,
  snapshot_metrics: SnapshotStore.Metrics,
  cursor_metrics: CursorStore.Metrics
) -> DispatchResult:
  match snapshot_metrics:
    case SnapshotStore.Metrics{snapshots, retained_bytes, snapshot_store}:
      match cursor_metrics:
        case CursorStore.Metrics{cursors, cursor_store}:
          stats.response.owner.result(
            stats.response.encoded(handle, context,
              StorageBytes.from_string(Nat.show(entries) ++ ":" ++
                Nat.show(payload_bytes) ++ ":" ++ Nat.show(snapshots) ++
                ":" ++ Nat.show(retained_bytes) ++ ":" ++ Nat.show(cursors))),
            snapshot_store, cursor_store)

def stats.response.owner(
  pair: ByteDb.Handle & ByteDb.Stats,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext
) -> DispatchResult:
  match pair:
    case (handle, stats):
      match stats:
        case ByteDb.Stats{entries, payload_bytes}:
          stats.response.owner.metrics(handle, context, entries, payload_bytes,
            SnapshotStore.metrics(snapshots), CursorStore.metrics(cursors))

def dispatch.stats.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext
) -> IO(DispatchResult):
  IO.pure(DispatchResult,
    stats.response.owner(ByteDb.stats(handle), snapshots, cursors, context))

def dispatch.stats(
  pair: ByteDb.Handle & ByteDb.Stats,
  context: ReplyContext
) -> IO(ByteDb.Handle & Protocol.Response):
  match pair:
    case (handle, snapshot):
      IO.pure(ByteDb.Handle & Protocol.Response,
        stats.response(handle, snapshot, context))

def dispatch.result(
  pair: ByteDb.Handle & Protocol.Response,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> DispatchResult:
  match pair:
    case (handle, response): DispatchResult{handle, snapshots, cursors, response}

def compact.preflight.result(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  decision: Bool & SnapshotStore.Store
) -> IO(DispatchResult):
  match decision:
    case (False{}, snapshots):
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})
    case (True{}, snapshots):
      do IO<DispatchResult>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.compact(handle)
        response : ByteDb.Handle & Protocol.Response <-
          write.response(pair, context)
        return dispatch.result(response, snapshots, cursors)

def compact.preflight.options(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  options: ResourceOptions.Options
) -> IO(DispatchResult):
  compact.preflight.result(handle, cursors, context,
    SnapshotStore.retired_files.can_compact(snapshots,
      ResourceOptions.reader.retired.files(options)))

def compact.preflight.options.pair(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  pair: ReplyContext & ResourceOptions.Options
) -> IO(DispatchResult):
  match pair:
    case (context, options):
      compact.preflight.options(handle, snapshots, cursors, context, options)

def compact.preflight(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext
) -> IO(DispatchResult):
  compact.preflight.options.pair(handle, snapshots, cursors,
    reply.options.pair(context))

def snapshot.generation(value: Maybe<&1, U32>) -> Nat:
  match value:
    case None{}: 0n
    case Some{generation}: U32.to_nat(generation)

def snapshot.open.result(
  handle: ByteDb.Handle,
  context: ReplyContext,
  cursors: CursorStore.Store,
  result: SnapshotStore.OpenResult
) -> DispatchResult:
  match result:
    case SnapshotStore.RootStored{store, snapshot_id}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Success{},
          Protocol.snapshot.id.bytes(snapshot_id))}
    case SnapshotStore.RootRejected{store}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))}

def snapshot.open.root.configured(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context_options: ReplyContext & ResourceOptions.Options,
  cursors: CursorStore.Store,
  roots: ByteDb.SnapshotRoot & ByteDb.SnapshotRoot
) -> DispatchResult:
  match context_options:
    case (context, +options):
      match roots:
        case (generation_root, retained_root):
          match generation_root:
            case ByteDb.SnapshotRoot{_, sst_generation, _, _}:
              snapshot.open.result(handle, context, cursors,
                SnapshotStore.open.root(snapshots, retained_root,
                  snapshot.generation(sst_generation),
                  (U32.to_nat(ResourceOptions.snapshot.count(options)),
                    U32.to_nat(ResourceOptions.snapshot.retained.bytes(options)))))

def snapshot.open.root.copies(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  cursors: CursorStore.Store,
  roots: ByteDb.SnapshotRoot & ByteDb.SnapshotRoot
) -> DispatchResult:
  snapshot.open.root.configured(handle, snapshots,
    reply.options.pair(context), cursors, roots)

def snapshot.open.captured(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, ByteDb.SnapshotRoot>,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  cursors: CursorStore.Store
) -> DispatchResult:
  match pair:
    case (handle, Fail{error}):
      dispatch.result((handle, reply.response(context, error.status(error),
        Bytes.new(0))), snapshots, cursors)
    case (handle, Done{root}):
      snapshot.open.root.copies(handle, snapshots, context, cursors,
        ByteDb.snapshot.root.clone(root))

def snapshot.open.configured(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context_options: ReplyContext & ResourceOptions.Options,
  cursors: CursorStore.Store
) -> IO(DispatchResult):
  match context_options:
    case (context, +options):
      do IO<DispatchResult>:
        captured : ByteDb.Handle &
          Result<&1, &1, ByteDb.Error, ByteDb.SnapshotRoot> <-
            ByteDb.snapshot_root_limited(
              U32.to_nat(ResourceOptions.snapshot.retained.bytes(options)),
              handle)
        return snapshot.open.captured(captured, snapshots, context, cursors)

def snapshot.open(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  cursors: CursorStore.Store
) -> IO(DispatchResult):
  snapshot.open.configured(handle, snapshots, reply.options.pair(context),
    cursors)

def snapshot.get.result(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  result: Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>
) -> DispatchResult:
  match result:
    case Fail{error}:
      DispatchResult{handle, snapshots, cursors,
        reply.response(context, error.status(error), Bytes.new(0))}
    case Done{None{}}:
      DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.NotFound{}, Bytes.new(0))}
    case Done{Some{value}}:
      DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.Success{}, value)}

def snapshot.get.lookup(
  handle: ByteDb.Handle,
  context: ReplyContext,
  cursors: CursorStore.Store,
  key: Bytes.Bytes,
  lookup: SnapshotStore.LookupResult
) -> IO(DispatchResult):
  match lookup:
    case SnapshotStore.RootFound{store, root}:
      do IO<DispatchResult>:
        result : Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>> <-
          ByteDb.snapshot.root.get(root, key)
        return snapshot.get.result(handle, store, cursors, context, result)
    case SnapshotStore.RootMissing{store}:
      IO.pure(DispatchResult, DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.get(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshot_id: U32,
  key: Bytes.Bytes
) -> IO(DispatchResult):
  snapshot.get.lookup(handle, context, cursors, key,
    SnapshotStore.lookup.root(snapshots, snapshot_id))

def snapshot.close.reply(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  status: Protocol.ResponseStatus
) -> DispatchResult:
  DispatchResult{handle, snapshots, cursors,
    reply.response(context, status, Bytes.new(0))}

def snapshot.close.cleanup.removed(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  removed: Result<&1, &1, U32 & String, Unit>
) -> IO(DispatchResult):
  match removed:
    case Done{Unit{}}:
      IO.pure(DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Success{}))
    case Fail{_}:
      IO.pure(DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.IoFailure{}))

def snapshot.close.cleanup.exists(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  stale_path: String,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(DispatchResult):
  match exists:
    case Fail{_}:
      IO.pure(DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.IoFailure{}))
    case Done{False{}}:
      IO.pure(DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Success{}))
    case Done{True{}}:
      do IO<DispatchResult>:
        removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(stale_path)
        snapshot.close.cleanup.removed(handle, snapshots, cursors, context,
          removed)

def snapshot.close.cleanup.paths(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  paths: String & String
) -> IO(DispatchResult):
  match paths:
    case (check_path, stale_path):
      do IO<DispatchResult>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(check_path)
        snapshot.close.cleanup.exists(handle, snapshots, cursors, context,
          stale_path, exists)

def snapshot.close.cleanup(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  stale_path: String
) -> IO(DispatchResult):
  snapshot.close.cleanup.paths(handle, snapshots, cursors, context,
    ByteDb.path.clone.pair(stale_path))

def snapshot.close.reclaim(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  stale_path: String,
  decision: Bool & SnapshotStore.Store
) -> IO(DispatchResult):
  match decision:
    case (False{}, snapshots):
      IO.pure(DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Success{}))
    case (True{}, snapshots):
      snapshot.close.cleanup(handle, snapshots, cursors, context, stale_path)

def snapshot.close.manifest.current(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  candidate: U32,
  stale_path: String,
  manifest: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(DispatchResult):
  match manifest:
    case Fail{ByteManifestIo.Invalid{_}}:
      IO.pure(DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Corruption{}))
    case Fail{ByteManifestIo.Host{_, _}}:
      IO.pure(DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.IoFailure{}))
    case Done{value}:
      match value:
        case ByteManifest.GenerationSst{file_id}:
          snapshot.close.reclaim(handle, cursors, context, stale_path,
            SnapshotStore.generation.can.reclaim(snapshots, candidate,
              Some{file_id}))
        case _:
          snapshot.close.reclaim(handle, cursors, context, stale_path,
            SnapshotStore.generation.can.reclaim(snapshots, candidate,
              None{}))

def snapshot.close.manifest(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: U32,
  stale_path: String,
  manifest: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(DispatchResult):
  snapshot.close.manifest.current(handle, snapshots, cursors, context,
    candidate, stale_path, manifest)

# Reads the active manifest before deciding whether a closed root is obsolete.
def snapshot_close_root_path_read(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshots: SnapshotStore.Store,
  file_id: U32,
  path: String,
  manifest_path: String
) -> IO(DispatchResult):
  do IO<DispatchResult>:
    manifest : Result<&1, &1, ByteManifestIo.Error,
      ByteManifest.ManifestValue> <-
        ByteManifestIo.read(manifest_path ++ "/MANIFEST")
    snapshot.close.manifest(handle, cursors, context,
      snapshots, file_id, path, manifest)



# Preserves the database handle while reading the active manifest path.
def snapshot_close_root_path_reclaim(
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshots: SnapshotStore.Store,
  file_id: U32,
  path: String,
  paths: ByteDb.Handle & String
) -> IO(DispatchResult):
  match paths:
    case (retained_handle, manifest_path):
      snapshot_close_root_path_read(retained_handle, cursors, context,
        snapshots, file_id, path, manifest_path)


# Skips legacy roots and checks generation references before unlinking.
def snapshot_close_root_path_candidate_decide(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: Maybe<&1, U32>,
  path: String
) -> IO(DispatchResult):
      match candidate:
        case None{}:
          IO.pure(DispatchResult, snapshot.close.reply(handle, snapshots,
            cursors, context, Protocol.Success{}))
        case Some{file_id}:
          snapshot_close_root_path_reclaim(cursors, context, snapshots,
            file_id, path, ByteDb.handle.path.copy(handle))


# Checks the generation only when a closed root has a stored SST path.
def snapshot_close_root_path_candidate_some(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: Maybe<&1, U32>,
  path: String
) -> IO(DispatchResult):
      snapshot_close_root_path_candidate_decide(handle, cursors, context,
        snapshots, candidate, path)


# Skips filesystem cleanup for roots without a physical SST path.
def snapshot_close_root_path_candidate(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: Maybe<&1, U32>,
  stale_path: Maybe<&1, String>
) -> IO(DispatchResult):
  match stale_path:
    case None{}:
      IO.pure(DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Success{}))
    case Some{path}:
      snapshot_close_root_path_candidate_some(handle, cursors, context,
        snapshots, candidate, path)


def snapshot.close.root.path(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: Maybe<&1, U32>,
  stale_path: Maybe<&1, String>
) -> IO(DispatchResult):
  snapshot_close_root_path_candidate(handle, cursors, context, snapshots,
    candidate, stale_path)



def snapshot.close.root(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshots: SnapshotStore.Store,
  root: ByteDb.SnapshotRoot
) -> IO(DispatchResult):
  match root:
    case ByteDb.SnapshotRoot{sst_path, sst_generation, _, _}:
      snapshot.close.root.path(handle, cursors, context, snapshots,
        sst_generation, sst_path)

def snapshot.close.result(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  result: SnapshotStore.CloseResult
) -> IO(DispatchResult):
  match result:
    case SnapshotStore.RootClosed{store, root}:
      snapshot.close.root(handle, cursors, context, store, root)
    case SnapshotStore.RootCloseBusy{store}:
      IO.pure(DispatchResult, snapshot.close.reply(handle, store, cursors,
        context, Protocol.Busy{}))
    case SnapshotStore.RootCloseMissing{store}:
      IO.pure(DispatchResult, snapshot.close.reply(handle, store, cursors,
        context, Protocol.InvalidArgument{}))

# Closes one owner snapshot token through the aggregate retention registry.
def snapshot.close(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshot_id: U32
) -> IO(DispatchResult):
  snapshot.close.result(handle, cursors, context,
    SnapshotStore.close(snapshots, snapshot_id))

def snapshot.cursor.open.register(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_ids: U32 & U32 & U32,
  cursor: VisibleCursor.Cursor
) -> IO(DispatchResult):
  match cursor_ids:
    case (store_id, (response_id, _)):
      IO.pure(DispatchResult, DispatchResult{handle, snapshots,
        CursorStore.insert(cursors, store_id, cursor),
        reply.response(context, Protocol.Success{},
          Protocol.snapshot.id.bytes(response_id))})

def snapshot.cursor.open.failed(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  error: ByteDb.Error,
  released: SnapshotStore.CursorCloseResult
) -> DispatchResult:
  match released:
    case SnapshotStore.CursorReleased{updated, _}:
      DispatchResult{handle, updated, cursors,
        reply.response(context, error.status(error), Bytes.new(0))}
    case SnapshotStore.CursorReleaseRejected{updated}:
      DispatchResult{handle, updated, cursors,
        reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.opened(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32,
  opened: Result<&1, &1, ByteDb.Error, VisibleCursor.Cursor>
) -> IO(DispatchResult):
  match opened:
    case Fail{error}:
      IO.pure(DispatchResult, snapshot.cursor.open.failed(handle, cursors,
        context, error,
        SnapshotStore.cursor.close(snapshots, cursor_id)))
    case Done{cursor}:
      snapshot.cursor.open.register(handle, snapshots, cursors, context,
        Protocol.u32.duplicate.triple(cursor_id), cursor)

def snapshot.cursor.open.admitted(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  root: ByteDb.SnapshotRoot,
  bounds: RangeCursor.Bounds,
  decision: SnapshotStore.CursorOpenResult
) -> IO(DispatchResult):
  match decision:
    case SnapshotStore.CursorRejected{store}:
      IO.pure(DispatchResult, DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})
    case SnapshotStore.CursorStored{store, cursor_id}:
      do IO<DispatchResult>:
        opened : Result<&1, &1, ByteDb.Error, VisibleCursor.Cursor> <-
          ByteDb.snapshot.root.cursor.open(root, bounds)
        dispatched : DispatchResult <-
          snapshot.cursor.opened(handle, store, cursors, context, cursor_id,
            opened)
        return dispatched

def snapshot.cursor.open.global.capacity(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  options: ResourceOptions.Options,
  snapshot_id: U32,
  root: ByteDb.SnapshotRoot,
  bounds: RangeCursor.Bounds,
  available: Bool
) -> IO(DispatchResult):
  match available:
    case True{}:
      snapshot.cursor.open.admitted(handle, cursors, context, root, bounds,
        SnapshotStore.cursor.open(snapshots, snapshot_id,
          U32.to_nat(ResourceOptions.cursor.per.snapshot(
            options))))
    case False{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})

def snapshot.cursor.open.lookup.capacity(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context_options: ReplyContext & ResourceOptions.Options,
  snapshot_id: U32,
  root: ByteDb.SnapshotRoot,
  bounds: RangeCursor.Bounds,
  metrics: CursorStore.Metrics
) -> IO(DispatchResult):
  match context_options:
    case (context, +options):
      match metrics:
        case CursorStore.Metrics{count, cursors}:
          snapshot.cursor.open.global.capacity(handle, snapshots, cursors,
            context, options, snapshot_id, root, bounds,
            CursorStore.has.capacity(count,
              U32.to_nat(ResourceOptions.cursor.count(options))))

def snapshot.cursor.open.lookup(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshot_id: U32,
  bounds: RangeCursor.Bounds,
  lookup: SnapshotStore.LookupResult
) -> IO(DispatchResult):
  match lookup:
    case SnapshotStore.RootFound{store, root}:
      snapshot.cursor.open.lookup.capacity(handle, store,
        reply.options.pair(context), snapshot_id, root, bounds,
        CursorStore.metrics(cursors))
    case SnapshotStore.RootMissing{store}:
      IO.pure(DispatchResult, DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.cursor.open.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  bounds: RangeCursor.Bounds,
  ids: U32 & U32 & U32
) -> IO(DispatchResult):
  match ids:
    case (lookup_id, (retained_id, _)):
      snapshot.cursor.open.lookup(handle, cursors, context, retained_id, bounds,
        SnapshotStore.lookup.root(snapshots, lookup_id))

def snapshot.cursor.open(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshot_id: U32,
  bounds: RangeCursor.Bounds
) -> IO(DispatchResult):
  snapshot.cursor.open.ids(handle, snapshots, cursors, context, bounds,
    Protocol.u32.duplicate.triple(snapshot_id))

def snapshot.cursor.next.response(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  frame: CursorCodec.Frame
) -> DispatchResult:
  DispatchResult{handle, snapshots, cursors,
    reply.response(context, Protocol.Success{}, CursorCodec.encode(frame))}

def snapshot.cursor.next.item(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32,
  key: Bytes.Bytes,
  value: Bytes.Bytes,
  cursor: VisibleCursor.Cursor
) -> DispatchResult:
  snapshot.cursor.next.response(handle, snapshots,
    CursorStore.reinsert(cursors, cursor_id, cursor), context,
    CursorCodec.CursorItem{key, value})

def snapshot.cursor.next.terminal(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  released: SnapshotStore.CursorCloseResult,
  frame: CursorCodec.Frame
) -> DispatchResult:
  match released:
    case SnapshotStore.CursorReleased{store, _}:
      snapshot.cursor.next.response(handle, store, cursors, context, frame)
    case SnapshotStore.CursorReleaseRejected{store}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.next.terminal.error(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  released: SnapshotStore.CursorCloseResult
) -> DispatchResult:
  match released:
    case SnapshotStore.CursorReleased{store, _}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.IoFailure{}, Bytes.new(0))}
    case SnapshotStore.CursorReleaseRejected{store}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.next.loop(
  fuel: Nat,
  state: CursorReadState
) -> IO(DispatchResult):
  match fuel:
    case 0n:
      match state:
        case CursorReadNeed{handle, snapshots, cursors, context, cursor_id,
            _, cursor}:
          IO.pure(DispatchResult, DispatchResult{handle, snapshots,
            CursorStore.reinsert(cursors, cursor_id, cursor),
            reply.response(context, Protocol.ResponseResourceLimit{},
              Bytes.new(0))})
        case CursorReadStep{handle, snapshots, cursors, context, cursor_id,
            release_id, step}:
          match step:
            case VisibleCursor.Item{entry, cursor}:
              match entry:
                case ByteMemTable.Entry{key, value}:
                  match value:
                    case Some{bytes}:
                      IO.pure(DispatchResult, snapshot.cursor.next.item(handle,
                        snapshots, cursors, context, cursor_id, key, bytes,
                        cursor))
                    case None{}:
                      IO.pure(DispatchResult, DispatchResult{handle, snapshots,
                        CursorStore.reinsert(cursors, cursor_id, cursor),
                        reply.response(context, Protocol.ResponseResourceLimit{},
                          Bytes.new(0))})
            case VisibleCursor.Skip{cursor}:
              IO.pure(DispatchResult, DispatchResult{handle, snapshots,
                CursorStore.reinsert(cursors, cursor_id, cursor),
                reply.response(context, Protocol.ResponseResourceLimit{},
                  Bytes.new(0))})
            case VisibleCursor.End{}:
              IO.pure(DispatchResult, snapshot.cursor.next.terminal(handle,
                cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id),
                CursorCodec.CursorEnd{}))
            case VisibleCursor.Error{_}:
              IO.pure(DispatchResult, snapshot.cursor.next.terminal.error(
                handle, cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id)))
    case 1n+rest:
      match state:
        case CursorReadNeed{handle, snapshots, cursors, context, cursor_id,
            release_id, cursor}:
          do IO<DispatchResult>:
            step : VisibleCursor.Step <- VisibleCursor.next(cursor)
            snapshot.cursor.next.loop(rest, CursorReadStep{handle, snapshots,
              cursors, context, cursor_id, release_id, step})
        case CursorReadStep{handle, snapshots, cursors, context, cursor_id,
            release_id, step}:
          match step:
            case VisibleCursor.Item{entry, cursor}:
              match entry:
                case ByteMemTable.Entry{key, value}:
                  match value:
                    case Some{bytes}:
                      IO.pure(DispatchResult, snapshot.cursor.next.item(handle,
                        snapshots, cursors, context, cursor_id, key, bytes,
                        cursor))
                    case None{}:
                      snapshot.cursor.next.loop(rest, CursorReadNeed{handle,
                        snapshots, cursors, context, cursor_id, release_id,
                        cursor})
            case VisibleCursor.Skip{cursor}:
              snapshot.cursor.next.loop(rest, CursorReadNeed{handle, snapshots,
                cursors, context, cursor_id, release_id, cursor})
            case VisibleCursor.End{}:
              IO.pure(DispatchResult, snapshot.cursor.next.terminal(handle,
                cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id),
                CursorCodec.CursorEnd{}))
            case VisibleCursor.Error{_}:
              IO.pure(DispatchResult, snapshot.cursor.next.terminal.error(
                handle, cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id)))

def snapshot.cursor.next.taken(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  ids: U32 & U32,
  result: CursorStore.TakeResult
) -> IO(DispatchResult):
  match ids:
    case (cursor_id, release_id):
      match result:
        case CursorStore.Taken{store, cursor}:
          snapshot.cursor.next.loop(4096n, CursorReadNeed{handle, snapshots,
            store, context, cursor_id, release_id, cursor})
        case CursorStore.NotFound{store}:
          IO.pure(DispatchResult, DispatchResult{handle, snapshots, store,
            reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.cursor.next.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  ids: U32 & U32 & U32
) -> IO(DispatchResult):
  match ids:
    case (take_id, (cursor_id, release_id)):
      snapshot.cursor.next.taken(handle, snapshots, context,
        (cursor_id, release_id), CursorStore.take(cursors, take_id))

def snapshot.cursor.next(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32
) -> IO(DispatchResult):
  snapshot.cursor.next.ids(handle, snapshots, cursors, context,
    Protocol.u32.duplicate.triple(cursor_id))

def snapshot.cursor.close.success(
  closed: Result<&1, &1, U32 & String, Unit>
) -> Bool:
  match closed:
    case Done{Unit{}}: True{}
    case Fail{_}: False{}

def snapshot.cursor.close.result(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  outcome: Bool & SnapshotStore.CursorCloseResult
) -> DispatchResult:
  match outcome:
    case (True{}, SnapshotStore.CursorReleased{store, _}):
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Success{}, Bytes.new(0))}
    case (False{}, SnapshotStore.CursorReleased{store, _}):
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.IoFailure{}, Bytes.new(0))}
    case (_, SnapshotStore.CursorReleaseRejected{store}):
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.close.closed(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32,
  closed: Result<&1, &1, U32 & String, Unit>
) -> IO(DispatchResult):
  IO.pure(DispatchResult, snapshot.cursor.close.result(handle, cursors,
    context, (snapshot.cursor.close.success(closed),
      SnapshotStore.cursor.close(snapshots, cursor_id))))

def snapshot.cursor.close.taken(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  cursor_id: U32,
  result: CursorStore.TakeResult
) -> IO(DispatchResult):
  match result:
    case CursorStore.Taken{store, cursor}:
      do IO<DispatchResult>:
        closed : Result<&1, &1, U32 & String, Unit> <-
          VisibleCursor.close(cursor)
        result : DispatchResult <- snapshot.cursor.close.closed(handle,
          snapshots, store, context, cursor_id, closed)
        return result
    case CursorStore.NotFound{store}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, store,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.cursor.close.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  ids: U32 & U32 & U32
) -> IO(DispatchResult):
  match ids:
    case (take_id, (release_id, _)):
      snapshot.cursor.close.taken(handle, snapshots, context,
        release_id, CursorStore.take(cursors, take_id))

def snapshot.cursor.close(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32
) -> IO(DispatchResult):
  snapshot.cursor.close.ids(handle, snapshots, cursors, context,
    Protocol.u32.duplicate.triple(cursor_id))

def dispatch.describe.owner(
  context_options: ReplyContext & ResourceOptions.Options,
  handle: ByteDb.Handle
) -> ByteDb.Handle & Protocol.Response:
  match context_options:
    case (context, options):
      (handle, reply.response(context, Protocol.Success{},
        OptionsCodec.encode(options)))

def dispatch.operation(
  handle: ByteDb.Handle,
  context: ReplyContext,
  operation: Operation.Operation
) -> IO(ByteDb.Handle & Protocol.Response):
  match operation:
    case Operation.Get{key}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error,
          Maybe<&1, Bytes.Bytes>> <- ByteDb.get(handle, key)
        return get.response(pair, context)
    case Operation.Put{key, value}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.put(handle, key, value)
        write.response(pair, context)
    case Operation.Delete{key}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.delete(handle, key)
        write.response(pair, context)
    case Operation.WriteBatch{mutations}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.write_batch(handle, mutations)
        write.response(pair, context)
    case Operation.Flush{}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.flush(handle)
        write.response(pair, context)
    case Operation.Compact{}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.compact(handle)
        write.response(pair, context)
    case Operation.Stats{}:
      dispatch.stats(ByteDb.stats(handle), context)
    case Operation.DescribeOwner{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        dispatch.describe.owner(reply.options.pair(context), handle))
    case Operation.SnapshotOpen{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotGet{_, _}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotClose{_}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorOpen{_, _}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorNext{_}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorClose{_}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorSeek{_, _}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))

def snapshot.cursor.seek.taken(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  ids: U32 & U32,
  lower: Maybe<&1, Bytes.Bytes>,
  result: CursorStore.TakeResult
) -> DispatchResult:
  match ids:
    case (cursor_id, _):
      match result:
        case CursorStore.Taken{store, cursor}:
          DispatchResult{handle, snapshots,
            CursorStore.reinsert(store, cursor_id,
              VisibleCursor.seek(cursor, lower)),
            reply.response(context, Protocol.Success{}, Bytes.new(0))}
        case CursorStore.NotFound{store}:
          DispatchResult{handle, snapshots, store,
            reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))}

def snapshot.cursor.seek.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  ids: U32 & U32 & U32,
  lower: Maybe<&1, Bytes.Bytes>
) -> IO(DispatchResult):
  match ids:
    case (cursor_id, (response_id, take_id)):
      IO.pure(DispatchResult, snapshot.cursor.seek.taken(handle, snapshots,
        context, (cursor_id, response_id), lower,
        CursorStore.take(cursors, take_id)))

def snapshot.cursor.seek(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32,
  lower: Maybe<&1, Bytes.Bytes>
) -> IO(DispatchResult):
  snapshot.cursor.seek.ids(handle, snapshots, cursors, context,
    Protocol.u32.duplicate.triple(cursor_id), lower)

def dispatch.decoded.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  decision: Operation.Decision
) -> IO(DispatchResult):
  match decision:
    case Operation.Decoded{Operation.Stats{}}:
      dispatch.stats.state(handle, snapshots, cursors, context)
    case Operation.Decoded{Operation.SnapshotOpen{}}:
      snapshot.open(handle, snapshots, context, cursors)
    case Operation.Decoded{Operation.SnapshotGet{snapshot_id, key}}:
      snapshot.get(handle, snapshots, cursors, context, snapshot_id, key)
    case Operation.Decoded{Operation.SnapshotClose{snapshot_id}}:
      snapshot.close(handle, snapshots, cursors, context, snapshot_id)
    case Operation.Decoded{Operation.SnapshotCursorOpen{snapshot_id, bounds}}:
      snapshot.cursor.open(handle, snapshots, cursors, context, snapshot_id,
        bounds)
    case Operation.Decoded{Operation.SnapshotCursorNext{cursor_id}}:
      snapshot.cursor.next(handle, snapshots, cursors, context, cursor_id)
    case Operation.Decoded{Operation.SnapshotCursorClose{cursor_id}}:
      snapshot.cursor.close(handle, snapshots, cursors, context, cursor_id)
    case Operation.Decoded{Operation.SnapshotCursorSeek{cursor_id, lower}}:
      snapshot.cursor.seek(handle, snapshots, cursors, context, cursor_id,
        lower)
    case Operation.Decoded{Operation.Compact{}}:
      compact.preflight(handle, snapshots, cursors, context)
    case Operation.Decoded{operation}:
      do IO<DispatchResult>:
        pair : ByteDb.Handle & Protocol.Response <-
          dispatch.operation(handle, context, operation)
        return dispatch.result(pair, snapshots, cursors)
    case Operation.MalformedArguments{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Operation.UnsupportedOperation{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def dispatch.decoded(
  handle: ByteDb.Handle,
  context: ReplyContext,
  decision: Operation.Decision
) -> IO(ByteDb.Handle & Protocol.Response):
  match decision:
    case Operation.Decoded{operation}:
      dispatch.operation(handle, context, operation)
    case Operation.MalformedArguments{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{},
          Bytes.new(0))))
    case Operation.UnsupportedOperation{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{},
          Bytes.new(0))))

def dispatch.validated(
  handle: ByteDb.Handle,
  context: ReplyContext,
  decision: Protocol.Decision
) -> IO(ByteDb.Handle & Protocol.Response):
  match decision:
    case Protocol.Accepted{_, operation_code, payload}:
      dispatch.decoded(handle, context,
        Operation.decode.payload(operation_code, payload))
    case Protocol.VersionMismatch{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Protocol.StaleGeneration{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Protocol.UnsupportedRequestOperation{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Protocol.ResourceLimit{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))))

def dispatch.validated.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  decision: Protocol.Decision
) -> IO(DispatchResult):
  match decision:
    case Protocol.Accepted{_, operation_code, payload}:
      dispatch.decoded.state(handle, snapshots, cursors, context,
        Operation.decode.payload(operation_code, payload))
    case Protocol.VersionMismatch{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Protocol.StaleGeneration{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Protocol.UnsupportedRequestOperation{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Protocol.ResourceLimit{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})

def dispatch.request.copies(
  handle: ByteDb.Handle,
  versions: U32 & U32 & U32,
  generations: U32 & U32 & U32,
  request_ids: U32 & U32 & U32,
  operation_code: U32,
  payload: Bytes.Bytes,
  active_generations: U32 & U32
) -> IO(ByteDb.Handle & Protocol.Response):
  match versions:
    case (version, (response_version, response_version_hold)):
      match generations:
        case (generation, (_, response_generation_hold)):
          match request_ids:
            case (request_id, (response_id, response_id_hold)):
              match active_generations:
                case (response_generation, active_generation):
                  dispatch.validated(handle,
                    ReplyContext{(response_version, response_version_hold),
                      (Generation.response.generation(response_generation),
                        response_generation_hold),
                      (response_id, response_id_hold),
                      ResourceOptions.defaults()},
                    Protocol.validate(
                      Protocol.Request{version, generation, request_id,
                        operation_code, payload},
                      1, active_generation, Protocol.max_payload_bytes()))

def dispatch.request.copies.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  versions: U32 & U32 & U32,
  generations: U32 & U32 & U32,
  request_ids: U32 & U32 & U32,
  operation_code: U32,
  payload: Bytes.Bytes,
  active_generations: U32 & U32,
  options: ResourceOptions.Options
) -> IO(DispatchResult):
  match versions:
    case (version, (response_version, response_version_hold)):
      match generations:
        case (generation, (_, response_generation_hold)):
          match request_ids:
            case (request_id, (response_id, response_id_hold)):
              match active_generations:
                case (response_generation, active_generation):
                  dispatch.validated.state(handle, snapshots, cursors,
                    ReplyContext{(response_version, response_version_hold),
                      (Generation.response.generation(response_generation),
                        response_generation_hold),
                      (response_id, response_id_hold), options},
                    Protocol.validate(
                      Protocol.Request{version, generation, request_id,
                        operation_code, payload},
                      1, active_generation, Protocol.max_payload_bytes()))

def u32.duplicate.pair.from(triple: U32 & U32 & U32) -> U32 & U32:
  match triple:
    case (first, (second, _)): (first, second)

def u32.duplicate.pair(value: U32) -> U32 & U32:
  u32.duplicate.pair.from(Protocol.u32.duplicate.triple(value))

def dispatch.request(
  handle: ByteDb.Handle,
  request: Protocol.Request,
  active_generation: U32
) -> IO(ByteDb.Handle & Protocol.Response):
  match request:
    case Protocol.Request{version, generation, request_id, operation_code, payload}:
      dispatch.request.copies(handle,
        Protocol.u32.duplicate.triple(version),
        Protocol.u32.duplicate.triple(generation),
        Protocol.u32.duplicate.triple(request_id), operation_code, payload,
        u32.duplicate.pair(active_generation))

def dispatch.request.with_options(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  active_generation: U32,
  options: ResourceOptions.Options
) -> IO(DispatchResult):
  match request:
    case Protocol.Request{version, generation, request_id, operation_code, payload}:
      dispatch.request.copies.state(handle, snapshots, cursors,
        Protocol.u32.duplicate.triple(version),
        Protocol.u32.duplicate.triple(generation),
        Protocol.u32.duplicate.triple(request_id), operation_code, payload,
        u32.duplicate.pair(active_generation), options)

def dispatch.request.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  active_generation: U32
) -> IO(DispatchResult):
  dispatch.request.with_options(handle, snapshots, cursors, request,
    active_generation, ResourceOptions.defaults())

def serve.closed(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> IO(ByteDb.Handle & SnapshotStore.Store & CursorStore.Store):
  match pair:
    case (connection, _):
      do IO<ByteDb.Handle & SnapshotStore.Store & CursorStore.Store>:
        _closed : Unit <- File.close(connection)
        return (handle, snapshots, cursors)

def bound.response.bounded(
  version: U32,
  generation: U32,
  request_id: U32,
  +length: U32,
  words: Array<U32>,
  bounded: ResponseBound.Bounded
) -> Protocol.Response:
  match bounded:
    case ResponseBound.Bounded{status, True{}}:
      Protocol.Response{version, generation, request_id, status,
        Bytes.Bytes{length, words}}
    case ResponseBound.Bounded{status, False{}}:
      Protocol.Response{version, generation, request_id, status,
        Bytes.new(0)}

def bound.response.decided(
  mutation: Bool,
  version: U32,
  generation: U32,
  request_id: U32,
  status: Protocol.ResponseStatus,
  +length: U32,
  words: Array<U32>,
  fits: Bool
) -> Protocol.Response:
  bound.response.bounded(version, generation, request_id, length, words,
    ResponseBound.bound(mutation, status, ResponseBound.outcome(fits)))

def bound.response(
  mutation: Bool,
  version: U32,
  generation: U32,
  request_id: U32,
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes,
  max_bytes: U32
) -> Protocol.Response:
  match payload:
    case Bytes.Bytes{+length, words}:
      bound.response.decided(mutation, version, generation, request_id, status,
        length, words, ResourceOptions.response.admitted(length, max_bytes))

def bound.response.result(
  mutation: Bool,
  response: Protocol.Response,
  max_bytes: U32
) -> Protocol.Response:
  match response:
    case Protocol.Response{version, generation, request_id, status, payload}:
      bound.response(mutation, version, generation, request_id, status, payload,
        max_bytes)

def serve.response(
  connection: File,
  result: DispatchResult,
  max_response_bytes: U32
) -> IO(ByteDb.Handle & SnapshotStore.Store & CursorStore.Store):
  match result:
    case DispatchResult{handle, snapshots, cursors, response}:
      do IO<ByteDb.Handle & SnapshotStore.Store & CursorStore.Store>:
        bounded : Protocol.Response =
          bound.response.result(False{}, response, max_response_bytes)
        written : File & Result<&1, &1, U32 & String, Unit> <-
          Io.write_all(connection, Protocol.encode_response(bounded))
        serve.closed(written, handle, snapshots, cursors)

def serve.reactor.dispatch.complete(
  server: File,
  context: ReactorContext
) -> ServiceState:
  reactor.state(server, context)

def serve.reactor.dispatch.context(
  updated: ByteDb.Handle & SnapshotStore.Store & CursorStore.Store,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  _cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue
) -> ReactorContext:
  match updated:
    case (handle, (snapshots, cursors)):
      ReactorContext{handle, endpoint, generation, options, snapshots,
        cursors, Nil{}, next_connection_id, accepted_sequence, queue}

def reactor.append.connections(
  left: List<&1, Connections.Connection>,
  right: List<&1, Connections.Connection>
) -> List<&1, Connections.Connection>:
  match left:
    case Nil{}: right
    case Con{connection, rest}:
      Con{connection, reactor.append.connections(rest, right)}

def reactor.dispatch.deadline(
  result: Result<&1, &1, U32 & String, Nat>,
  timeout_ms: U32
) -> Nat:
  match result:
    case Done{+now}:
      Nat.add(now, Nat.mul(U32.to_nat(timeout_ms), 1000n))
    case Fail{_}: 0n

def reactor.dispatch.encode(
  mutation: Bool,
  result: DispatchResult,
  reservation: TxPolicy.DispatchReservation
) -> EncodedDispatch:
  match result reservation:
    case DispatchResult{handle, snapshots, cursors, response}
      TxPolicy.DispatchReservation{connection_id, request_bytes,
        +payload_limit, peak_bytes}:
      EncodedDispatch{handle, snapshots, cursors,
        Protocol.encode_response(
          bound.response.result(mutation, response, payload_limit)),
        TxPolicy.tx.frame.transfer(TxPolicy.DispatchReservation{
          connection_id, request_bytes, payload_limit, peak_bytes})}

def reactor.dispatch.response.context(
  result: EncodedDispatch,
  id: U32,
  socket: File,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  response_connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  deadline_ms: Nat
) -> ReactorContext:
  match result:
    case EncodedDispatch{handle, snapshots, cursors, bytes, reservation}:
      ReactorContext{handle, endpoint, generation, options, snapshots,
        cursors,
        Con{Connections.Connection{id, socket, 4,
          Connections.WritingResponse{bytes, 0, deadline_ms, reservation}},
          response_connections},
        next_connection_id, accepted_sequence, queue}

def reactor.dispatch.observe.measured(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  reservation: TxPolicy.FrameReservation,
  measured: Bytes.Bytes & U32
) -> IO(EncodedDispatch):
  match measured:
    case (bytes, length):
      do IO<EncodedDispatch>:
        observed : TxPolicy.FrameReservation <- Observation.framed(reservation, length)
        return EncodedDispatch{handle, snapshots, cursors, bytes, observed}

# Records the encoded frame while retaining its affine reservation.
def reactor.dispatch.observe.encoded(result: EncodedDispatch) -> IO(EncodedDispatch):
  match result:
    case EncodedDispatch{handle, snapshots, cursors, bytes, reservation}:
      reactor.dispatch.observe.measured(handle, snapshots, cursors,
        reservation, Bytes.length(bytes))

def serve.reactor.dispatch.response(
  mutation: Bool,
  result: DispatchResult,
  reservation: TxPolicy.DispatchReservation,
  id: U32,
  socket: File,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  response_connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue
) -> IO(ReactorContext):
  do IO<ReactorContext>:
    encoded : EncodedDispatch <- reactor.dispatch.observe.encoded(
      reactor.dispatch.encode(mutation, result, reservation))
    clock : Result<&1, &1, U32 & String, Nat> <- Fs.clock_monotonic()
    return reactor.dispatch.response.context(encoded, id, socket, endpoint,
      generation, options, response_connections, next_connection_id,
      accepted_sequence, queue,
      reactor.dispatch.deadline(clock,
        ResourceOptions.transport.response.timeout(options)))

def close.connections(connections: List<&1, Connections.Connection>) -> IO(Unit):
  match connections:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{connection, rest}:
      match connection:
        case Connections.Connection{id, socket, _, _}:
          do IO<Unit>:
            _observed : Unit <- Observation.closed(id)
            _closed : Unit <- File.close(socket)
            close.connections(rest)

def close.poll.interests(
  interests: List<SocketTypes.PollInterest>
) -> IO(Unit):
  match interests:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{interest, rest}:
      match interest:
        case SocketTypes.PollInterest{id, socket, _}:
          do IO<Unit>:
            _observed : Unit <- Observation.closed(id)
            _closed : Unit <- File.close(socket)
            close.poll.interests(rest)

def serve.reactor.dispatch.completed(
  mutation: Bool,
  server: File,
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  other_connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  id: U32,
  socket: File,
  completed: TxPolicy.DispatchCompletion
) -> IO(ServiceState):
  match completed:
    case TxPolicy.DispatchCompleted{reservation, response}:
      do IO<ServiceState>:
        next_context : ReactorContext <-
          serve.reactor.dispatch.response(mutation,
            DispatchResult{handle, snapshots, cursors, response},
            reservation, id, socket, endpoint, generation, options,
            other_connections, next_connection_id, accepted_sequence, queue)
        return serve.reactor.dispatch.complete(server, next_context)
    case TxPolicy.DispatchCompletionRejected{_, _}:
      do IO<ServiceState>:
        _observed : Unit <- Observation.closed(id)
        _closed_socket : Unit <- File.close(socket)
        _closed_peers : Unit <- close.connections(other_connections)
        return Stopping{server, handle, endpoint,
          "dispatch completion without an active reservation", cursors}

def serve.reactor.dispatch.finished(
  mutation: Bool,
  server: File,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  other_connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  id: U32,
  socket: File,
  flight: TxPolicy.InFlight,
  result: DispatchResult
) -> IO(ServiceState):
  match result:
    case DispatchResult{handle, snapshots, cursors, response}:
      serve.reactor.dispatch.completed(mutation, server, handle, snapshots,
        cursors,
        endpoint, generation, options, other_connections, next_connection_id,
        accepted_sequence, queue, id, socket,
        TxPolicy.tx.flight.complete(flight, response))

def serve.reactor.dispatch.started(
  mutation: Bool,
  generations: U32 & U32 & U32,
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  other_connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  id: U32,
  socket: File,
  started: TxPolicy.DispatchStart
) -> IO(ServiceState):
  match generations started:
    case (dispatch_generation, (response_generation, _))
      TxPolicy.DispatchStarted{flight, request}:
      do IO<ServiceState>:
        observed_flight : TxPolicy.InFlight <- Observation.dispatched(flight)
        dispatched : DispatchResult <-
          dispatch.request.with_options(handle, snapshots, cursors, request,
            dispatch_generation, options)
        serve.reactor.dispatch.finished(mutation, server, endpoint,
          response_generation,
          options, other_connections, next_connection_id, accepted_sequence,
          queue, id, socket, observed_flight, dispatched)
    case _ TxPolicy.DispatchAlreadyStarted{_}:
      do IO<ServiceState>:
        _observed : Unit <- Observation.closed(id)
        _closed_socket : Unit <- File.close(socket)
        _closed_peers : Unit <- close.connections(other_connections)
        return Stopping{server, handle, endpoint,
          "request was already dispatched", cursors}

def serve.reactor.dispatch.pending.connection(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  other_connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  connection: Connections.Connection,
  request: Protocol.Request,
  request_bytes: Nat,
  deadline: ConnectionPolicy.DeadlineDecision
) -> IO(ServiceState):
  match connection:
    case Connections.Connection{+id, socket, _, phase}:
      match phase:
        case Connections.Queued{_, bound}:
          match request:
            case Protocol.Request{version, request_generation, request_id,
              +operation, payload}:
              match deadline:
                case ConnectionPolicy.Continue{}:
                  serve.reactor.dispatch.started(
                    ClientPolicy.operation.is_mutation(operation),
                    Protocol.u32.duplicate.triple(generation), server,
                    handle, endpoint, options, snapshots, cursors,
                    other_connections, next_connection_id, accepted_sequence,
                    queue, id, socket,
                    TxPolicy.tx.flight.start(TxPolicy.tx.flight.reserved(
                      id, request_bytes, bound,
                      Protocol.Request{version, request_generation, request_id,
                        operation, payload})))
                case ConnectionPolicy.Expire{}:
                  do IO<ServiceState>:
                    timed_out : DispatchResult = DispatchResult{handle,
                      snapshots, cursors,
                      Protocol.Response{version, request_generation,
                        request_id, Protocol.Timeout{}, Bytes.new(0)}}
                    next_context : ReactorContext <-
                      serve.reactor.dispatch.response(False{}, timed_out,
                        TxPolicy.DispatchReservation{id, 0n, 0, 0n}, id, socket,
                        endpoint, generation, options, other_connections,
                        next_connection_id, accepted_sequence, queue)
                    return serve.reactor.dispatch.complete(server,
                      next_context)
        case _:
          do IO<ServiceState>:
            _closed : Unit <- close.connections(
              Con{connection, other_connections})
            return Stopping{server, handle, endpoint,
              "queued request connection phase mismatch", cursors}

def serve.reactor.dispatch.pending.detached(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  now: Nat,
  deadline_ms: Nat,
  request: Protocol.Request,
  request_bytes: Nat,
  detached: Connections.DetachResult
) -> IO(ServiceState):
  match detached:
    case Connections.Detached{other_connections, connection}:
      serve.reactor.dispatch.pending.connection(server, handle, endpoint,
        generation, options, snapshots, cursors, other_connections,
        next_connection_id, accepted_sequence, queue, connection, request,
        request_bytes,
        ConnectionPolicy.deadline(now, deadline_ms))
    case Connections.DetachNotFound{retained}:
      IO.pure(ServiceState, ReactorServing{server, handle, endpoint,
        generation, options, snapshots, cursors, retained,
        next_connection_id, accepted_sequence, queue})
    case Connections.DetachExhausted{state}:
      do IO<ServiceState>:
        _closed : Unit <- close.connections(
          Connections.detach.state.connections(state))
        return Stopping{server, handle, endpoint,
          "connection lookup fuel exhausted", cursors}

def serve.reactor.dispatch.pending.taken(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  now: Nat,
  connection_id: U32,
  deadline_ms: Nat,
  request: Protocol.Request,
  request_bytes: Nat
) -> IO(ServiceState):
  serve.reactor.dispatch.pending.detached(server, handle, endpoint,
    generation, options, snapshots, cursors, next_connection_id,
    accepted_sequence, queue, now, deadline_ms, request, request_bytes,
    Connections.detach(connections, connection_id))

def serve.reactor.dispatch.queue.result(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  now: Nat,
  result: RequestQueue.TakeResult
) -> IO(ServiceState):
  match result:
    case RequestQueue.Empty{queue}:
      IO.pure(ServiceState, ReactorServing{server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, queue})
    case RequestQueue.Taken{queue, pending}:
      match pending:
        case RequestQueue.Pending{connection_id, _, deadline_ms,
            request_bytes, _, request}:
          serve.reactor.dispatch.pending.taken(server, handle, endpoint,
            generation, options, snapshots, cursors, connections,
            next_connection_id, accepted_sequence, queue, now,
            connection_id, deadline_ms, request, request_bytes)

def reactor.transmit.used(metrics: Connections.TransmitCount) -> Nat:
  match metrics:
    case Connections.TransmitCount{_, bytes, _, _, _, _}: bytes

def reactor.resource.limit.response(request: Protocol.Request)
  -> Protocol.Response:
  match request:
    case Protocol.Request{version, generation, request_id, _, _}:
      Protocol.Response{version, generation, request_id,
        Protocol.ResponseResourceLimit{}, Bytes.new(0)}

def serve.reactor.dispatch.resource.detached(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  pending: RequestQueue.Pending,
  detached: Connections.DetachResult
) -> IO(ServiceState):
  match pending:
    case RequestQueue.Pending{_, _, _, _, _, request}:
      match detached:
        case Connections.Detached{connections, connection}:
          match connection:
            case Connections.Connection{+id, socket, _, _}:
              do IO<ServiceState>:
                response_context : ReactorContext <-
                  serve.reactor.dispatch.response(False{},
                    DispatchResult{handle, snapshots, cursors,
                      reactor.resource.limit.response(request)},
                    TxPolicy.DispatchReservation{id, 0n, 0, 0n},
                    id, socket, endpoint, generation, options, connections,
                    next_connection_id, accepted_sequence, queue)
                return serve.reactor.dispatch.complete(server,
                  response_context)
        case Connections.DetachNotFound{connections}:
          IO.pure(ServiceState, ReactorServing{server, handle, endpoint,
            generation, options, snapshots, cursors, connections,
            next_connection_id, accepted_sequence, queue})
        case Connections.DetachExhausted{state}:
          do IO<ServiceState>:
            _closed : Unit <- close.connections(
              Connections.detach.state.connections(state))
            return Stopping{server, handle, endpoint,
              "connection lookup fuel exhausted", cursors}

def serve.reactor.dispatch.resource.pending.id(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  ids: U32 & U32 & U32,
  request_sequence: Nat,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  response_peak: Nat,
  request: Protocol.Request
) -> IO(ServiceState):
  match ids:
    case (pending_id, (detach_id, _)):
      serve.reactor.dispatch.resource.detached(server, handle, endpoint,
        generation, options, snapshots, cursors, next_connection_id,
        accepted_sequence, queue,
        RequestQueue.Pending{pending_id, request_sequence, deadline_ms,
          encoded_bytes, response_peak, request},
        Connections.detach(connections, detach_id))

def serve.reactor.dispatch.resource.pending(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  pending: RequestQueue.Pending
) -> IO(ServiceState):
  match pending:
    case RequestQueue.Pending{+connection_id, request_sequence,
      deadline_ms, encoded_bytes, response_peak, request}:
      serve.reactor.dispatch.resource.pending.id(server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, queue,
        Protocol.u32.duplicate.triple(connection_id), request_sequence,
        deadline_ms, encoded_bytes, response_peak, request)

def serve.reactor.dispatch.resource.rejected(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  taken: RequestQueue.TakeResult
) -> IO(ServiceState):
  match taken:
    case RequestQueue.Empty{queue}:
      IO.pure(ServiceState, ReactorServing{server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, queue})
    case RequestQueue.Taken{queue, pending}:
      serve.reactor.dispatch.resource.pending(server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, queue, pending)

def serve.reactor.dispatch.queue.decided(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  now: Nat,
  decision: TxPolicy.QueueReservation
) -> IO(ServiceState):
  match decision:
    case TxPolicy.QueueKeep{queue}:
      IO.pure(ServiceState, ReactorServing{server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, queue})
    case TxPolicy.QueueDispatch{queue}:
      serve.reactor.dispatch.queue.result(server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, now, RequestQueue.take(queue))
    case TxPolicy.QueueReject{queue}:
      serve.reactor.dispatch.resource.rejected(server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, RequestQueue.take(queue))
    case TxPolicy.QueueExpire{queue}:
      serve.reactor.dispatch.queue.result(server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, now, RequestQueue.take(queue))

def serve.reactor.dispatch.queue.reserved(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  decision: TxPolicy.QueueReservation,
  measured: Connections.TransmitCount,
  now: Nat
) -> IO(ServiceState):
  match measured:
    case Connections.TransmitCount{retained_connections, _, _, _, _, _}:
      serve.reactor.dispatch.queue.decided(server, handle, endpoint,
        generation, options, snapshots, cursors, retained_connections,
        next_connection_id, accepted_sequence, now, decision)

def serve.reactor.dispatch.queue.peeked.measured(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  reservation_now: Nat,
  dispatch_now: Nat,
  measured: Connections.TransmitCount,
  result: RequestQueue.PeekResult
) -> IO(ServiceState):
  match measured result:
    case Connections.TransmitCount{connections, +bytes, count, live, control, header} peeked:
      serve.reactor.dispatch.queue.reserved(server, handle, endpoint,
        generation, options, snapshots, cursors, next_connection_id,
        accepted_sequence,
        TxPolicy.tx.queue.reserve.peeked(peeked, bytes,
          TxPolicy.tx.capacity(
            ResourceOptions.transport.response.bytes(options)),
          reservation_now),
        Connections.TransmitCount{connections, bytes, count, live, control, header}, dispatch_now)

def serve.reactor.dispatch.queue.peeked(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  times: Nat & Nat,
  measured: Connections.TransmitCount,
  result: RequestQueue.PeekResult
) -> IO(ServiceState):
  match times:
    case (reservation_now, dispatch_now):
      serve.reactor.dispatch.queue.peeked.measured(server, handle, endpoint,
        generation, options, snapshots, cursors, next_connection_id,
        accepted_sequence, reservation_now, dispatch_now, measured, result)

def reactor.cursor.head.budget.paired(
  cursors: CursorStore.Store,
  queue: RequestQueue.Queue,
  paired: TxPolicy.BoundDecision & Nat
) -> CursorHeadBudget:
  match paired:
    case (bound, peak):
      CursorHeadBudget{cursors, RequestQueue.head.peak(queue, peak), bound}

def reactor.cursor.head.budget(
  queue: RequestQueue.Queue,
  response_bytes: U32,
  preview: CursorStore.PreviewResult
) -> CursorHeadBudget:
  match preview:
    case CursorStore.PreviewReady{cursors, payload_bytes}:
      reactor.cursor.head.budget.paired(cursors, queue,
        Connections.admission.response.bound(
          TxPolicy.tx.payload.bound(payload_bytes, response_bytes)))
    case CursorStore.PreviewTerminal{cursors, payload_bytes}:
      reactor.cursor.head.budget.paired(cursors, queue,
        Connections.admission.response.bound(
          TxPolicy.tx.payload.bound(payload_bytes, response_bytes)))
    case CursorStore.PreviewRejected{cursors}:
      CursorHeadBudget{cursors, RequestQueue.head.peak(queue, 28n),
        TxPolicy.Bounded{0, 28n}}

def serve.reactor.dispatch.queue.cursor.prepared(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  now: Nat,
  connection_id: U32,
  prepared: CursorHeadBudget
) -> IO(ServiceState):
  match prepared:
    case CursorHeadBudget{cursors, queue, bound}:
      serve.reactor.dispatch.queue.peeked(server, handle, endpoint,
        generation, options, snapshots, cursors, next_connection_id,
        accepted_sequence, Protocol.nat.duplicate.pair(now),
        Connections.transmit.metrics(
          Connections.queued.bound.connections(connections, connection_id,
            bound)), RequestQueue.peek(queue))

def serve.reactor.dispatch.queue.cursor.previewed(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  now: Nat,
  queue: RequestQueue.Queue,
  connection_id: U32,
  preview: CursorStore.PreviewResult
) -> IO(ServiceState):
  serve.reactor.dispatch.queue.cursor.prepared(server, handle, endpoint,
    generation, options, snapshots, connections, next_connection_id,
    accepted_sequence, now, connection_id,
    reactor.cursor.head.budget(queue,
      ResourceOptions.transport.response.bytes(options), preview))

def serve.reactor.dispatch.queue.cursor.inspect(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  now: Nat,
  peeked: RequestQueue.CursorPeek
) -> IO(ServiceState):
  match peeked:
    case RequestQueue.CursorPeek{queue, None{}, _}:
      serve.reactor.dispatch.queue.peeked(server, handle, endpoint,
        generation, options, snapshots, cursors, next_connection_id,
        accepted_sequence, Protocol.nat.duplicate.pair(now),
        Connections.transmit.metrics(connections), RequestQueue.peek(queue))
    case RequestQueue.CursorPeek{queue, Some{cursor_id}, connection_id}:
      do IO<ServiceState>:
        preview : CursorStore.PreviewResult <-
          CursorStore.preview(cursors, cursor_id)
        serve.reactor.dispatch.queue.cursor.previewed(server, handle,
          endpoint, generation, options, snapshots, connections,
          next_connection_id, accepted_sequence, now, queue,
          connection_id, preview)

def serve.reactor.dispatch.queue.one(
  server: File,
  context: ReactorContext,
  now: Nat
) -> IO(ServiceState):
  match context:
    case ReactorContext{handle, endpoint, generation, +options, snapshots,
      cursors, connections, next_connection_id, accepted_sequence, queue}:
      serve.reactor.dispatch.queue.cursor.inspect(server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, now,
        RequestQueue.peek.cursor(queue))

def reactor.response.preflight.request.decoded(
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  retained_payload: Bytes.Bytes,
  decoded: Operation.Decision,
  response_bytes: U32
) -> ResponsePreflight:
  match decoded:
    case Operation.Decoded{Operation.Get{key}}:
      PreflightGet{Protocol.Request{version, generation, request_id,
        operation, retained_payload}, key}
    case Operation.Decoded{Operation.Stats{}}:
      PreflightStats{Protocol.Request{version, generation, request_id,
        operation, retained_payload}}
    case Operation.Decoded{Operation.DescribeOwner{}}:
      PreflightBounded{Protocol.Request{version, generation, request_id,
        operation, retained_payload}, TxPolicy.tx.payload.bound(76n,
          response_bytes)}
    case Operation.Decoded{Operation.SnapshotCursorNext{cursor_id}}:
      PreflightCursorNext{Protocol.Request{version, generation, request_id,
        operation, retained_payload}, cursor_id}
    case Operation.Decoded{Operation.SnapshotGet{snapshot_id, key}}:
      PreflightSnapshotGet{Protocol.Request{version, generation, request_id,
        operation, retained_payload}, snapshot_id, key}
    case Operation.Decoded{Operation.SnapshotOpen{}}:
      PreflightBounded{Protocol.Request{version, generation, request_id,
        operation, retained_payload}, TxPolicy.tx.payload.bound(4n,
          response_bytes)}
    case Operation.Decoded{Operation.SnapshotCursorOpen{_, _}}:
      PreflightBounded{Protocol.Request{version, generation, request_id,
        operation, retained_payload}, TxPolicy.tx.payload.bound(4n,
          response_bytes)}
    case _:
      PreflightBounded{Protocol.Request{version, generation, request_id,
        operation, retained_payload},
        TxPolicy.tx.payload.bound(0n, response_bytes)}

def reactor.response.preflight.request.cloned(
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  payloads: Bytes.Bytes & Bytes.Bytes,
  response_bytes: U32
) -> ResponsePreflight:
  match payloads:
    case (inspect_payload, retained_payload):
      reactor.response.preflight.request.decoded(version, generation,
        request_id, operation, retained_payload,
        Operation.decode.payload(operation, inspect_payload), response_bytes)

def reactor.response.preflight.request(
  request: Protocol.Request,
  response_bytes: U32
) -> ResponsePreflight:
  match request:
    case Protocol.Request{+version, +generation, +request_id, +operation,
        payload}:
      reactor.response.preflight.request.cloned(version, generation,
        request_id, operation, ByteMemTable.bytes.clone(payload),
        response_bytes)

def reactor.response.preflight.get.result(
  request: Protocol.Request,
  result: Result<&1, &1, ByteDb.Error, Maybe<&1, U32>>,
  response_bytes: U32,
  capacity: Nat
) -> ResponseBoundRequest:
  match result:
    case Done{Some{value_bytes}}:
      ResponseBoundRequest{request,
        TxPolicy.tx.get.bound(value_bytes, response_bytes, capacity)}
    case Done{None{}}:
      ResponseBoundRequest{request, TxPolicy.Bounded{0, 28n}}
    case Fail{_}:
      ResponseBoundRequest{request, TxPolicy.Bounded{0, 28n}}

def reactor.response.preflight.get.measured(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, U32>>,
  request: Protocol.Request,
  response_bytes: U32,
  capacity: Nat
) -> ByteDb.Handle & ResponseBoundRequest:
  match pair:
    case (handle, result):
      (handle, reactor.response.preflight.get.result(request, result,
        response_bytes, capacity))

def reactor.response.preflight.get.bound(
  measured: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, U32>>,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  response_bytes: U32,
  capacity: Nat
) -> ResponseBoundState:
  match measured:
    case (handle, result):
      ResponseBoundState{handle, snapshots, cursors,
        reactor.response.preflight.get.result(request, result,
          response_bytes, capacity)}

def reactor.response.preflight.cursor.bound.result(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  request: Protocol.Request,
  response_bytes: U32,
  measured: CursorStore.PreviewResult
) -> ResponseBoundState:
  match measured:
    case CursorStore.PreviewReady{cursors, payload_bytes}:
      ResponseBoundState{handle, snapshots, cursors, ResponseBoundRequest{request,
          TxPolicy.tx.payload.bound(payload_bytes, response_bytes)}}
    case CursorStore.PreviewTerminal{cursors, payload_bytes}:
      ResponseBoundState{handle, snapshots, cursors, ResponseBoundRequest{request,
          TxPolicy.tx.payload.bound(payload_bytes, response_bytes)}}
    case CursorStore.PreviewRejected{cursors}:
      ResponseBoundState{handle, snapshots, cursors,
        ResponseBoundRequest{request, TxPolicy.Bounded{0, 28n}}}

def reactor.response.preflight.cursor.bound(
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  handle: ByteDb.Handle,
  request: Protocol.Request,
  cursor_id: U32,
  response_bytes: U32
) -> IO(ResponseBoundState):
  do IO<ResponseBoundState>:
    measured : CursorStore.PreviewResult <- CursorStore.preview(cursors,
      cursor_id)
    return reactor.response.preflight.cursor.bound.result(handle, snapshots,
      request, response_bytes, measured)

def reactor.response.preflight.snapshot.bound.result(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  measured: SnapshotStore.Store & TxPolicy.BoundDecision
) -> ResponseBoundState:
  match measured:
    case (updated_snapshots, bound):
      ResponseBoundState{handle, updated_snapshots, cursors,
        ResponseBoundRequest{request, bound}}

def reactor.response.preflight.snapshot.bound(
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  handle: ByteDb.Handle,
  request: Protocol.Request,
  snapshot_id: U32,
  response_bytes: U32
) -> ResponseBoundState:
  reactor.response.preflight.snapshot.bound.result(handle, cursors, request,
    SnapshotStore.snapshot.response.bound(snapshots, snapshot_id,
      response_bytes))

def reactor.response.preflight.snapshot.value.bound(
  handle: ByteDb.Handle,
  updated_snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  measured: Result<&1, &1, ByteDb.Error, Maybe<&1, U32>>,
  response_bytes: U32
) -> ResponseBoundState:
  match measured:
    case Fail{_}:
      ResponseBoundState{handle, updated_snapshots, cursors,
        ResponseBoundRequest{request,
          TxPolicy.tx.payload.bound(0n, response_bytes)}}
    case Done{None{}}:
      ResponseBoundState{handle, updated_snapshots, cursors,
        ResponseBoundRequest{request,
          TxPolicy.tx.payload.bound(0n, response_bytes)}}
    case Done{Some{value_bytes}}:
      ResponseBoundState{handle, updated_snapshots, cursors,
        ResponseBoundRequest{request,
          TxPolicy.tx.payload.bound(U32.to_nat(value_bytes),
            response_bytes)}}

def reactor.response.preflight.snapshot.value.measured(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  measured_store: SnapshotStore.Store & IO(Result<&1, &1, ByteDb.Error,
    Maybe<&1, U32>>),
  response_bytes: U32
) -> IO(ResponseBoundState):
  match measured_store:
    case (updated_snapshots, measurement):
      do IO<ResponseBoundState>:
        measured : Result<&1, &1, ByteDb.Error, Maybe<&1, U32>> <- measurement
        return reactor.response.preflight.snapshot.value.bound(handle,
          updated_snapshots, cursors, request, measured, response_bytes)

def reactor.response.preflight.snapshot.value(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  snapshot_id: U32,
  key: Bytes.Bytes,
  response_bytes: U32
) -> IO(ResponseBoundState):
  reactor.response.preflight.snapshot.value.measured(handle, cursors, request,
    SnapshotStore.value_length(snapshots, snapshot_id, key), response_bytes)

def reactor.response.preflight.stats.complete(
  handle: ByteDb.Handle,
  entries: Nat,
  payload_bytes: Nat,
  snapshot_count: Nat,
  retained_bytes: Nat,
  cursor_count: Nat,
  snapshot_store: SnapshotStore.Store,
  cursor_store: CursorStore.Store,
  request: Protocol.Request,
  response_bytes: U32
) -> ResponseBoundState:
  ResponseBoundState{handle, snapshot_store, cursor_store,
    ResponseBoundRequest{request, TxPolicy.tx.payload.bound(
      StatsCodec.payload.length(entries, payload_bytes, snapshot_count,
        retained_bytes, cursor_count), response_bytes)}}

def reactor.response.preflight.stats.cursors(
  handle: ByteDb.Handle,
  entries: Nat,
  payload_bytes: Nat,
  snapshot_count: Nat,
  retained_bytes: Nat,
  snapshot_store: SnapshotStore.Store,
  cursors: CursorStore.Metrics,
  request: Protocol.Request,
  response_bytes: U32
) -> ResponseBoundState:
  match cursors:
    case CursorStore.Metrics{count, store}:
      reactor.response.preflight.stats.complete(handle, entries,
        payload_bytes, snapshot_count, retained_bytes, count, snapshot_store,
        store, request, response_bytes)

def reactor.response.preflight.stats.measured(
  database: ByteDb.Handle & ByteDb.Stats,
  snapshots: SnapshotStore.Metrics,
  cursors: CursorStore.Metrics,
  request: Protocol.Request,
  response_bytes: U32
) -> ResponseBoundState:
  match database:
    case (handle, ByteDb.Stats{entries, payload_bytes}):
      match snapshots:
        case SnapshotStore.Metrics{snapshots, retained_bytes, store}:
          reactor.response.preflight.stats.cursors(handle, entries,
            payload_bytes, snapshots, retained_bytes, store, cursors, request,
            response_bytes)

def reactor.response.preflight.stats.bound(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  response_bytes: U32
) -> ResponseBoundState:
  reactor.response.preflight.stats.measured(ByteDb.stats(handle),
    SnapshotStore.metrics(snapshots), CursorStore.metrics(cursors), request,
    response_bytes)

def reactor.response.preflight.request.bound(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  decision: ResponsePreflight,
  response_bytes: U32,
  capacity: Nat
) -> IO(ResponseBoundState):
  match decision:
    case PreflightBounded{request, bound}:
      IO.pure(ResponseBoundState,
        ResponseBoundState{handle, snapshots, cursors,
          ResponseBoundRequest{request, bound}})
    case PreflightGet{request, key}:
      do IO<ResponseBoundState>:
        measured : ByteDb.Handle & Result<&1, &1, ByteDb.Error,
          Maybe<&1, U32>> <- ByteDb.value_length(handle, key)
        return reactor.response.preflight.get.bound(measured, snapshots,
          cursors, request, response_bytes, capacity)
    case PreflightStats{request}:
      IO.pure(ResponseBoundState,
        reactor.response.preflight.stats.bound(handle, snapshots, cursors,
          request, response_bytes))
    case PreflightSnapshotGet{request, snapshot_id, key}:
      reactor.response.preflight.snapshot.value(handle, snapshots, cursors,
        request, snapshot_id, key, response_bytes)
    case PreflightCursorNext{request, cursor_id}:
      reactor.response.preflight.cursor.bound(snapshots, cursors, handle,
        request, cursor_id, response_bytes)

def reactor.response.preflight.connection.bound(
  id: U32,
  socket: File,
  poll_events: U32,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  new_cursor: Maybe<&2, U32>,
  measured: ResponseBoundState
) -> ResponsePreflightConnection:
  match measured:
    case ResponseBoundState{handle, snapshots, cursors,
        ResponseBoundRequest{request, bound}}:
      ResponsePreflightConnection{handle, snapshots, cursors,
        Connections.Connection{id, socket, poll_events,
          Connections.BoundedAdmission{request, deadline_ms, encoded_bytes,
          bound}}, new_cursor}

def reactor.response.preflight.cursor.seen.loop(
  remaining: List<&2, U32>,
  cursor_ids: U32 & U32
) -> Bool:
  match remaining:
    case Nil{}: False{}
    case Con{id, tail}:
      match cursor_ids:
        case (query_id, next_id):
          U32.is_eq(id, query_id) ||
            reactor.response.preflight.cursor.seen.loop(tail,
              protocol.u32.duplicate.pair(next_id))

def reactor.response.preflight.cursor.seen(
  remaining: List<&2, U32>,
  cursor_id: U32
) -> Bool:
  reactor.response.preflight.cursor.seen.loop(remaining,
    protocol.u32.duplicate.pair(cursor_id))

def reactor.response.preflight.connection.request.measured(
  id: U32,
  socket: File,
  poll_events: U32,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  new_cursor: Maybe<&2, U32>,
  measured: ResponseBoundState
) -> ResponsePreflightConnection:
  reactor.response.preflight.connection.bound(id, socket, poll_events,
    deadline_ms, encoded_bytes, new_cursor, measured)

def reactor.response.preflight.connection.request.cursor(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  id: U32,
  socket: File,
  poll_events: U32,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  request: Protocol.Request,
  +cursor_id: U32,
  response_bytes: U32,
  capacity: Nat,
  decision: TxPolicy.CursorAdmissionDecision
) -> IO(ResponsePreflightConnection):
  match decision:
    case TxPolicy.WaitForEarlierCursorNext{}:
      IO.pure(ResponsePreflightConnection,
        ResponsePreflightConnection{handle, snapshots, cursors,
          Connections.Connection{id, socket, poll_events,
            Connections.AwaitingAdmission{request, deadline_ms,
              encoded_bytes}}, None{}})
    case TxPolicy.PrepareCursorNext{}:
      do IO<ResponsePreflightConnection>:
        measured : ResponseBoundState <-
          reactor.response.preflight.request.bound(handle, snapshots,
            cursors, PreflightCursorNext{request, cursor_id},
            response_bytes, capacity)
        return reactor.response.preflight.connection.request.measured(
          id, socket, poll_events, deadline_ms, encoded_bytes,
          Some{cursor_id}, measured)

def reactor.response.preflight.connection.request.cursor.start(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  id: U32,
  socket: File,
  poll_events: U32,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  request: Protocol.Request,
  ids: U32 & U32,
  seen_cursor_ids: List<&2, U32>,
  response_bytes: U32 & U32,
  capacity: Nat
) -> IO(ResponsePreflightConnection):
  match ids:
    case (seen_id, cursor_id):
      match response_bytes:
        case (seen_bytes, bound_bytes):
          reactor.response.preflight.connection.request.cursor(handle,
            snapshots, cursors, id, socket, poll_events, deadline_ms,
            encoded_bytes, request, cursor_id, bound_bytes, capacity,
            TxPolicy.tx.cursor.admission(
              reactor.response.preflight.cursor.seen(seen_cursor_ids,
                seen_id)))

def reactor.response.preflight.connection.request(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  id: U32,
  socket: File,
  poll_events: U32,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  seen_cursor_ids: List<&2, U32>,
  response_bytes: U32,
  capacity: Nat,
  decision: ResponsePreflight
) -> IO(ResponsePreflightConnection):
  match decision:
    case PreflightCursorNext{request, cursor_id}:
      reactor.response.preflight.connection.request.cursor.start(handle,
        snapshots, cursors, id, socket, poll_events, deadline_ms,
        encoded_bytes, request,
        protocol.u32.duplicate.pair(cursor_id), seen_cursor_ids,
        protocol.u32.duplicate.pair(response_bytes), capacity)
    case _:
      do IO<ResponsePreflightConnection>:
        measured : ResponseBoundState <-
          reactor.response.preflight.request.bound(handle, snapshots,
            cursors, decision, response_bytes, capacity)
        return reactor.response.preflight.connection.request.measured(
          id, socket, poll_events, deadline_ms, encoded_bytes, None{},
          measured)

def reactor.response.preflight.connection(
  handle: ByteDb.Handle,
  connection: Connections.Connection,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  seen_cursor_ids: List<&2, U32>,
  +response_bytes: U32,
  capacity: Nat
) -> IO(ResponsePreflightConnection):
  match connection:
    case Connections.Connection{id, socket, poll_events, phase}:
      match phase:
        case Connections.AwaitingAdmission{request, deadline_ms,
            encoded_bytes}:
          reactor.response.preflight.connection.request(handle, snapshots,
            cursors, id, socket, poll_events, deadline_ms, encoded_bytes,
            seen_cursor_ids, response_bytes, capacity,
            reactor.response.preflight.request(request, response_bytes))
        case _:
          IO.pure(ResponsePreflightConnection,
            ResponsePreflightConnection{handle, snapshots, cursors,
              Connections.Connection{id, socket, poll_events, phase}, None{}})

def reactor.response.preflight.cursor.ids.add(
  new_cursor: Maybe<&2, U32>,
  seen_cursor_ids: List<&2, U32>
) -> List<&2, U32>:
  match new_cursor:
    case None{}: seen_cursor_ids
    case Some{id}: Con{id, seen_cursor_ids}

def reactor.response.preflight.loop(
  fuel: Nat,
  state: ResponsePreflightState
) -> IO(ResponsePreflightResult):
  match fuel:
    case 0n: IO.pure(ResponsePreflightResult,
      PreflightFuelExhausted{state})
    case 1n+rest:
      match state:
        case PreflightScanning{handle, snapshots, cursors, remaining, retained,
            +response_bytes, +capacity, +seen_cursor_ids}:
          match remaining:
            case Nil{}:
              IO.pure(ResponsePreflightResult, PreflightReady{handle,
                snapshots, cursors, retained})
            case Con{connection, tail}:
              do IO<ResponsePreflightResult>:
                measured : ResponsePreflightConnection <-
                  reactor.response.preflight.connection(handle, connection,
                    snapshots, cursors, seen_cursor_ids, response_bytes,
                    capacity)
                reactor.response.preflight.loop(rest,
                  PreflightMeasured{measured, tail, retained,
                    response_bytes, capacity, seen_cursor_ids})
        case PreflightMeasured{result, remaining, retained,
            +response_bytes, +capacity, +seen_cursor_ids}:
          match result:
            case ResponsePreflightConnection{handle, snapshots, cursors,
                connection, new_cursor}:
              reactor.response.preflight.loop(rest,
                PreflightScanning{handle, snapshots, cursors, remaining,
                  Con{connection, retained}, response_bytes, capacity,
                  reactor.response.preflight.cursor.ids.add(new_cursor,
                    seen_cursor_ids)})

def reactor.response.preflight.counted(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  counted: List<&1, Connections.Connection> & Nat,
  +response_bytes: U32
) -> IO(ResponsePreflightResult):
  match counted:
    case (connections, count):
      reactor.response.preflight.loop(Nat.add(Nat.mul(count, 2n), 1n),
        PreflightScanning{handle, snapshots, cursors,
          Connections.reverse.connections(connections, Nil{}), Nil{},
          response_bytes, TxPolicy.tx.capacity(response_bytes), Nil{}})

def reactor.response.preflight(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  response_bytes: U32
) -> IO(ResponsePreflightResult):
  reactor.response.preflight.counted(handle, snapshots, cursors,
    Connections.count.connections(connections), response_bytes)

def reactor.admission.rejected.request(
  +id: U32,
  socket: File,
  request: Protocol.Request,
  status: Protocol.ResponseStatus,
  response_deadline: Nat
) -> Connections.Connection:
  match request:
    case Protocol.Request{version, generation, request_id, _, _}:
      Connections.Connection{id, socket, 4,
        Connections.WritingResponse{
          Protocol.encode_response(Protocol.Response{version, generation,
            request_id, status, Bytes.new(0)}), 0, response_deadline,
          TxPolicy.tx.frame.control(id)}}

def reactor.admission.rejected(
  connection: Connections.Connection,
  reason: QueuePolicy.Rejection,
  response_deadline: Nat
) -> Connections.Connection:
  match connection:
    case Connections.Connection{id, socket, _,
      Connections.AwaitingAdmission{request, _, _}}:
      reactor.admission.rejected.request(id, socket, request,
        ConnectionPolicy.admission.rejection.status(reason), response_deadline)
    case connection: connection

def reactor.admission.evaluate(
  connection: Connections.Connection,
  remaining: List<&1, Connections.Connection>,
  retained: List<&1, Connections.Connection>,
  queue: RequestQueue.Queue,
  sequence_copies: Nat & Nat,
  count_copies: Nat & Nat,
  byte_copies: Nat & Nat,
  response_deadline: Nat,
  +response_bytes: U32
) -> ReactorAdmissionState:
  match sequence_copies:
    case (admit_sequence, retained_sequence):
      match count_copies:
        case (admit_count, retained_count):
          match byte_copies:
            case (admit_bytes, retained_bytes):
              AdmissionEvaluated{
                Connections.admission(connection, queue, admit_sequence,
                  admit_count, admit_bytes, response_bytes),
                remaining, retained, retained_sequence, response_deadline,
                retained_count, retained_bytes, response_bytes}

def reactor.admission.rejected.state(
  connection: Connections.Connection,
  reason: QueuePolicy.Rejection,
  remaining: List<&1, Connections.Connection>,
  retained: List<&1, Connections.Connection>,
  queue: RequestQueue.Queue,
  accepted_sequence: Nat,
  deadlines: Nat & Nat,
  max_count: Nat,
  max_bytes: Nat,
  +response_bytes: U32
) -> ReactorAdmissionState:
  match deadlines:
    case (rejection_deadline, next_deadline):
      AdmissionScanning{remaining,
        Con{reactor.admission.rejected(connection, reason,
          rejection_deadline), retained}, queue, accepted_sequence,
        next_deadline, max_count, max_bytes, response_bytes}

def reactor.admission.loop(
  fuel: Nat,
  state: ReactorAdmissionState
) -> ReactorAdmissionResult:
  match fuel:
    case 0n: AdmissionFuelExhausted{state}
    case 1n+rest:
      match state:
        case AdmissionScanning{remaining, retained, queue,
          accepted_sequence, response_deadline, max_count, max_bytes,
          response_bytes}:
          match remaining:
            case Nil{}:
              AdmissionReady{
                Connections.reverse.connections(retained, Nil{}), queue,
                accepted_sequence}
            case Con{connection, tail}:
              reactor.admission.loop(rest,
                reactor.admission.evaluate(connection, tail, retained, queue,
                  Protocol.nat.duplicate.pair(accepted_sequence),
                  Protocol.nat.duplicate.pair(max_count),
                  Protocol.nat.duplicate.pair(max_bytes), response_deadline,
                  response_bytes))
        case AdmissionEvaluated{result, remaining, retained,
          accepted_sequence, response_deadline, max_count, max_bytes,
          response_bytes}:
          match result:
            case Connections.AdmissionResult{connection, queue, status}:
              match status:
                case Connections.AdmissionQueued{sequence}:
                  reactor.admission.loop(rest,
                    AdmissionScanning{remaining, Con{connection, retained},
                      queue, Nat.add(sequence, 1n), response_deadline,
                      max_count, max_bytes, response_bytes})
                case Connections.AdmissionRejected{reason}:
                  reactor.admission.loop(rest,
                    reactor.admission.rejected.state(connection, reason,
                      remaining, retained, queue, accepted_sequence,
                      Protocol.nat.duplicate.pair(response_deadline),
                      max_count, max_bytes, response_bytes))
                case _:
                  reactor.admission.loop(rest,
                    AdmissionScanning{remaining, Con{connection, retained},
                      queue, accepted_sequence, response_deadline,
                      max_count, max_bytes, response_bytes})

def reactor.admission.start(
  counted: List<&1, Connections.Connection> & Nat,
  queue: RequestQueue.Queue,
  accepted_sequence: Nat,
  response_deadline: Nat,
  max_count: Nat,
  max_bytes: Nat,
  response_bytes: U32
) -> ReactorAdmissionResult:
  match counted:
    case (connections, count):
      reactor.admission.loop(Nat.add(Nat.mul(count, 2n), 1n),
        AdmissionScanning{connections, Nil{}, queue, accepted_sequence,
          response_deadline, max_count, max_bytes, response_bytes})

def reactor.admission.state.connections(
  state: ReactorAdmissionState
) -> List<&1, Connections.Connection>:
  match state:
    case AdmissionScanning{remaining, retained, _, _, _, _, _, _}:
      Connections.append.connections(
        Connections.reverse.connections(retained, Nil{}), remaining)
    case AdmissionEvaluated{result, remaining, retained, _, _, _, _, _}:
      match result:
        case Connections.AdmissionResult{connection, _, _}:
          Connections.append.connections(
            Connections.reverse.connections(retained, Nil{}),
            Con{connection, remaining})

def serve.reactor.admission.exhausted(
  state: ReactorAdmissionState,
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  cursors: CursorStore.Store
) -> IO(ServiceState):
  do IO<ServiceState>:
    _closed : Unit <- close.connections(
      reactor.admission.state.connections(state))
    return Stopping{server, handle, endpoint,
      "owner admission iteration exhausted", cursors}

def serve.reactor.admission.complete(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  now: Nat,
  result: ReactorAdmissionResult
) -> IO(ServiceState):
  match result:
    case AdmissionReady{connections, queue, accepted_sequence}:
      serve.reactor.dispatch.queue.one(server,
        ReactorContext{handle, endpoint, generation, options, snapshots,
          cursors, connections, next_connection_id, accepted_sequence, queue},
        now)
    case AdmissionFuelExhausted{state}:
      do IO<ServiceState>:
        _closed : Unit <- close.connections(
          reactor.admission.state.connections(state))
        return Stopping{server, handle, endpoint,
          "owner admission iteration exhausted", cursors}


def serve.reactor.read.clients.admitted.times(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  times: Nat & Nat,
  cleaned: ReactorCleanupResult
) -> IO(ServiceState):
  match times:
    case (completion_now, deadline_now):
      match cleaned:
        case ReactorCleaned{connections, queue}:
          serve.reactor.admission.complete(server, handle, endpoint,
            generation, options, snapshots, cursors, next_connection_id,
            completion_now,
            reactor.admission.start(
              Connections.count.connections(
                Connections.reverse.connections(connections, Nil{})),
              queue, accepted_sequence,
              Nat.add(deadline_now, Nat.mul(U32.to_nat(
                ResourceOptions.transport.response.timeout(options)),
                1000n)),
              U32.to_nat(ResourceOptions.queue.requests(options)),
              U32.to_nat(ResourceOptions.queue.bytes(options)),
              ResourceOptions.transport.response.bytes(options)))

def serve.reactor.read.clients.admitted(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  +now: Nat,
  cleaned: ReactorCleanupResult
) -> IO(ServiceState):
  serve.reactor.read.clients.admitted.times(server, handle, endpoint,
    generation, options, snapshots, cursors, next_connection_id,
    accepted_sequence, Protocol.nat.duplicate.pair(now), cleaned)

def reactor.response.preflight.state.resources(
  state: ResponsePreflightState
) -> ResponsePreflightResources:
  match state:
    case PreflightScanning{handle, snapshots, cursors, remaining, retained,
        _, _, _}:
      ResponsePreflightResources{handle, snapshots, cursors,
        Connections.append.connections(
          Connections.reverse.connections(remaining, Nil{}), retained)}
    case PreflightMeasured{result, remaining, retained, _, _, _}:
      match result:
        case ResponsePreflightConnection{handle, snapshots, cursors,
            connection, _}:
          ResponsePreflightResources{handle, snapshots, cursors,
            Connections.append.connections(
              Connections.reverse.connections(remaining, Nil{}),
              Con{connection, retained})}

def serve.reactor.read.preflight.exhausted(
  server: File,
  endpoint: String,
  resources: ResponsePreflightResources
) -> IO(ServiceState):
  match resources:
    case ResponsePreflightResources{handle, _, cursors, connections}:
      do IO<ServiceState>:
        _closed : Unit <- close.connections(connections)
        return Stopping{server, handle, endpoint,
          "owner response preflight iteration exhausted", cursors}

def serve.reactor.read.preflighted(
  result: ResponsePreflightResult,
  server: File,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  next_connection_id: U32,
  accepted_sequence: Nat,
  now: Nat,
  queue: RequestQueue.Queue
) -> IO(ServiceState):
  match result:
    case PreflightReady{handle, snapshots, cursors, connections}:
      serve.reactor.read.clients.admitted(server, handle, endpoint,
        generation, options, snapshots, cursors, next_connection_id,
        accepted_sequence, now, ReactorCleaned{connections, queue})
    case PreflightFuelExhausted{state}:
      serve.reactor.read.preflight.exhausted(server, endpoint,
        reactor.response.preflight.state.resources(state))

def serve.reactor.read.preflight.cleanup(
  cleaned: ReactorCleanupResult,
  handle: ByteDb.Handle,
  server: File,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  now: Nat
) -> IO(ServiceState):
  match cleaned:
    case ReactorCleaned{connections, queue}:
      do IO<ServiceState>:
        preflighted : ResponsePreflightResult <-
          reactor.response.preflight(handle, snapshots, cursors, connections,
            ResourceOptions.transport.response.bytes(options))
        serve.reactor.read.preflighted(preflighted, server, endpoint,
          generation, options, next_connection_id,
          accepted_sequence, now, queue)

def serve.reactor.read.completed(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  now: Nat,
  queue: RequestQueue.Queue
) -> IO(ServiceState):
  do IO<ServiceState>:
    cleaned : ReactorCleanupResult <- reactor.cleanup.closed(
      connections, queue)
    serve.reactor.read.preflight.cleanup(cleaned, handle, server,
      endpoint, generation, options, snapshots, cursors, next_connection_id,
      accepted_sequence, now)

def serve.reactor.read.result(
  result: ReactorReadResult,
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  now: Nat,
  queue: RequestQueue.Queue
) -> IO(ServiceState):
  match result:
    case ReadCompleted{connections}:
      serve.reactor.read.completed(server, handle, endpoint, generation,
        options, snapshots, cursors, connections, next_connection_id,
        accepted_sequence, now, queue)
    case ReadFuelExhausted{state}:
      do IO<ServiceState>:
        _closed : Unit <- close.connections(
          reactor.read.state.connections(state))
        return Stopping{server, handle, endpoint,
          "owner read iteration exhausted", cursors}

def serve.reactor.read.clients.timed(
  clock: Result<&1, &1, U32 & String, Nat>,
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  events: List<&2, SocketTypes.ReadyEvent>
) -> IO(ServiceState):
  match clock:
    case Done{+now}:
      do IO<ServiceState>:
        result : ReactorReadResult <-
          serve.reactor.read.start(Connections.receive.metrics(connections),
            events, now,
            U32.to_nat(ResourceOptions.transport.frame.bytes(options)),
            Nat.add(now, Nat.mul(U32.to_nat(
              ResourceOptions.queue.timeout(options)), 1000n)),
            U32.to_nat(ResourceOptions.transport.receive.bytes(options)))
        next : ServiceState <- serve.reactor.read.result(result, server,
          handle, endpoint,
          generation, options, snapshots, cursors, next_connection_id,
          accepted_sequence, now, queue)
        return next
    case Fail{_}:
      IO.pure(ServiceState, ReactorServing{server, handle, endpoint,
        generation, options, snapshots, cursors, connections,
        next_connection_id, accepted_sequence, queue})


def serve.reactor.read.clients(
  state: ServiceState,
  events: List<&2, SocketTypes.ReadyEvent>
) -> IO(ServiceState):
  match state:
    case ReactorServing{server, handle, endpoint, generation, +options,
      snapshots, cursors, connections, next_connection_id,
      accepted_sequence, queue}:
      do IO<ServiceState>:
        clock : Result<&1, &1, U32 & String, Nat> <- Fs.clock_monotonic()
        serve.reactor.read.clients.timed(clock, server, handle, endpoint,
          generation, options, snapshots, cursors, connections,
          next_connection_id, accepted_sequence, queue, events)
    case _: IO.pure(ServiceState, state)

def serve.stop.result(
  removed: Result<&1, &1, U32 & String, Unit>,
  closed: Result<&1, &1, ByteDb.Error, Unit>,
  reason: String
) -> IO(Unit):
  match removed closed reason:
    case Done{Unit{}} Done{Unit{}} "owner request budget exhausted":
      IO.print("OWNER_STOPPED")
    case Done{Unit{}} Done{Unit{}} _:
      IO.die(Unit, 1, reason)
    case Fail{(code, message)} Done{Unit{}} _:
      IO.die(Unit, code, "owner endpoint removal failed: " ++ message)
    case Done{Unit{}} Fail{_} _:
      IO.die(Unit, 1, "owner database lock release failed")
    case Fail{(code, message)} Fail{_} _:
      IO.die(Unit, code, "owner endpoint removal failed: " ++ message)

def serve.stop(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  reason: String,
  cursors: CursorStore.Store
) -> IO(Unit):
  do IO<Unit>:
    _cursors_closed : Unit <- CursorStore.close.all(cursors)
    _server_closed : Unit <- File.close(server)
    removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
    closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    serve.stop.result(removed, closed, reason)

def reactor.context(state: ServiceState) -> Maybe<&1, ReactorContext>:
  match state:
    case ReactorServing{_, handle, endpoint, generation, options,
      snapshots, cursors, connections, next_connection_id,
      accepted_sequence, queue}:
      Some{ReactorContext{handle, endpoint, generation, options, snapshots,
        cursors, connections, next_connection_id, accepted_sequence, queue}}
    case _: None{}

def serve.reactor.insert.result(
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  +next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  inserted: Connections.InsertResult
) -> IO(ReactorContext):
  match inserted:
    case Connections.Inserted{next_connections}:
      do IO<ReactorContext>:
        _observed : Unit <- Observation.opened(next_connection_id,
          ResourceOptions.transport.connections(options),
          TxPolicy.tx.capacity(ResourceOptions.transport.response.bytes(options)))
        return ReactorContext{handle, endpoint, generation, options, snapshots,
          cursors, next_connections, U32.add(next_connection_id, 1),
          accepted_sequence, queue}
    case Connections.Full{next_connections, rejected}:
      match rejected:
        case Connections.Connection{_, rejected_socket, _, _}:
          do IO<ReactorContext>:
            _closed : Unit <- File.close(rejected_socket)
            return ReactorContext{handle, endpoint, generation,
              options, snapshots, cursors, next_connections,
              next_connection_id, accepted_sequence, queue}

def serve.reactor.inserted(
  context: ReactorContext,
  connection: Connections.Connection
) -> IO(ReactorContext):
  match context:
    case ReactorContext{handle, endpoint, generation, +options, snapshots,
      cursors, connections, +next_id, accepted_sequence, queue}:
      serve.reactor.insert.result(
        handle, endpoint, generation, options, snapshots, cursors, next_id,
        accepted_sequence, queue,
        Connections.insert(connections, connection,
          U32.to_nat(ResourceOptions.transport.connections(options))))

def serve.reactor.accept.id.decision(
  context: ReactorContext,
  socket: File,
  now: Nat,
  decision: ConnectionPolicy.ConnectionIdDecision
) -> IO(ReactorContext):
  match context:
    case ReactorContext{handle, endpoint, generation, +options,
      snapshots, cursors, connections, +next_id, accepted_sequence, queue}:
      match decision:
        case ConnectionPolicy.IdAvailable{}:
          serve.reactor.inserted(
            ReactorContext{handle, endpoint, generation, options,
              snapshots, cursors, connections, next_id, accepted_sequence,
              queue},
            Connections.open(next_id, socket,
              Nat.add(now, Nat.mul(U32.to_nat(
                ResourceOptions.transport.frame.timeout(options)),
                1000n))))
        case ConnectionPolicy.IdExhausted{}:
          do IO<ReactorContext>:
            _closed : Unit <- File.close(socket)
            return ReactorContext{handle, endpoint, generation, options,
              snapshots, cursors, connections, next_id, accepted_sequence,
              queue}

def serve.reactor.accept.clock(
  context: ReactorContext,
  socket: File,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(ReactorContext):
  match context:
    case ReactorContext{handle, endpoint, generation, +options, snapshots,
      cursors, connections, +next_id, accepted_sequence, queue}:
      match result:
        case Done{now}:
          serve.reactor.accept.id.decision(
            ReactorContext{handle, endpoint, generation, options,
              snapshots, cursors, connections, next_id,
              accepted_sequence, queue},
            socket, now, ConnectionPolicy.connection.id(next_id))
        case Fail{_}:
          do IO<ReactorContext>:
            _closed : Unit <- File.close(socket)
            return ReactorContext{handle, endpoint, generation, options,
              snapshots, cursors, connections, next_id, accepted_sequence,
              queue}

def serve.reactor.accept.mode(
  context: ReactorContext,
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(ReactorContext):
  match pair:
    case (socket, Done{Unit{}}):
      do IO<ReactorContext>:
        clock : Result<&1, &1, U32 & String, Nat> <- Fs.clock_monotonic()
        serve.reactor.accept.clock(context, socket, clock)
    case (socket, Fail{_}):
      do IO<ReactorContext>:
        _closed : Unit <- File.close(socket)
        return context

def serve.reactor.accept.client(
  context: ReactorContext,
  server: File,
  connection: File
) -> IO(File & ReactorContext):
  do IO<File & ReactorContext>:
    nonblocking : File & Result<&1, &1, UnixSocket.Error, Unit> <-
      UnixSocket.nonblocking(connection)
    next_context : ReactorContext <-
      serve.reactor.accept.mode(context, nonblocking)
    return (server, next_context)

def serve.reactor.accept(
  context: ReactorContext,
  pair: File & Result<&1, &1, UnixSocket.Error, File>
) -> IO(File & ReactorContext):
  match pair:
    case (server, Done{connection}):
      serve.reactor.accept.client(context, server, connection)
    case (server, Fail{_}):
      IO.pure(File & ReactorContext, (server, context))

def serve.reactor.accept.batch.done(
  pair: File & ReactorContext
) -> IO(File & ReactorContext):
  match pair:
    case (server, context):
      IO.pure(File & ReactorContext, (server, context))

def serve.reactor.accept.batch(
  fuel: Nat,
  state: ReactorAcceptState
) -> IO(File & ReactorContext):
  match fuel:
    case 0n:
      match state:
        case AcceptPolling{server, context}:
          IO.pure(File & ReactorContext, (server, context))
        case AcceptObserved{context, pair}:
          match pair:
            case (server, Done{connection}):
              do IO<File & ReactorContext>:
                installed : File & ReactorContext <-
                  serve.reactor.accept.client(context, server, connection)
                serve.reactor.accept.batch.done(installed)
            case (server, Fail{_}):
              IO.pure(File & ReactorContext, (server, context))
        case AcceptInstalled{pair}:
          match pair:
            case (server, context):
              IO.pure(File & ReactorContext, (server, context))
    case 1n+rest:
      match state:
        case AcceptPolling{server, context}:
          do IO<File & ReactorContext>:
            attempt : File & Result<&1, &1, UnixSocket.Error, File> <-
              UnixSocket.accept(server)
            serve.reactor.accept.batch(rest,
              AcceptObserved{context, attempt})
        case AcceptObserved{context, pair}:
          match pair:
            case (server, Done{connection}):
              do IO<File & ReactorContext>:
                installed : File & ReactorContext <-
                  serve.reactor.accept.client(context, server, connection)
                serve.reactor.accept.batch(rest,
                  AcceptInstalled{installed})
            case (server, Fail{UnixSocket.Transient{code}}):
              match code:
                case 4:
                  serve.reactor.accept.batch(rest,
                    AcceptPolling{server, context})
                case _: IO.pure(File & ReactorContext, (server, context))
            case (server, Fail{_}):
              IO.pure(File & ReactorContext, (server, context))
        case AcceptInstalled{pair}:
          match pair:
            case (server, context):
              serve.reactor.accept.batch(rest,
                AcceptPolling{server, context})

def reactor.poll.timeout.interests.loop(
  remaining: List<SocketTypes.PollInterest>,
  retained: List<SocketTypes.PollInterest>,
  has_connections: Bool,
  queue_active: Bool
) -> PollTimeoutInput:
  match remaining:
    case Nil{}:
      PollTimeoutInput{List.reverse(&1, SocketTypes.PollInterest, retained),
        has_connections, queue_active}
    case Con{interest, rest}:
      reactor.poll.timeout.interests.loop(rest, Con{interest, retained},
        True{}, queue_active)

def reactor.poll.timeout.interests(
  interests: List<SocketTypes.PollInterest>,
  queue_active: Bool
) -> PollTimeoutInput:
  reactor.poll.timeout.interests.loop(interests, Nil{}, False{}, queue_active)

def reactor.poll.timeout(
  +options: ResourceOptions.Options,
  has_connections: Bool,
  queue_active: Bool
) -> ConnectionPolicy.PollTimeoutInput:
  ConnectionPolicy.PollTimeout{has_connections, queue_active,
    ResourceOptions.transport.frame.timeout(options),
    ResourceOptions.transport.response.timeout(options),
    ResourceOptions.queue.timeout(options)}

def serve.reactor.poll.prepared.interests(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  metadata: List<&1, Connections.Metadata>,
  timeout_input: PollTimeoutInput
) -> ReactorPollPrepared:
  match timeout_input:
    case PollTimeoutInput{client_interests, has_connections, queue_active}:
      ReactorPollPrepared{metadata,
        ReactorContext{handle, endpoint, generation, options, snapshots,
          cursors, Nil{}, next_connection_id, accepted_sequence, queue},
        Con{SocketTypes.PollInterest{0, server, 1}, client_interests},
        ConnectionPolicy.poll.timeout(reactor.poll.timeout(options,
          has_connections, queue_active))}

def serve.reactor.poll.prepared.queue.active.split(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  queue_active: Bool,
  split: Connections.Split
) -> ReactorPollPrepared:
  match split:
    case Connections.Split{metadata, interests}:
      serve.reactor.poll.prepared.interests(server, handle, endpoint,
        generation, options, snapshots, cursors, next_connection_id,
        accepted_sequence, queue, metadata,
        reactor.poll.timeout.interests(interests, queue_active))

def serve.reactor.poll.prepared.queue.active(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  _queue: RequestQueue.Queue,
  split: Connections.Split,
  active_pair: RequestQueue.Queue & Bool
) -> ReactorPollPrepared:
  match active_pair:
    case (restored_queue, queue_active):
      serve.reactor.poll.prepared.queue.active.split(server, handle,
        endpoint, generation, options, snapshots, cursors,
        next_connection_id, accepted_sequence, restored_queue, queue_active,
        split)
def serve.reactor.poll.prepared.with.queue(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  split: Connections.Split,
  active_pair: RequestQueue.Queue & Bool
) -> ReactorPollPrepared:
  match active_pair:
    case (queue, queue_active):
      serve.reactor.poll.prepared.queue.active.split(server, handle,
        endpoint, generation, options, snapshots, cursors,
        next_connection_id, accepted_sequence, queue, queue_active, split)

def serve.reactor.poll.prepared(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  +options: ResourceOptions.Options,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue,
  split: Connections.Split
) -> ReactorPollPrepared:
  serve.reactor.poll.prepared.with.queue(server, handle, endpoint,
    generation, options, snapshots, cursors, next_connection_id,
    accepted_sequence, split, RequestQueue.active(queue))
def serve.reactor.poll.accepted(
  pair: File & ReactorContext,
  events: List<&2, SocketTypes.ReadyEvent>
) -> IO(ServiceState):
  match pair:
    case (server, context):
      serve.reactor.read.clients(reactor.state(server, context), events)

def serve.reactor.poll.listener(
  server: File,
  context: ReactorContext,
  readiness: Connections.EventReadiness,
  events: List<&2, SocketTypes.ReadyEvent>
) -> IO(ServiceState):
  match context:
    case ReactorContext{handle, endpoint, generation, +options, snapshots,
      cursors, connections, next_connection_id, accepted_sequence, queue}:
      match readiness:
        case Connections.EventReady{_}:
          do IO<ServiceState>:
            accepted : File & ReactorContext <-
              serve.reactor.accept.batch(
                U32.to_nat(ResourceOptions.transport.connections(options)),
                AcceptPolling{server, ReactorContext{handle, endpoint,
                  generation, options, snapshots, cursors, connections,
                  next_connection_id, accepted_sequence, queue}})
            serve.reactor.poll.accepted(accepted, events)
        case Connections.EventNotReady{}:
          serve.reactor.read.clients(reactor.state(server,
            ReactorContext{handle, endpoint, generation, options, snapshots,
              cursors, connections, next_connection_id, accepted_sequence,
              queue}), events)

def serve.reactor.poll.restored.ids(
  context: ReactorContext,
  server: File,
  +events: List<&2, SocketTypes.ReadyEvent>,
  connections: List<&1, Connections.Connection>,
  ids_valid: Bool,
  event_validation: Connections.EventValidation
) -> IO(ServiceState):
  match context:
    case ReactorContext{handle, endpoint, generation, options, snapshots,
      cursors, _, next_connection_id, accepted_sequence, queue}:
      match ids_valid:
        case True{}:
          match event_validation:
            case Connections.EventsValid{}:
              serve.reactor.poll.listener(server,
                ReactorContext{handle, endpoint, generation, options,
                  snapshots, cursors, connections, next_connection_id,
                  accepted_sequence, queue},
                Connections.event.find(0, events), events)
            case Connections.EventUnknown{_}:
              do IO<ServiceState>:
                _closed : Unit <- close.connections(connections)
                return Stopping{server, handle, endpoint,
                  "socket poll returned an unknown connection ID", cursors}
            case Connections.EventDuplicate{_}:
              do IO<ServiceState>:
                _closed : Unit <- close.connections(connections)
                return Stopping{server, handle, endpoint,
                  "socket poll returned a duplicate connection ID", cursors}
        case False{}:
          do IO<ServiceState>:
            _closed : Unit <- close.connections(connections)
            return Stopping{server, handle, endpoint,
              "socket poll interest ID mismatch", cursors}

def serve.reactor.poll.restored(
  decision: Connections.RestoreDecision,
  context: ReactorContext,
  server: File,
  +events: List<&2, SocketTypes.ReadyEvent>,
  event_validation: Connections.EventValidation
) -> IO(ServiceState):
  match decision:
    case Connections.Restored{connections, ids_valid}:
      serve.reactor.poll.restored.ids(context, server, events, connections,
        ids_valid, event_validation)
    case Connections.InvalidLengths{_, _}:
      match context:
        case ReactorContext{handle, endpoint, _, _, _, cursors, _, _, _, _}:
          IO.pure(ServiceState, Stopping{server, handle, endpoint,
            "socket poll interest restoration failed", cursors})

def serve.reactor.poll.done.ids(
  context: ReactorContext,
  +events: List<&2, SocketTypes.ReadyEvent>,
  server: File & List<SocketTypes.PollInterest>,
  indexed: Connections.MetadataIds
) -> IO(ServiceState):
  match server:
    case (socket, clients):
      match indexed:
        case Connections.MetadataListed{restored_metadata, ids}:
          do IO<ServiceState>:
            validation : Connections.EventValidation <- IO.pure(
              Connections.EventValidation,
              Connections.events.validate(events, Con{0, ids}))
            restored : Connections.RestoreDecision <- IO.pure(
              Connections.RestoreDecision,
              Connections.restore(restored_metadata, clients))
            state : ServiceState <- serve.reactor.poll.restored(restored,
              context, socket, events, validation)
            return state

def serve.reactor.poll.done(
  interests: List<SocketTypes.PollInterest>,
  metadata: List<&1, Connections.Metadata>,
  context: ReactorContext,
  events: List<&2, SocketTypes.ReadyEvent>
) -> IO(ServiceState):
  match interests:
    case Con{listener, clients}:
      match listener:
        case SocketTypes.PollInterest{_, server, _}:
          serve.reactor.poll.done.ids(context, events, (server, clients),
            Connections.metadata.ids(metadata))
    case Nil{}:
      IO.die(ServiceState, 1, "socket poll returned an empty interest set")

def serve.reactor.poll.failed(
  interests: List<SocketTypes.PollInterest>,
  context: ReactorContext
) -> IO(ServiceState):
  match interests:
    case Con{listener, clients}:
      match listener:
        case SocketTypes.PollInterest{_, server, _}:
          match context:
            case ReactorContext{handle, endpoint, _, _, _, cursors,
              _, _, _, _}:
              do IO<ServiceState>:
                _closed : Unit <- close.poll.interests(clients)
                return Stopping{server, handle, endpoint,
                  "socket poll failed", cursors}
    case Nil{}:
      IO.die(ServiceState, 1, "socket poll failed without an interest set")

def serve.reactor.poll.error.result(
  interests: List<SocketTypes.PollInterest>,
  metadata: List<&1, Connections.Metadata>,
  context: ReactorContext,
  retryable: Bool
) -> IO(ServiceState):
  match retryable:
    case True{}:
      serve.reactor.poll.done(interests, metadata, context, Nil{})
    case False{}:
      serve.reactor.poll.failed(interests, context)

def serve.reactor.poll.error(
  interests: List<SocketTypes.PollInterest>,
  metadata: List<&1, Connections.Metadata>,
  context: ReactorContext,
  error: UnixSocket.Error
) -> IO(ServiceState):
  serve.reactor.poll.error.result(interests, metadata, context,
    UnixSocket.poll.error.retryable(error))

def serve.reactor.poll.interests(
  metadata: List<&1, Connections.Metadata>,
  context: ReactorContext,
  pair:
    List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>
) -> IO(ServiceState):
  match pair:
    case (interests, Done{events}):
      serve.reactor.poll.done(interests, metadata, context, events)
    case (interests, Fail{error}):
      serve.reactor.poll.error(interests, metadata, context, error)

def serve.reactor.poll.result(
  metadata: List<&1, Connections.Metadata>,
  context: ReactorContext,
  pair:
    List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>
) -> IO(ServiceState):
  serve.reactor.poll.interests(metadata, context, pair)

def serve.reactor.poll.wait(prepared: ReactorPollPrepared) -> IO(ServiceState):
  match prepared:
    case ReactorPollPrepared{metadata, context, interests, timeout_ms}:
      do IO<ServiceState>:
        pair : List<SocketTypes.PollInterest> &
          Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>> <-
            UnixSocket.poll_many(interests, timeout_ms)
        serve.reactor.poll.result(metadata, context, pair)

def serve.reactor.wait(state: ServiceState) -> IO(ServiceState):
  match state:
    case ReactorServing{server, handle, endpoint, generation, +options,
      snapshots, cursors, connections, next_connection_id,
      accepted_sequence, queue}:
      serve.reactor.poll.wait(serve.reactor.poll.prepared(server, handle,
        endpoint, generation, options, snapshots, cursors,
        next_connection_id, accepted_sequence, queue,
        Connections.split(connections)))
    case _: IO.pure(ServiceState, state)

def serve.reactor.carry(
  next: ServiceState,
  connections: List<&1, Connections.Connection>,
  next_connection_id: U32,
  accepted_sequence: Nat,
  queue: RequestQueue.Queue
) -> ServiceState:
  match next:
    case Serving{server, handle, endpoint, generation, options,
      snapshots, cursors}:
      ReactorServing{server, handle, endpoint, generation, options,
        snapshots, cursors, connections, next_connection_id,
        accepted_sequence, queue}
    case Stopping{server, handle, endpoint, reason, cursors}:
      Stopping{server, handle, endpoint, reason, cursors}
    case state: state

def reactor.observe.measured(
  server: File,
  context: ReactorContext,
  metrics: Connections.TransmitCount
) -> ServiceState:
  match context metrics:
    case ReactorContext{handle, endpoint, generation, options,
      snapshots, cursors, _, next_id, sequence, queue}
      Connections.TransmitCount{connections, _, _, _, _, _}:
      ReactorServing{server, handle, endpoint, generation, options,
        snapshots, cursors, connections, next_id, sequence, queue}

# Exposes fixed slots and TX occupancy before polling, independently of dispatch.
def reactor.observe.active(state: ServiceState) -> IO(ServiceState):
  match state:
    case ReactorServing{server, handle, endpoint, generation, options,
        snapshots, cursors, connections, next_id, sequence, queue}:
      do IO<ServiceState>:
        metrics : Connections.TransmitCount <- Observation.census(
          Connections.transmit.metrics(connections))
        return reactor.observe.measured(server,
          ReactorContext{handle, endpoint, generation, options,
            snapshots, cursors, Nil{}, next_id, sequence, queue}, metrics)
    case other: IO.pure(ServiceState, other)

def reactor.observe.enabled(state: ServiceState, active: Bool) -> IO(ServiceState):
  match active:
    case False{}: IO.pure(ServiceState, state)
    case True{}: reactor.observe.active(state)

# Avoids the extra connection census when fixture observation is disabled.
def reactor.observe.state(state: ServiceState) -> IO(ServiceState):
  do IO<ServiceState>:
    active : Bool <- Observation.enabled()
    reactor.observe.enabled(state, active)

def serve.loop(fuel: Nat, state: ServiceState) -> IO(Unit):
  match fuel:
    case 0n:
      match state:
        case Serving{server, handle, endpoint, _, _, _, cursors}:
          serve.stop(server, handle, endpoint,
            "owner request budget exhausted", cursors)
        case ReactorServing{server, handle, endpoint, _, _, _, cursors,
          connections, _, _, _}:
          do IO<Unit>:
            _connections_closed : Unit <- close.connections(connections)
            serve.stop(server, handle, endpoint,
              "owner request budget exhausted", cursors)
        case Stopping{server, handle, endpoint, reason, cursors}:
          serve.stop(server, handle, endpoint, reason, cursors)
    case 1n+rest:
      match state:
        case Serving{server, handle, endpoint, generation, options,
          snapshots, cursors}:
          do IO<Unit>:
            context : ServiceState = ReactorServing{server, handle, endpoint,
              generation, options, snapshots, cursors, Nil{}, 0, 0n,
              RequestQueue.empty()}
            next : ServiceState <- serve.reactor.wait(context)
            serve.loop(rest, next)
        case ReactorServing{_, _, _, _, _, _, _, _, _, _, _}:
          do IO<Unit>:
            observed : ServiceState <- reactor.observe.state(state)
            next : ServiceState <- serve.reactor.wait(observed)
            serve.loop(rest, next)
        case Stopping{server, handle, endpoint, reason, cursors}:
          serve.stop(server, handle, endpoint, reason, cursors)
