import Base
import ./ConnectionPolicy.bend as ConnectionPolicy
import ./Protocol.bend as Protocol
import ./RequestQueue.bend as Queue
import ./QueuePolicy.bend as QueuePolicy
import ./TransportBudgetPolicy.bend as TxPolicy
import ./UnixSocketTypes.bend as SocketTypes
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries the state for Phase.
type Phase is Type:
  ReadingHeader{chunks: List<&1, Bytes.Bytes>, received_bytes: U32,
    deadline_ms: Nat}
  ReadingPayload{header: Bytes.Bytes, chunks: List<&1, Bytes.Bytes>,
    expected_bytes: U32, received_bytes: U32, deadline_ms: Nat}
  AwaitingAdmission{request: Protocol.Request, deadline_ms: Nat,
    encoded_bytes: Nat}
  BoundedAdmission{request: Protocol.Request, deadline_ms: Nat,
    encoded_bytes: Nat, bound: TxPolicy.BoundDecision}
  WaitingAdmission{pending: Queue.Pending}
  Queued{accepted_sequence: Nat, bound: TxPolicy.BoundDecision}
  InFlight{request_id: U32}
  WritingResponse{encoded: Bytes.Bytes, written_bytes: U32,
    deadline_ms: Nat, reservation: TxPolicy.FrameReservation}
  Closing{}

# Carries the state for Connection.
type Connection is Type:
  Connection{id: U32, socket: File, poll_events: U32, phase: Phase}

# Carries the state for InsertResult.
type InsertResult is Type:
  Inserted{connections: List<&1, Connection>}
  Full{connections: List<&1, Connection>, rejected: Connection}

# Carries the state for ConnectionCount.
type ConnectionCount is Type:
  ConnectionCount{connections: List<&1, Connection>, count: Nat}

# Carries the state for ReceiveCount.
type ReceiveCount is Type:
  ReceiveCount{connections: List<&1, Connection>, bytes: Nat, count: Nat}

# Carries the state for ReceiveLoopState.
type ReceiveLoopState is Type:
  ReceiveScanning{remaining: List<&1, Connection>,
    retained: List<&1, Connection>, total: Nat, count: Nat}
  ReceiveMeasured{remaining: List<&1, Connection>,
    retained: List<&1, Connection>, total: Nat, count: Nat,
    processed: Connection & Nat}

# Carries the state for TransmitCount.
type TransmitCount is Type:
  TransmitCount{connections: List<&1, Connection>, bytes: Nat, count: Nat,
    live_bytes: Nat, control_bytes: Nat, header_bytes: Nat}

# Carries the state for DetachSearch.
type DetachSearch is Type:
  DetachScanning{remaining: List<&1, Connection>,
    retained: List<&1, Connection>, targets: U32 & U32 & U32}
  DetachCompared{pair: Connection & Bool,
    remaining: List<&1, Connection>, retained: List<&1, Connection>,
    targets: U32 & U32 & U32}

# Carries the state for DetachResult.
type DetachResult is Type:
  Detached{connections: List<&1, Connection>, connection: Connection}
  DetachNotFound{connections: List<&1, Connection>}
  DetachExhausted{state: DetachSearch}

# Carries the state for Metadata.
type Metadata is Type:
  Metadata{id: U32, poll_events: U32, phase: Phase}

# Carries the state for Split.
type Split is Type:
  Split{metadata: List<&1, Metadata>,
    interests: List<SocketTypes.PollInterest>}

# Carries the state for RestoreDecision.
type RestoreDecision is Type:
  Restored{connections: List<&1, Connection>, ids_valid: Bool}
  InvalidLengths{metadata: List<&1, Metadata>,
    interests: List<SocketTypes.PollInterest>}

# Carries the state for HeaderStatus.
type HeaderStatus is Data:
  HeaderNotReading{}
  HeaderWaiting{}
  HeaderPayload{expected_payload_bytes: U32}
  HeaderRejected{decision: Protocol.HeaderDecision}

# Carries the state for PayloadStatus.
type PayloadStatus is Type:
  PayloadNotReading{}
  PayloadWaiting{}
  PayloadReady{}
  PayloadRejected{decision: Protocol.FrameDecision}

# Carries the state for AdmissionStatus.
type AdmissionStatus is Type:
  AdmissionNotReady{}
  AdmissionQueued{accepted_sequence: Nat}
  AdmissionRejected{reason: QueuePolicy.Rejection}

# Carries the state for AdmissionResult.
type AdmissionResult is Type:
  AdmissionResult{connection: Connection, queue: Queue.Queue,
    status: AdmissionStatus}

def response.pending(
  connection: Connection,
  encoded: Bytes.Bytes,
  deadline_ms: Nat
) -> Connection:
  match connection:
    case Connection{+id, socket, _, _}:
      Connection{id, socket, 4,
        WritingResponse{encoded, 0, deadline_ms, TxPolicy.tx.frame.control(id)}}

def queued.bound.selected.true(
  connection: Connection,
  bound: TxPolicy.BoundDecision
) -> Connection:
  match connection:
    case Connection{id, socket, poll_events, Queued{sequence, _}}:
      Connection{id, socket, poll_events, Queued{sequence, bound}}
    case connection: connection

def queued.bound.selected(
  connection: Connection,
  bound: TxPolicy.BoundDecision,
  selected: Bool
) -> Connection:
  match selected:
    case False{}: connection
    case True{}: queued.bound.selected.true(connection, bound)

def queued.bound.connection(
  connection: Connection,
  target_id: U32,
  bound: TxPolicy.BoundDecision
) -> Connection:
  match connection:
    case Connection{+id, socket, poll_events, phase}:
      queued.bound.selected(Connection{id, socket, poll_events, phase},
        bound, U32.is_eq(id, target_id))

def queued.bound.connections(
  connections: List<&1, Connection>,
  +target_id: U32,
  +bound: TxPolicy.BoundDecision
) -> List<&1, Connection>:
  match connections:
    case Nil{}: Nil{}
    case Con{connection, rest}:
      Con{queued.bound.connection(connection, target_id, bound),
        queued.bound.connections(rest, target_id, bound)}

def u32.duplicate.pair(+value: U32) -> U32 & U32:
  (value, value)

# Carries the state for EventReadiness.
type EventReadiness is Data:
  EventNotReady{}
  EventReady{flags: U32}

# Carries the state for EventValidation.
type EventValidation is Data:
  EventsValid{}
  EventUnknown{connection_id: U32}
  EventDuplicate{connection_id: U32}

# Carries the state for EventIdSearch.
type EventIdSearch is Type:
  EventIdSearching{remaining: List<&2, U32>, query_id: U32}
  EventIdFound{}
  EventIdMissing{}

# Carries the state for EventValidationState.
type EventValidationState is Type:
  EventValidationScanning{remaining: List<&2, SocketTypes.ReadyEvent>,
    ids: List<&2, U32>, seen: List<&2, U32>}
  EventValidationKnown{search: EventIdSearch, connection_id: U32,
    remaining: List<&2, SocketTypes.ReadyEvent>, ids: List<&2, U32>,
    seen: List<&2, U32>}
  EventValidationCheckingDuplicate{connection_id: U32,
    remaining: List<&2, SocketTypes.ReadyEvent>, ids: List<&2, U32>,
    seen: List<&2, U32>}
  EventValidationDuplicateChecked{search: EventIdSearch,
    connection_id: U32, remaining: List<&2, SocketTypes.ReadyEvent>,
    ids: List<&2, U32>, seen: List<&2, U32>}

def events.validate.added(
  copies: U32 & U32 & U32,
  remaining: List<&2, SocketTypes.ReadyEvent>,
  ids: List<&2, U32>,
  seen: List<&2, U32>
) -> EventValidationState:
  match copies:
    case (_, (_, seen_id)):
      EventValidationScanning{remaining, ids, Con{seen_id, seen}}

# Carries the state for MetadataIds.
type MetadataIds is Type:
  MetadataListed{metadata: List<&1, Metadata>, ids: List<&2, U32>}

# Carries the state for MetadataIdsState.
type MetadataIdsState is Type:
  MetadataIdsScanning{remaining: List<&1, Metadata>,
    retained: List<&1, Metadata>, ids: List<&2, U32>}

# Carries the state for MetadataCount.
type MetadataCount is Type:
  MetadataCount{metadata: List<&1, Metadata>, count: Nat}

def event.id.search.compared(
  copies: U32 & U32 & U32,
  matches: Bool,
  rest: List<&2, U32>
) -> EventIdSearch:
  match copies:
    case (_, (recur, _)):
      match matches:
        case True{}: EventIdFound{}
        case False{}: EventIdSearching{rest, recur}

def event.id.search.checked(
  copies: U32 & U32 & U32,
  candidate: U32,
  rest: List<&2, U32>
) -> EventIdSearch:
  match copies:
    case (checked, (recur, _)):
      event.id.search.compared(Protocol.u32.duplicate.triple(recur),
        U32.is_eq(checked, candidate), rest)

def event.id.search.loop(fuel: Nat, state: EventIdSearch) -> EventIdSearch:
  match fuel:
    case 0n: state
    case 1n+rest_fuel:
      match state:
        case EventIdFound{}: state
        case EventIdMissing{}: state
        case EventIdSearching{remaining, query_id}:
          match remaining:
            case Nil{}: EventIdMissing{}
            case Con{candidate, tail}:
              event.id.search.loop(rest_fuel,
                event.id.search.checked(Protocol.u32.duplicate.triple(
                  query_id), candidate, tail))

def event.id.search(+ids: List<&2, U32>, query_id: U32) -> EventIdSearch:
  event.id.search.loop(Nat.add(List.length(&2, U32, ids), 1n),
    EventIdSearching{ids, query_id})

def events.validate.known.begin(
  copies: U32 & U32 & U32,
  remaining: List<&2, SocketTypes.ReadyEvent>,
  +ids: List<&2, U32>,
  seen: List<&2, U32>
) -> EventValidationState:
  match copies:
    case (query_id, (connection_id, _)):
      EventValidationKnown{event.id.search(ids, query_id), connection_id,
        remaining, ids, seen}

def events.validate.duplicate.begin(
  copies: U32 & U32 & U32,
  remaining: List<&2, SocketTypes.ReadyEvent>,
  ids: List<&2, U32>,
  +seen: List<&2, U32>
) -> EventValidationState:
  match copies:
    case (query_id, (connection_id, _)):
      EventValidationDuplicateChecked{event.id.search(seen, query_id),
        connection_id, remaining, ids, seen}

def events.validate.loop(fuel: Nat, state: EventValidationState) -> EventValidation:
  match fuel:
    case 0n: EventsValid{}
    case 1n+rest_fuel:
      match state:
        case EventValidationScanning{remaining, +ids, seen}:
          match remaining:
            case Nil{}: EventsValid{}
            case Con{event, tail}:
              match event:
                case SocketTypes.ReadyEvent{connection_id, _}:
                  events.validate.loop(rest_fuel,
                    events.validate.known.begin(
                      Protocol.u32.duplicate.triple(connection_id), tail,
                      ids, seen))
        case EventValidationKnown{search, connection_id, remaining, ids,
            seen}:
          match search:
            case EventIdMissing{}: EventUnknown{connection_id}
            case EventIdFound{}:
              events.validate.loop(rest_fuel,
                EventValidationCheckingDuplicate{connection_id, remaining,
                  ids, seen})
            case _: EventUnknown{connection_id}
        case EventValidationCheckingDuplicate{connection_id, remaining,
            ids, +seen}:
          events.validate.loop(rest_fuel,
            events.validate.duplicate.begin(
              Protocol.u32.duplicate.triple(connection_id), remaining, ids,
              seen))
        case EventValidationDuplicateChecked{search, connection_id,
            remaining, ids, seen}:
          match search:
            case EventIdFound{}: EventDuplicate{connection_id}
            case EventIdMissing{}:
              events.validate.loop(rest_fuel,
                events.validate.added(
                  Protocol.u32.duplicate.triple(connection_id), remaining,
                  ids, seen))
            case _: EventDuplicate{connection_id}
        case _: EventsValid{}

def event.count.keep.go(
  remaining: List<&2, SocketTypes.ReadyEvent>,
  reversed: List<&2, SocketTypes.ReadyEvent>,
  count: Nat
) -> List<&2, SocketTypes.ReadyEvent> & Nat:
  match remaining:
    case Nil{}: (List.reverse(&2, SocketTypes.ReadyEvent, reversed), count)
    case Con{event, tail}:
      event.count.keep.go(tail, Con{event, reversed}, Nat.add(count, 1n))

def event.count.keep(
  events: List<&2, SocketTypes.ReadyEvent>
) -> List<&2, SocketTypes.ReadyEvent> & Nat:
  event.count.keep.go(events, Nil{}, 0n)

def events.validate.counted(
  counted: List<&2, SocketTypes.ReadyEvent> & Nat,
  ids: List<&2, U32>
) -> EventValidation:
  match counted:
    case (events, count):
      events.validate.loop(Nat.add(Nat.mul(count, 4n), 1n),
        EventValidationScanning{events, ids, Nil{}})

def events.validate(
  events: List<&2, SocketTypes.ReadyEvent>,
  +ids: List<&2, U32>
) -> EventValidation:
  events.validate.counted(event.count.keep(events), ids)

# Carries the state for EventSearch.
type EventSearch is Type:
  EventScanning{remaining: List<&2, SocketTypes.ReadyEvent>,
    target: U32 & U32 & U32}
  EventCompared{matches: Bool, flags: U32,
    remaining: List<&2, SocketTypes.ReadyEvent>,
    target: U32 & U32 & U32}

def event.find.loop(
  fuel: Nat,
  state: EventSearch
) -> EventReadiness:
  match fuel:
    case 0n: EventNotReady{}
    case 1n+rest_fuel:
      match state:
        case EventScanning{remaining, target}:
          match remaining:
            case Nil{}: EventNotReady{}
            case Con{event, tail}:
              match event:
                case SocketTypes.ReadyEvent{event_id, flags}:
                  match target:
                    case (checked, (recurse, _)):
                      event.find.loop(rest_fuel,
                        EventCompared{U32.is_eq(checked, event_id), flags,
                          tail, Protocol.u32.duplicate.triple(recurse)})
        case EventCompared{decision, flags, remaining, target}:
          match decision:
            case True{}: EventReady{flags}
            case False{}:
              event.find.loop(rest_fuel,
                EventScanning{remaining, target})

def event.find.counted(
  id: U32,
  counted: List<&2, SocketTypes.ReadyEvent> & Nat
) -> EventReadiness:
  match counted:
    case (events, count):
      event.find.loop(Nat.add(Nat.mul(count, 2n), 1n),
        EventScanning{events, Protocol.u32.duplicate.triple(id)})

def event.find(
  id: U32,
  events: List<&2, SocketTypes.ReadyEvent>
) -> EventReadiness:
  event.find.counted(id, event.count.keep(events))

# Handles open.
def open(id: U32, socket: File, deadline_ms: Nat) -> Connection:
  Connection{id, socket, 1, ReadingHeader{Nil{}, 0, deadline_ms}}

def insert.decided(
  existing: List<&1, Connection>,
  connection: Connection,
  capacity: ConnectionPolicy.CapacityDecision
) -> InsertResult:
  match capacity:
    case ConnectionPolicy.Available{}:
      Inserted{Con{connection, existing}}
    case ConnectionPolicy.Full{}: Full{existing, connection}

def reverse.metadata(remaining: List<&1, Metadata>,
  output: List<&1, Metadata>) -> List<&1, Metadata>:
  match remaining:
    case Nil{}: output
    case Con{item, rest}: reverse.metadata(rest, Con{item, output})

def metadata.count.loop(
  remaining: List<&1, Metadata>,
  retained: List<&1, Metadata>,
  count: Nat
) -> MetadataCount:
  match remaining:
    case Nil{}: MetadataCount{reverse.metadata(retained, Nil{}), count}
    case Con{entry, tail}:
      match entry:
        case Metadata{connection_id, poll_events, phase}:
          metadata.count.loop(tail,
            Con{Metadata{connection_id, poll_events, phase}, retained},
            Nat.add(count, 1n))

def metadata.count(metadata: List<&1, Metadata>) -> MetadataCount:
  metadata.count.loop(metadata, Nil{}, 0n)

def metadata.ids.entry(
  copies: U32 & U32 & U32,
  poll_events: U32,
  phase: Phase,
  tail: List<&1, Metadata>,
  retained: List<&1, Metadata>,
  ids: List<&2, U32>
) -> MetadataIdsState:
  match copies:
    case (metadata_id, (output_id, _)):
      MetadataIdsScanning{tail,
        Con{Metadata{metadata_id, poll_events, phase}, retained},
        Con{output_id, ids}}

def metadata.ids.loop(fuel: Nat, state: MetadataIdsState) -> MetadataIds:
  match fuel:
    case 0n:
      match state:
        case MetadataIdsScanning{_, retained, ids}:
          MetadataListed{reverse.metadata(retained, Nil{}), ids}
    case 1n+rest_fuel:
      match state:
        case MetadataIdsScanning{remaining, retained, ids}:
          match remaining:
            case Nil{}: MetadataListed{reverse.metadata(retained, Nil{}), ids}
            case Con{entry, tail}:
              match entry:
                case Metadata{connection_id, poll_events, phase}:
                  metadata.ids.loop(rest_fuel,
                    metadata.ids.entry(
                      Protocol.u32.duplicate.triple(connection_id),
                      poll_events, phase, tail, retained, ids))

def metadata.ids.counted(counted: MetadataCount) -> MetadataIds:
  match counted:
    case MetadataCount{restored, count}:
      metadata.ids.loop(Nat.add(Nat.mul(count, 2n), 1n),
        MetadataIdsScanning{restored, Nil{}, Nil{}})

def metadata.ids(metadata: List<&1, Metadata>) -> MetadataIds:
  metadata.ids.counted(metadata.count(metadata))

def reverse.interests(remaining: List<SocketTypes.PollInterest>,
  output: List<SocketTypes.PollInterest>) -> List<SocketTypes.PollInterest>:
  match remaining:
    case Nil{}: output
    case Con{item, rest}: reverse.interests(rest, Con{item, output})

def reverse.connections(remaining: List<&1, Connection>,
  output: List<&1, Connection>) -> List<&1, Connection>:
  match remaining:
    case Nil{}: output
    case Con{item, rest}: reverse.connections(rest, Con{item, output})

def count.connections.loop(
  remaining: List<&1, Connection>,
  retained: List<&1, Connection>,
  count: Nat
) -> ConnectionCount:
  match remaining:
    case Nil{}:
      ConnectionCount{reverse.connections(retained, Nil{}), count}
    case Con{connection, rest}:
      count.connections.loop(rest, Con{connection, retained},
        Nat.add(count, 1n))

def count.connections.result(
  state: ConnectionCount
) -> List<&1, Connection> & Nat:
  match state:
    case ConnectionCount{connections, count}: (connections, count)

def count.connections(
  connections: List<&1, Connection>
) -> List<&1, Connection> & Nat:
  count.connections.result(
    count.connections.loop(connections, Nil{}, 0n))

def receive.bytes.payload(
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  expected_bytes: U32 & U32,
  received_bytes: U32,
  deadline_ms: Nat
) -> Phase & Nat:
  match expected_bytes:
    case (retained_expected, measured_expected):
      (ReadingPayload{header, chunks, retained_expected, received_bytes,
        deadline_ms}, TxPolicy.rx.frame.peak(
          U32.to_nat(measured_expected)))

def receive.bytes.phase(phase: Phase) -> Phase & Nat:
  match phase:
    case ReadingHeader{chunks, +received_bytes, deadline_ms}:
      (ReadingHeader{chunks, received_bytes, deadline_ms},
        0n)
    case ReadingPayload{header, chunks, expected_bytes,
      +received_bytes, deadline_ms}:
      receive.bytes.payload(header, chunks,
        u32.duplicate.pair(expected_bytes), received_bytes,
        deadline_ms)
    case AwaitingAdmission{request, deadline_ms, +encoded_bytes}:
      (AwaitingAdmission{request, deadline_ms, encoded_bytes}, encoded_bytes)
    case BoundedAdmission{request, deadline_ms, +encoded_bytes, bound}:
      (BoundedAdmission{request, deadline_ms, encoded_bytes, bound},
        encoded_bytes)
    case WaitingAdmission{pending}:
      (WaitingAdmission{pending}, 0n)
    case Queued{accepted_sequence, bound}:
      (Queued{accepted_sequence, bound}, 0n)
    case InFlight{request_id}: (InFlight{request_id}, 0n)
    case WritingResponse{encoded, written_bytes, deadline_ms, reservation}:
      (WritingResponse{encoded, written_bytes, deadline_ms, reservation}, 0n)
    case Closing{}: (Closing{}, 0n)

def receive.bytes.connection.result(
  pair: Phase & Nat,
  id: U32,
  socket: File,
  poll_events: U32
) -> Connection & Nat:
  match pair:
    case (phase, bytes):
      (Connection{id, socket, poll_events, phase}, bytes)

def receive.bytes.connection.payload(
  id: U32,
  socket: File,
  poll_events: U32,
  payload: Phase & Nat
) -> Connection & Nat:
  match payload:
    case (phase, bytes):
      (Connection{id, socket, poll_events, phase}, bytes)

def receive.bytes.connection(connection: Connection) -> Connection & Nat:
  match connection:
    case Connection{id, socket, poll_events, phase}:
      receive.bytes.connection.result(receive.bytes.phase(phase), id,
        socket, poll_events)

def append.connections(
  left: List<&1, Connection>,
  right: List<&1, Connection>
) -> List<&1, Connection>:
  match left:
    case Nil{}: right
    case Con{connection, rest}:
      Con{connection, append.connections(rest, right)}

def receive.bytes.loop(
  fuel: Nat,
  state: ReceiveLoopState
) -> ReceiveCount:
  match fuel:
    case 0n:
      match state:
        case ReceiveScanning{remaining, retained, total, count}:
          ReceiveCount{append.connections(
            reverse.connections(retained, Nil{}), remaining), total, count}
        case ReceiveMeasured{remaining, retained, total, count, _}:
          ReceiveCount{append.connections(
            reverse.connections(retained, Nil{}), remaining), total, count}
    case 1n+rest_fuel:
      match state:
        case ReceiveScanning{remaining, retained, total, count}:
          match remaining:
            case Nil{}:
              ReceiveCount{reverse.connections(retained, Nil{}), total, count}
            case Con{connection, rest}:
              match connection:
                case Connection{id, socket, poll_events, phase}:
                  match phase:
                    case ReadingHeader{chunks, +received_bytes, deadline_ms}:
                      receive.bytes.loop(rest_fuel, ReceiveScanning{rest,
                        Con{Connection{id, socket, poll_events,
                          ReadingHeader{chunks, received_bytes, deadline_ms}},
                          retained}, total, Nat.add(count, 1n)})
                    case ReadingPayload{header, chunks, expected_bytes,
                      +received_bytes, deadline_ms}:
                      receive.bytes.loop(rest_fuel, ReceiveMeasured{rest,
                        retained, total, count,
                        receive.bytes.connection.payload(id, socket,
                          poll_events, receive.bytes.payload(header, chunks,
                            u32.duplicate.pair(expected_bytes),
                            received_bytes, deadline_ms))})
                    case AwaitingAdmission{request, deadline_ms,
                      +encoded_bytes}:
                      receive.bytes.loop(rest_fuel, ReceiveScanning{rest,
                        Con{Connection{id, socket, poll_events,
                          AwaitingAdmission{request, deadline_ms,
                            encoded_bytes}}, retained},
                        Nat.add(total, encoded_bytes), Nat.add(count, 1n)})
                    case BoundedAdmission{request, deadline_ms,
                      +encoded_bytes, bound}:
                      receive.bytes.loop(rest_fuel, ReceiveScanning{rest,
                        Con{Connection{id, socket, poll_events,
                          BoundedAdmission{request, deadline_ms,
                            encoded_bytes, bound}}, retained},
                        Nat.add(total, encoded_bytes), Nat.add(count, 1n)})
                    case WaitingAdmission{pending}:
                      receive.bytes.loop(rest_fuel, ReceiveScanning{rest,
                        Con{Connection{id, socket, poll_events,
                          WaitingAdmission{pending}}, retained}, total,
                        Nat.add(count, 1n)})
                    case Queued{accepted_sequence, bound}:
                      receive.bytes.loop(rest_fuel, ReceiveScanning{rest,
                        Con{Connection{id, socket, poll_events,
                          Queued{accepted_sequence, bound}}, retained}, total,
                        Nat.add(count, 1n)})
                    case InFlight{request_id}:
                      receive.bytes.loop(rest_fuel, ReceiveScanning{rest,
                        Con{Connection{id, socket, poll_events,
                          InFlight{request_id}}, retained}, total,
                        Nat.add(count, 1n)})
                    case WritingResponse{encoded, written_bytes,
                      deadline_ms, reservation}:
                      receive.bytes.loop(rest_fuel, ReceiveScanning{rest,
                        Con{Connection{id, socket, poll_events,
                          WritingResponse{encoded, written_bytes,
                            deadline_ms, reservation}}, retained}, total,
                        Nat.add(count, 1n)})
                    case Closing{}:
                      receive.bytes.loop(rest_fuel, ReceiveScanning{rest,
                        Con{Connection{id, socket, poll_events, Closing{}},
                          retained}, total, Nat.add(count, 1n)})
        case ReceiveMeasured{remaining, retained, total, count, processed}:
          match processed:
            case (connection, bytes):
              receive.bytes.loop(rest_fuel, ReceiveScanning{remaining,
                Con{connection, retained}, Nat.add(total, bytes),
                Nat.add(count, 1n)})

def receive.metrics.counted(
  counted: List<&1, Connection> & Nat
) -> ReceiveCount:
  match counted:
    case (connections, count):
      receive.bytes.loop(Nat.add(Nat.mul(2n, count), 1n),
        ReceiveScanning{connections, Nil{}, 0n, 0n})

def receive.metrics(
  connections: List<&1, Connection>
) -> ReceiveCount:
  receive.metrics.counted(count.connections(connections))

def transmit.bytes.response.bytes(+len: U32) -> Nat:
  U32.to_nat(len)

def transmit.frame.measured(
  id: U32,
  socket: File,
  events: U32,
  written: U32,
  deadline: Nat,
  measured: Bytes.Bytes & U32,
  reservation: TxPolicy.FrameReservation
) -> Connection & Nat & Nat:
  match measured reservation:
    case (encoded, length) TxPolicy.FrameReservation{reservation_id, +reserved}:
      (Connection{id, socket, events, WritingResponse{encoded, written,
        deadline, TxPolicy.FrameReservation{reservation_id, reserved}}},
        (reserved, U32.to_nat(length)))

def transmit.connection.measured(connection: Connection) -> Connection & Nat & Nat:
  match connection:
    case Connection{id, socket, events,
        WritingResponse{encoded, written, deadline, reservation}}:
      transmit.frame.measured(id, socket, events, written, deadline,
        Bytes.length(encoded), reservation)
    case other: (other, (0n, 0n))

# Reserves one control frame and header slot for each admitted connection.
def transmit.summary(
  connections: List<&1, Connection>,
  reserved: Nat,
  +count: Nat,
  live: Nat
) -> TransmitCount:
  TransmitCount{connections, reserved, count, live,
    TxPolicy.slots.control.bytes(count), TxPolicy.slots.header.bytes(count)}

def transmit.prepend(
  measured: Connection & Nat & Nat,
  remaining: TransmitCount
) -> TransmitCount:
  match measured remaining:
    case (connection, (reserved, live))
      TransmitCount{connections, tail_reserved, count, tail_live, _, _}:
      transmit.summary(Con{connection, connections}, Nat.add(reserved, tail_reserved),
        Nat.add(count, 1n), Nat.add(live, tail_live))

def transmit.metrics(connections: List<&1, Connection>) -> TransmitCount:
  match connections:
    case Nil{}: transmit.summary(Nil{}, 0n, 0n, 0n)
    case Con{connection, remaining}:
      transmit.prepend(transmit.connection.measured(connection),
        transmit.metrics(remaining))

def detach.comparison.id(
  ids: U32 & U32 & U32,
  socket: File,
  poll_events: U32,
  phase: Phase,
  target: U32
) -> Connection & Bool:
  match ids:
    case (id, (comparison_id, _)):
      (Connection{id, socket, poll_events, phase},
        U32.is_eq(comparison_id, target))

def detach.comparison(
  connection: Connection,
  target: U32
) -> Connection & Bool:
  match connection:
    case Connection{id, socket, poll_events, phase}:
      detach.comparison.id(Protocol.u32.duplicate.triple(id), socket,
        poll_events, phase, target)

def detach.loop(fuel: Nat, state: DetachSearch) -> DetachResult:
  match fuel:
    case 0n: DetachExhausted{state}
    case 1n+fuel_rest:
      match state:
        case DetachScanning{remaining, retained, targets}:
          match remaining:
            case Nil{}:
              DetachNotFound{reverse.connections(retained, Nil{})}
            case Con{connection, connection_rest}:
              match targets:
                case (target, (recurse_target, _)):
                  detach.loop(fuel_rest,
                    DetachCompared{detach.comparison(connection, target),
                      connection_rest, retained,
                      Protocol.u32.duplicate.triple(recurse_target)})
        case DetachCompared{pair, remaining, retained, targets}:
          match pair:
            case (connection, True{}):
              Detached{append.connections(
                reverse.connections(retained, Nil{}), remaining), connection}
            case (connection, False{}):
              detach.loop(fuel_rest,
                DetachScanning{remaining, Con{connection, retained}, targets})

def detach.counted(counted: List<&1, Connection> & Nat,
  target: U32) -> DetachResult:
  match counted:
    case (connections, count):
      detach.loop(Nat.add(Nat.mul(count, 2n), 1n),
        DetachScanning{connections, Nil{},
          Protocol.u32.duplicate.triple(target)})

# Handles detach.
def detach(connections: List<&1, Connection>, target: U32) -> DetachResult:
  detach.counted(count.connections(connections), target)

def detach.state.connections(state: DetachSearch) -> List<&1, Connection>:
  match state:
    case DetachScanning{remaining, retained, _}:
      append.connections(reverse.connections(retained, Nil{}), remaining)
    case DetachCompared{pair, remaining, retained, _}:
      match pair:
        case (connection, _):
          append.connections(reverse.connections(retained, Nil{}),
            Con{connection, remaining})

def insert.counted(
  counted: List<&1, Connection> & Nat,
  connection: Connection,
  max_connections: Nat
) -> InsertResult:
  match counted:
    case (existing, count):
      insert.decided(existing, connection,
        ConnectionPolicy.capacity(count, max_connections))

# Handles insert.
def insert(
  existing: List<&1, Connection>,
  connection: Connection,
  max_connections: Nat
) -> InsertResult:
  insert.counted(count.connections(existing), connection, max_connections)

def header.payload.accepted(
  id: U32,
  socket: File,
  poll_events: U32,
  deadline_ms: Nat,
  header: Bytes.Bytes,
  frame_lengths: U32 & U32 & U32
) -> Connection & HeaderStatus:
  match frame_lengths:
    case (phase_length, (status_length, _)):
      (Connection{id, socket, poll_events,
        ReadingPayload{header, Nil{}, U32.sub(phase_length, 24), 0,
          deadline_ms}},
        HeaderPayload{U32.sub(status_length, 24)})

def header.updated(
  id: U32,
  socket: File,
  poll_events: U32,
  deadline_ms: Nat,
  step: ConnectionPolicy.HeaderStep
) -> Connection & HeaderStatus:
  match step:
    case ConnectionPolicy.HeaderPartial{chunks, received_bytes}:
      (Connection{id, socket, poll_events,
        ReadingHeader{chunks, U32.from_nat(received_bytes), deadline_ms}},
        HeaderWaiting{})
    case ConnectionPolicy.HeaderAccepted{header, frame_bytes}:
      header.payload.accepted(id, socket, poll_events, deadline_ms, header,
        Protocol.u32.duplicate.triple(frame_bytes))
    case ConnectionPolicy.HeaderRejected{decision}:
      (Connection{id, socket, poll_events, Closing{}},
        HeaderRejected{decision})

def header.received(
  connection: Connection,
  chunk: Bytes.Bytes,
  max_payload_bytes: Nat
) -> Connection & HeaderStatus:
  match connection:
    case Connection{id, socket, poll_events, phase}:
      match phase:
        case ReadingHeader{chunks, received_bytes, deadline_ms}:
          header.updated(id, socket, poll_events, deadline_ms,
            ConnectionPolicy.header.step(chunks, U32.to_nat(received_bytes),
              chunk, max_payload_bytes))
        case _: (Connection{id, socket, poll_events, phase},
          HeaderNotReading{})

def payload.ready(
  id: U32,
  socket: File,
  poll_events: U32,
  queue_deadline_ms: Nat,
  expected_bytes: U32,
  request: Protocol.Request
) -> Connection & PayloadStatus:
  (Connection{id, socket, poll_events,
    AwaitingAdmission{request, queue_deadline_ms,
      Nat.add(24n, U32.to_nat(expected_bytes))}}, PayloadReady{})

def payload.updated.header(
  id: U32,
  socket: File,
  poll_events: U32,
  deadline_ms: Nat,
  expected_bytes: U32,
  queue_deadline_ms: Nat,
  step: ConnectionPolicy.PayloadStep
) -> Connection & PayloadStatus:
  match step:
    case ConnectionPolicy.PayloadPartial{header, chunks, received_bytes}:
      (Connection{id, socket, poll_events,
        ReadingPayload{header, chunks, expected_bytes,
          U32.from_nat(received_bytes), deadline_ms}},
        PayloadWaiting{})
    case ConnectionPolicy.PayloadAccepted{request}:
      payload.ready(id, socket, poll_events, queue_deadline_ms,
        expected_bytes, request)
    case ConnectionPolicy.PayloadRejected{decision}:
      (Connection{id, socket, poll_events, Closing{}},
        PayloadRejected{decision})

def payload.received.expected(
  id: U32,
  socket: File,
  poll_events: U32,
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: U32,
  deadline_ms: Nat,
  expected: U32 & U32 & U32,
  chunk: Bytes.Bytes,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat
) -> Connection & PayloadStatus:
  match expected:
    case (phase_expected, (decode_expected, _)):
      payload.updated.header(id, socket, poll_events, deadline_ms,
        phase_expected, queue_deadline_ms,
        ConnectionPolicy.payload.step(header, chunks,
          U32.to_nat(received_bytes), chunk, decode_expected,
          max_payload_bytes))

def payload.received(
  connection: Connection,
  chunk: Bytes.Bytes,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat
) -> Connection & PayloadStatus:
  match connection:
    case Connection{id, socket, poll_events, phase}:
      match phase:
        case ReadingPayload{header, chunks, expected_bytes,
          received_bytes, deadline_ms}:
          payload.received.expected(id, socket, poll_events, header, chunks,
            received_bytes, deadline_ms,
            Protocol.u32.duplicate.triple(expected_bytes), chunk,
            max_payload_bytes, queue_deadline_ms)
        case _: (Connection{id, socket, poll_events, phase},
          PayloadNotReading{})

def payload.empty(
  connection: Connection,
  max_payload_bytes: Nat,
  queue_deadline_ms: Nat
) -> Connection & PayloadStatus:
  payload.received(connection, Bytes.new(0), max_payload_bytes,
    queue_deadline_ms)

def admission.rejected(
  id: U32,
  socket: File,
  poll_events: U32,
  queue: Queue.Queue,
  pending: Queue.Pending,
  reason: QueuePolicy.Rejection
) -> AdmissionResult:
  match pending:
    case Queue.Pending{_, _, deadline_ms, encoded_bytes, _, request}:
      AdmissionResult{
        Connection{id, socket, poll_events,
          AwaitingAdmission{request, deadline_ms, encoded_bytes}},
        queue, AdmissionRejected{reason}}

def admission.decided(
  id: U32,
  socket: File,
  poll_events: U32,
  sequence: Nat & Nat,
  bound: TxPolicy.BoundDecision,
  decision: Queue.Admission
) -> AdmissionResult:
  match sequence:
    case (connection_sequence, status_sequence):
      match decision:
        case Queue.Enqueued{queue}:
          AdmissionResult{Connection{id, socket, poll_events,
            Queued{connection_sequence, bound}}, queue,
            AdmissionQueued{status_sequence}}
        case Queue.Rejected{queue, pending, reason}:
          admission.rejected(id, socket, poll_events, queue, pending, reason)

def admission.sequence.copies.status(
  pending_sequence: Nat,
  copies: Nat & Nat
) -> Nat & Nat & Nat:
  match copies:
    case (connection_sequence, status_sequence):
      (pending_sequence, (connection_sequence, status_sequence))

def admission.sequence.copies.pair(copies: Nat & Nat) -> Nat & Nat & Nat:
  match copies:
    case (pending_sequence, other):
      admission.sequence.copies.status(pending_sequence,
        Protocol.nat.duplicate.pair(other))

def admission.sequence.copies(value: Nat) -> Nat & Nat & Nat:
  admission.sequence.copies.pair(Protocol.nat.duplicate.pair(value))

def admission.response.bound.value(
  payload_bytes: U32,
  peaks: Nat & Nat
) -> TxPolicy.BoundDecision & Nat:
  match peaks:
    case (bound_peak, response_peak):
      (TxPolicy.Bounded{payload_bytes, bound_peak}, response_peak)

def admission.response.bound(
  bound: TxPolicy.BoundDecision
) -> TxPolicy.BoundDecision & Nat:
  match bound:
    case TxPolicy.Bounded{payload_bytes, +peak_bytes}:
      admission.response.bound.value(payload_bytes,
        Protocol.nat.duplicate.pair(peak_bytes))
    case TxPolicy.InvalidRequest{}: (TxPolicy.InvalidRequest{}, 28n)
    case TxPolicy.TooLarge{}: (TxPolicy.TooLarge{}, 4294967295n)

def admission.pending.queued(
  ids: U32 & U32,
  socket: File,
  poll_events: U32,
  sequence: Nat & Nat & Nat,
  bound: TxPolicy.BoundDecision,
  response_peak: Nat,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  request: Protocol.Request,
  queue: Queue.Queue,
  max_count: Nat,
  max_bytes: Nat
) -> AdmissionResult:
  match ids:
    case (connection_id, pending_id):
      match sequence:
        case (pending_sequence, (queued_sequence, status_sequence)):
          admission.decided(connection_id, socket, poll_events,
            (queued_sequence, status_sequence), bound,
            Queue.enqueue(queue,
              Queue.Pending{pending_id, pending_sequence, deadline_ms,
                encoded_bytes, response_peak, request}, max_count, max_bytes))

def admission.pending.bounded(
  ids: U32 & U32,
  socket: File,
  poll_events: U32,
  sequence: Nat & Nat & Nat,
  bound_peak: TxPolicy.BoundDecision & Nat,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  request: Protocol.Request,
  queue: Queue.Queue,
  max_count: Nat,
  max_bytes: Nat
) -> AdmissionResult:
  match bound_peak:
    case (bound, response_peak):
      admission.pending.queued(ids, socket, poll_events, sequence, bound,
        response_peak, deadline_ms, encoded_bytes, request, queue, max_count,
        max_bytes)

def admission.pending(
  ids: U32 & U32,
  socket: File,
  poll_events: U32,
  sequence: Nat & Nat & Nat,
  bound: TxPolicy.BoundDecision,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  request: Protocol.Request,
  queue: Queue.Queue,
  max_count: Nat,
  max_bytes: Nat
) -> AdmissionResult:
  admission.pending.bounded(ids, socket, poll_events, sequence,
    admission.response.bound(bound), deadline_ms, encoded_bytes, request,
    queue, max_count, max_bytes)

def admission.waiting(
  ids: U32 & U32 & U32,
  socket: File,
  poll_events: U32,
  sequence: Nat & Nat & Nat,
  bound: TxPolicy.BoundDecision,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  request: Protocol.Request,
  queue: Queue.Queue,
  max_count: Nat,
  max_bytes: Nat
) -> AdmissionResult:
  match ids:
    case (connection_id, (pending_id, _)):
      admission.pending((connection_id, pending_id), socket, poll_events,
        sequence, bound, deadline_ms, encoded_bytes, request, queue,
        max_count, max_bytes)

def admission.not_ready(
  connection: Connection,
  queue: Queue.Queue
) -> AdmissionResult:
  AdmissionResult{connection, queue, AdmissionNotReady{}}

# Handles admission.
def admission(
  connection: Connection,
  queue: Queue.Queue,
  accepted_sequence: Nat,
  max_count: Nat,
  max_bytes: Nat,
  _response_bytes: U32
) -> AdmissionResult:
  match connection:
    case Connection{id, socket, poll_events, phase}:
      match phase:
        case AwaitingAdmission{request, deadline_ms, encoded_bytes}:
          admission.not_ready(Connection{id, socket, poll_events,
            AwaitingAdmission{request, deadline_ms, encoded_bytes}}, queue)
        case BoundedAdmission{request, deadline_ms, encoded_bytes, bound}:
          admission.waiting(
            Protocol.u32.duplicate.triple(id),
            socket, poll_events,
            admission.sequence.copies(accepted_sequence), bound, deadline_ms,
            encoded_bytes, request, queue, max_count, max_bytes)
        case _: admission.not_ready(
          Connection{id, socket, poll_events, phase}, queue)

def restore.loop(metadata: List<&1, Metadata>,
  interests: List<SocketTypes.PollInterest>,
  restored: List<&1, Connection>, ids_valid: Bool) -> RestoreDecision:
  match metadata:
    case Nil{}:
      match interests:
        case Nil{}: Restored{reverse.connections(restored, Nil{}), ids_valid}
        case Con{_, _}: InvalidLengths{Nil{}, interests}
    case Con{entry, metadata_rest}:
      match entry:
        case Metadata{+id, poll_events, phase}:
          match interests:
            case Nil{}:
              InvalidLengths{Con{Metadata{id, poll_events, phase}, metadata_rest}, Nil{}}
            case Con{interest, interest_rest}:
              match interest:
                case SocketTypes.PollInterest{interest_id, socket, events}:
                  restore.loop(metadata_rest, interest_rest,
                    Con{Connection{id, socket, poll_events, phase}, restored},
                    Bool.and(ids_valid, U32.is_eq(id, interest_id)))

# Handles restore.
def restore(metadata: List<&1, Metadata>,
  interests: List<SocketTypes.PollInterest>) -> RestoreDecision:
  restore.loop(metadata, interests, Nil{}, True{})

def split.loop(remaining: List<&1, Connection>,
  metadata: List<&1, Metadata>,
  interests: List<SocketTypes.PollInterest>) -> Split:
  match remaining:
    case Nil{}:
      Split{reverse.metadata(metadata, Nil{}),
        reverse.interests(interests, Nil{})}
    case Con{connection, rest}:
      match connection:
        case Connection{+id, socket, +poll_events, phase}:
          split.loop(rest, Con{Metadata{id, poll_events, phase}, metadata},
            Con{SocketTypes.PollInterest{id, socket, poll_events}, interests})

# Handles split.
def split(connections: List<&1, Connection>) -> Split:
  split.loop(connections, Nil{}, Nil{})
