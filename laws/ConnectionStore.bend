import Base
import ../src/coordinator/ConnectionStore.bend as Store
import ../src/coordinator/ConnectionPolicy.bend as ConnectionPolicy
import ../src/coordinator/Protocol.bend as Protocol
import ../src/coordinator/RequestQueue.bend as Queue
import ../src/coordinator/QueuePolicy.bend as QueuePolicy
import ../src/coordinator/TransportBudgetPolicy.bend as TxPolicy
import ../src/coordinator/UnixSocketTypes.bend as SocketTypes
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Verifies queued bound update preserves the connection ownership.
law queued_bound_update_preserves_the_connection_ownership:
  for id: U32
  for socket: File
  for poll_events: U32
  for sequence: Nat
  for old_bound: TxPolicy.BoundDecision
  for new_bound: TxPolicy.BoundDecision
  {Store.queued.bound.selected(Store.Connection{id, socket, poll_events,
    Store.Queued{sequence, old_bound}}, new_bound, True{}) ==
    Store.Connection{id, socket, poll_events,
      Store.Queued{sequence, new_bound}} : Store.Connection}

# Verifies unselected bound update preserves every phase.
law unselected_bound_update_preserves_every_phase:
  for connection: Store.Connection
  for bound: TxPolicy.BoundDecision
  {Store.queued.bound.selected(connection, bound, False{}) == connection :
    Store.Connection}

def header.prefix(sliced: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match sliced:
    case (_, prefix): prefix

# Verifies readiness search finds the matching connection.
law readiness_search_finds_the_matching_connection:
  {Store.event.find(7, [SocketTypes.ReadyEvent{2, 1},
    SocketTypes.ReadyEvent{7, 5}]) == Store.EventReady{5} :
      Store.EventReadiness}

# Verifies readiness search skips unrelated events.
law readiness_search_skips_unrelated_events:
  {Store.event.find(4, [SocketTypes.ReadyEvent{2, 1},
    SocketTypes.ReadyEvent{7, 5}]) == Store.EventNotReady{} :
      Store.EventReadiness}

# Verifies readiness validation accepts known unique ids.
law readiness_validation_accepts_known_unique_ids:
  {Store.events.validate([SocketTypes.ReadyEvent{2, 1},
      SocketTypes.ReadyEvent{7, 5}], [2, 7]) == Store.EventsValid{} :
      Store.EventValidation}

# Verifies readiness validation rejects one event without connections.
law readiness_validation_rejects_one_event_without_connections:
  for id: U32
  for flags: U32
  {Store.events.validate([SocketTypes.ReadyEvent{id, flags}], []) ==
    Store.EventUnknown{id} : Store.EventValidation}

# Verifies readiness validation rejects unknown ids.
law readiness_validation_rejects_unknown_ids:
  {Store.events.validate([SocketTypes.ReadyEvent{9, 1}], [2, 7]) ==
    Store.EventUnknown{9} : Store.EventValidation}

# Verifies readiness validation rejects duplicate ids.
law readiness_validation_rejects_duplicate_ids:
  {Store.events.validate([SocketTypes.ReadyEvent{2, 1},
      SocketTypes.ReadyEvent{2, 5}], [2, 7]) == Store.EventDuplicate{2} :
      Store.EventValidation}

# Verifies connection detach preserves relative order.
law connection_detach_preserves_relative_order:
  for first: File
  for target: File
  for last: File
  {Store.detach([Store.Connection{1, first, 1, Store.Closing{}},
      Store.Connection{7, target, 1, Store.Closing{}},
      Store.Connection{9, last, 1, Store.Closing{}}], 7) ==
    Store.Detached{[Store.Connection{1, first, 1, Store.Closing{}},
      Store.Connection{9, last, 1, Store.Closing{}}],
      Store.Connection{7, target, 1, Store.Closing{}}} : Store.DetachResult}

# Verifies accepted socket starts with an empty header.
law accepted_socket_starts_with_an_empty_header:
  for id: U32
  for socket: File
  for deadline_ms: Nat
  {Store.open(id, socket, deadline_ms) ==
    Store.Connection{id, socket, 1,
      Store.ReadingHeader{Nil{}, 0, deadline_ms}} : Store.Connection}

# Verifies transmit metrics retain full response buffers.
law transmit_metrics_retain_full_response_buffers:
  for socket: File
  {Store.transmit.metrics([
    Store.Connection{1, socket, 4,
      Store.WritingResponse{Bytes.new(3), 1, 90n,
        TxPolicy.FrameReservation{1, 3n}}},
    Store.Connection{2, socket, 1, Store.Closing{}}]) ==
    Store.TransmitCount{[
      Store.Connection{1, socket, 4,
        Store.WritingResponse{Bytes.new(3), 1, 90n,
          TxPolicy.FrameReservation{1, 3n}}},
      Store.Connection{2, socket, 1, Store.Closing{}}], 3n, 2n} :
    Store.TransmitCount}

# Verifies response reservation counts the whole encoded frame.
law response_reservation_counts_the_whole_encoded_frame:
  for len: U32
  {Store.transmit.bytes.response.bytes(len) == U32.to_nat(len) : Nat}

# Verifies rx fragment progress keeps the entire frame peak reserved.
law rx_fragment_progress_keeps_the_entire_frame_peak_reserved:
  for expected_bytes: U32
  for received_bytes: U32
  {Store.receive.bytes.phase(Store.ReadingPayload{Bytes.new(0), Nil{},
    expected_bytes, received_bytes, 10n}) ==
    (Store.ReadingPayload{Bytes.new(0), Nil{}, expected_bytes,
      received_bytes, 10n},
      TxPolicy.rx.frame.peak(U32.to_nat(expected_bytes))) : Store.Phase & Nat}

# Verifies rx partial transition preserves expected frame and deadline.
law rx_partial_transition_preserves_expected_frame_and_deadline:
  for id: U32
  for socket: File
  for poll_events: U32
  for deadline_ms: Nat
  for expected_bytes: U32
  for queue_deadline_ms: Nat
  for received_bytes: Nat
  {Store.payload.updated.header(id, socket, poll_events, deadline_ms,
    expected_bytes, queue_deadline_ms,
    ConnectionPolicy.PayloadPartial{Bytes.new(0), Nil{}, received_bytes}) ==
    (Store.Connection{id, socket, poll_events,
      Store.ReadingPayload{Bytes.new(0), Nil{}, expected_bytes,
        U32.from_nat(received_bytes), deadline_ms}}, Store.PayloadWaiting{}) :
      Store.Connection & Store.PayloadStatus}

# Verifies rx completed frame moves the request to admission.
law rx_completed_frame_moves_the_request_to_admission:
  for id: U32
  for socket: File
  for poll_events: U32
  for deadline_ms: Nat
  for expected_bytes: U32
  for queue_deadline_ms: Nat
  for request: Protocol.Request
  {Store.payload.updated.header(id, socket, poll_events, deadline_ms,
    expected_bytes, queue_deadline_ms,
    ConnectionPolicy.PayloadAccepted{request}) ==
    (Store.Connection{id, socket, poll_events,
      Store.AwaitingAdmission{request, queue_deadline_ms,
        Nat.add(24n, U32.to_nat(expected_bytes))}}, Store.PayloadReady{}) :
      Store.Connection & Store.PayloadStatus}

# Verifies rx closed connection has no live payload reservation.
law rx_closed_connection_has_no_live_payload_reservation:
  {Store.receive.bytes.phase(Store.Closing{}) ==
    (Store.Closing{}, 0n) : Store.Phase & Nat}

# Verifies insertion respects the connection capacity.
law insertion_respects_the_connection_capacity:
  for socket: File
  {Store.insert(Nil{}, Store.open(1, socket, 40n), 1n) ==
    Store.Inserted{Con{Store.Connection{1, socket, 1,
      Store.ReadingHeader{Nil{}, 0, 40n}}, Nil{}}} : Store.InsertResult}

# Verifies full connection capacity preserves existing slots.
law full_connection_capacity_preserves_existing_slots:
  for existing: File
  for socket: File
  {Store.insert(Con{Store.Connection{2, existing, 1,
      Store.ReadingHeader{Nil{}, 0, 10n}}, Nil{}},
      Store.open(3, socket, 40n), 1n) == Store.Full{
        Con{Store.Connection{2, existing, 1,
          Store.ReadingHeader{Nil{}, 0, 10n}}, Nil{}},
        Store.Connection{3, socket, 1,
          Store.ReadingHeader{Nil{}, 0, 40n}}} : Store.InsertResult}

# Verifies bounded admission transfers response peak to fifo.
law bounded_admission_transfers_response_peak_to_fifo:
  for socket: File
  {Store.admission(Store.Connection{1, socket, 1,
      Store.BoundedAdmission{Protocol.Request{1, 1, 9, 2, Bytes.new(0)},
        100n, 24n, TxPolicy.Bounded{0, 28n}}}, Queue.empty(), 4n, 1n,
        24n, 64) ==
    Store.AdmissionResult{
      Store.Connection{1, socket, 1,
        Store.Queued{4n, TxPolicy.Bounded{0, 28n}}},
      Queue.Queue{Nil{},
        Con{Queue.Pending{1, 4n, 100n, 24n, 28n,
          Protocol.Request{1, 1, 9, 2, Bytes.new(0)}}, Nil{}}, 1n, 24n},
      Store.AdmissionQueued{4n}} : Store.AdmissionResult}

# Verifies awaiting admission waits for tx preflight.
law awaiting_admission_waits_for_tx_preflight:
  for socket: File
  {Store.admission(Store.Connection{1, socket, 1,
      Store.AwaitingAdmission{Protocol.Request{1, 1, 9, 2, Bytes.new(0)},
        100n, 24n}}, Queue.empty(), 4n, 1n, 24n, 64) ==
    Store.AdmissionResult{
      Store.Connection{1, socket, 1,
        Store.AwaitingAdmission{Protocol.Request{1, 1, 9, 2,
          Bytes.new(0)}, 100n, 24n}},
      Queue.empty(), Store.AdmissionNotReady{}} : Store.AdmissionResult}

# Verifies awaiting admission keeps request when queue is saturated.
law awaiting_admission_keeps_request_when_queue_is_saturated:
  for socket: File
  {Store.admission(Store.Connection{1, socket, 1,
      Store.AwaitingAdmission{Protocol.Request{1, 1, 9, 2, Bytes.new(0)},
        100n, 24n}}, Queue.empty(), 4n, 0n, 24n, 64) ==
    Store.AdmissionResult{
      Store.Connection{1, socket, 1,
        Store.AwaitingAdmission{Protocol.Request{1, 1, 9, 2, Bytes.new(0)},
          100n, 24n}},
      Queue.empty(), Store.AdmissionNotReady{}} :
      Store.AdmissionResult}

# Verifies empty payload becomes admissible without socket read.
law empty_payload_becomes_admissible_without_socket_read:
  for socket: File
  {Store.payload.empty(Store.Connection{1, socket, 1,
      Store.ReadingPayload{
        header.prefix(Bytes.slice(Protocol.encode(
          Protocol.Request{1, 1, 9, 2, Bytes.new(0)}), 0, 24)),
        Nil{}, 0, 0, 10n}}, 16n, 50n) ==
    (Store.Connection{1, socket, 1,
      Store.AwaitingAdmission{Protocol.Request{1, 1, 9, 2, Bytes.new(0)},
        50n, 24n}}, Store.PayloadReady{}) : Store.Connection &
      Store.PayloadStatus}
