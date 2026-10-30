import Base
import ../src/coordinator/TransportBudgetPolicy.bend as Policy
import ../src/coordinator/RequestQueue.bend as Queue
import ../src/coordinator/Protocol.bend as Protocol

# Verifies dispatch moves the request and preserves its reservation.
law dispatch_moves_the_request_and_preserves_its_reservation:
  for reservation: Policy.DispatchReservation
  for request: Protocol.Request
  {Policy.tx.flight.start(Policy.ReservedRequest{reservation, request}) ==
    Policy.DispatchStarted{Policy.DispatchedRequest{reservation}, request} :
    Policy.DispatchStart}

# Verifies dispatched request cannot be dispatched again.
law dispatched_request_cannot_be_dispatched_again:
  for reservation: Policy.DispatchReservation
  {Policy.tx.flight.start(Policy.DispatchedRequest{reservation}) ==
    Policy.DispatchAlreadyStarted{Policy.DispatchedRequest{reservation}} :
    Policy.DispatchStart}

# Verifies completed dispatch transfers the same reservation.
law completed_dispatch_transfers_the_same_reservation:
  for reservation: Policy.DispatchReservation
  for response: Protocol.Response
  {Policy.tx.flight.complete(Policy.DispatchedRequest{reservation}, response) ==
    Policy.DispatchCompleted{reservation, response} : Policy.DispatchCompletion}

# Verifies completion before dispatch preserves the unexecuted request.
law completion_before_dispatch_preserves_the_unexecuted_request:
  for reservation: Policy.DispatchReservation
  for request: Protocol.Request
  for response: Protocol.Response
  {Policy.tx.flight.complete(Policy.ReservedRequest{reservation, request},
    response) == Policy.DispatchCompletionRejected{
      Policy.ReservedRequest{reservation, request}, response} :
    Policy.DispatchCompletion}

# Verifies writing response preserves the dispatch reservation.
law writing_response_preserves_the_dispatch_reservation:
  for connection_id: U32
  for request_bytes: Nat
  for payload_limit: U32
  for peak_bytes: Nat
  {Policy.tx.frame.transfer(Policy.DispatchReservation{connection_id,
    request_bytes, payload_limit, peak_bytes}) ==
    Policy.FrameReservation{connection_id, peak_bytes} : Policy.FrameReservation}

# Verifies partial writes keep the complete frame reservation.
law partial_writes_keep_the_complete_frame_reservation:
  for connection_id: U32
  for reserved_bytes: Nat
  {Policy.tx.frame.measure(Policy.FrameReservation{connection_id,
    reserved_bytes}) == (Policy.FrameReservation{connection_id, reserved_bytes},
      reserved_bytes) : Policy.FrameReservation & Nat}

# Verifies control slot is separate from the data reservation.
law control_slot_is_separate_from_the_data_reservation:
  for connection_id: U32
  {Policy.tx.frame.control(connection_id) ==
    Policy.FrameReservation{connection_id, 0n} : Policy.FrameReservation}

# Verifies impossible response never waits.
law impossible_response_never_waits:
  for available: Bool
  {Policy.tx.decide(False{}, available) == Policy.Reject{} : Policy.TxDecision}

# Verifies temporary tx pressure preserves wait.
law temporary_tx_pressure_preserves_wait:
  {Policy.tx.decide(True{}, False{}) == Policy.WaitForCapacity{} : Policy.TxDecision}

# Verifies sufficient tx reserves before dispatch.
law sufficient_tx_reserves_before_dispatch:
  {Policy.tx.decide(True{}, True{}) == Policy.Reserve{} : Policy.TxDecision}

# Verifies tx reservation records the reserved total.
law tx_reservation_records_the_reserved_total:
  for used: Nat
  for required: Nat
  for capacity: Nat
  {Policy.tx.reserve(used, required, capacity) ==
    Policy.tx.reserve.result(used, required,
      Policy.tx.request(used, required, capacity)) : Policy.TxReservation}

# Verifies tx wait keeps existing reservations.
law tx_wait_keeps_existing_reservations:
  for used: Nat
  for required: Nat
  for capacity: Nat
  {Policy.tx.reserve.result(used, required, Policy.WaitForCapacity{}) ==
    Policy.TxWaiting{used} : Policy.TxReservation}

# Verifies tx rejection keeps existing reservations.
law tx_rejection_keeps_existing_reservations:
  for used: Nat
  for required: Nat
  for capacity: Nat
  {Policy.tx.reserve.result(used, required, Policy.Reject{}) ==
    Policy.TxRejected{used} : Policy.TxReservation}

# Verifies terminal peer cannot remain paused.
law terminal_peer_cannot_remain_paused:
  for owns_credit: Bool
  {Policy.rx.interest(True{}, owns_credit) == Policy.ClosePeer{} : Policy.RxInterest}

# Verifies rx frame peak includes header and decoder overlap.
law rx_frame_peak_includes_header_and_decoder_overlap:
  for payload_bytes: Nat
  {Policy.rx.frame.peak(payload_bytes) ==
    Nat.add(48n, Nat.mul(3n, payload_bytes)) : Nat}

# Verifies rx reservation wait preserves existing credit.
law rx_reservation_wait_preserves_existing_credit:
  for used_bytes: Nat
  for required_bytes: Nat
  for capacity_bytes: Nat
  {Policy.rx.frame.reservation(used_bytes, required_bytes, capacity_bytes,
    True{}, False{}) == Policy.WaitForFrameCredit{used_bytes} :
      Policy.RxReservationDecision}

# Verifies rx impossible frame is rejected before allocation.
law rx_impossible_frame_is_rejected_before_allocation:
  for used_bytes: Nat
  for required_bytes: Nat
  for capacity_bytes: Nat
  {Policy.rx.frame.reservation(used_bytes, required_bytes, capacity_bytes,
    False{}, True{}) == Policy.RejectFrame{used_bytes} :
      Policy.RxReservationDecision}

# Verifies rx reserve full frame when credit is available.
law rx_reserve_full_frame_when_credit_is_available:
  for used_bytes: Nat
  for required_bytes: Nat
  for capacity_bytes: Nat
  {Policy.rx.frame.reservation(used_bytes, required_bytes, capacity_bytes,
    True{}, True{}) ==
    Policy.ReserveFrame{Nat.add(used_bytes, required_bytes)} :
      Policy.RxReservationDecision}

# Verifies rx temporarily full budget waits with credit unchanged.
law rx_temporarily_full_budget_waits_with_credit_unchanged:
  {Policy.rx.frame.reserve(4095n, 78n, 4095n) ==
    Policy.WaitForFrameCredit{4095n} : Policy.RxReservationDecision}

# Verifies rx frame over total budget is rejected.
law rx_frame_over_total_budget_is_rejected:
  {Policy.rx.frame.reserve(0n, 9048n, 4095n) ==
    Policy.RejectFrame{0n} : Policy.RxReservationDecision}

# Verifies rx frame reserves at exact peak boundary.
law rx_frame_reserves_at_exact_peak_boundary:
  {Policy.rx.frame.reserve(0n, 4095n, 4095n) ==
    Policy.ReserveFrame{4095n} : Policy.RxReservationDecision}

# Verifies fifo head waits without capacity.
law fifo_head_waits_without_capacity:
  {Policy.tx.queue.decide(Policy.HeadPolicy{True{}, False{}, False{}}) ==
    Policy.KeepHead{} : Policy.QueueDecision}

# Verifies fifo head rejects impossible response.
law fifo_head_rejects_impossible_response:
  for available: Bool
  {Policy.tx.queue.decide(Policy.HeadPolicy{False{}, available, False{}}) ==
    Policy.RejectHead{} : Policy.QueueDecision}

# Verifies expired fifo head never dispatches.
law expired_fifo_head_never_dispatches:
  for fits_total: Bool
  for fits_available: Bool
  {Policy.tx.queue.decide(Policy.HeadPolicy{fits_total, fits_available,
    True{}}) == Policy.ExpireHead{} : Policy.QueueDecision}

# Verifies eligible fifo head dispatches.
law eligible_fifo_head_dispatches:
  {Policy.tx.queue.decide(Policy.HeadPolicy{True{}, True{}, False{}}) ==
    Policy.DispatchHead{} : Policy.QueueDecision}

# Verifies earlier cursor next keeps later admission pending.
law earlier_cursor_next_keeps_later_admission_pending:
  {Policy.tx.cursor.admission(True{}) ==
    Policy.WaitForEarlierCursorNext{} : Policy.CursorAdmissionDecision}

# Verifies unclaimed cursor next can be prepared.
law unclaimed_cursor_next_can_be_prepared:
  {Policy.tx.cursor.admission(False{}) ==
    Policy.PrepareCursorNext{} : Policy.CursorAdmissionDecision}

# Verifies get encoding peak includes live payload and frame.
law get_encoding_peak_includes_live_payload_and_frame:
  for value_bytes: Nat
  {Policy.tx.get.peak(value_bytes) ==
    Nat.add(Nat.mul(2n, value_bytes), 28n) : Nat}

# Verifies tx capacity fits a maximum response encoding peak.
law tx_capacity_fits_a_maximum_response_encoding_peak:
  for response_bytes: U32
  {Policy.tx.capacity(response_bytes) ==
    Nat.add(Nat.mul(2n, U32.to_nat(response_bytes)), 28n) : Nat}

# Verifies general response bound accounts for payload and frame.
law general_response_bound_accounts_for_payload_and_frame:
  for payload_bytes: U32
  {Policy.tx.response.bound(payload_bytes) ==
    Policy.Bounded{payload_bytes, Policy.tx.get.peak(
      U32.to_nat(payload_bytes))} : Policy.BoundDecision}

# Verifies payload bound rejects only when payload exceeds limit.
law payload_bound_rejects_only_when_payload_exceeds_limit:
  for payload_bytes: Nat
  for max_payload_bytes: U32
  {Policy.tx.payload.bound(payload_bytes, max_payload_bytes) ==
    Policy.tx.payload.bound.decided(payload_bytes,
      Nat.is_le(payload_bytes, U32.to_nat(max_payload_bytes))) :
      Policy.BoundDecision}

# Verifies fixed token bound accounts for token and frame.
law fixed_token_bound_accounts_for_token_and_frame:
  {Policy.tx.payload.bound(4n, 3) == Policy.TooLarge{} : Policy.BoundDecision}

# Verifies cursor bound uses retained root measurement.
law cursor_bound_uses_retained_root_measurement:
  for retained_bytes: Nat
  for response_bytes: U32
  {Policy.tx.cursor.bound(retained_bytes, response_bytes) ==
    Policy.tx.cursor.bound.required(
      Policy.tx.nat.duplicate(Nat.add(retained_bytes, 9n)),
      Policy.tx.u32.duplicate(response_bytes)) : Policy.BoundDecision}

# Verifies cursor bound rejects over limit fixture.
law cursor_bound_rejects_over_limit_fixture:
  {Policy.tx.cursor.bound(10n, 18) == Policy.TooLarge{} : Policy.BoundDecision}

# Verifies cursor bound reserves root peak fixture.
law cursor_bound_reserves_root_peak_fixture:
  {Policy.tx.cursor.bound(10n, 19) == Policy.Bounded{19, 66n} : Policy.BoundDecision}

# Verifies oversized get response is rejected before dispatch.
law oversized_get_response_is_rejected_before_dispatch:
  {Policy.tx.get.bound(1, 0, 0n) == Policy.TooLarge{} : Policy.BoundDecision}

# Verifies wait keeps the fifo queue owned and unchanged.
law wait_keeps_the_fifo_queue_owned_and_unchanged:
  for queue: Queue.Queue
  {Policy.tx.queue.reserve(queue,
    Policy.HeadPolicy{True{}, False{}, False{}}) ==
      Policy.QueueKeep{queue} : Policy.QueueReservation}

# Verifies head metadata supplies the reservation and absolute deadline.
law head_metadata_supplies_the_reservation_and_absolute_deadline:
  for connection_id: U32
  for accepted_sequence: Nat
  for deadline_ms: Nat
  for opcode: U32
  for request_bytes: Nat
  for response_peak: Nat
  for used: Nat
  for capacity: Nat
  for now: Nat
  {Policy.tx.queue.head.policy(Some{Queue.HeadMetadata{connection_id,
      accepted_sequence, deadline_ms, opcode, request_bytes, response_peak}},
    used, capacity, now) == Policy.tx.queue.decide.budget(used,
      response_peak, capacity, Nat.is_le(deadline_ms, now)) :
    Policy.QueueDecision}

# Verifies peek reservation applies head policy to the peeked queue.
law peek_reservation_applies_head_policy_to_the_peeked_queue:
  for queue: Queue.Queue
  for head: Maybe<&2, Queue.HeadMetadata>
  for used: Nat
  for capacity: Nat
  for now: Nat
  {Policy.tx.queue.reserve.peeked(Queue.PeekResult{queue, head}, used,
      capacity, now) == Policy.tx.queue.reserved(queue,
        Policy.tx.queue.head.policy(head, used, capacity, now)) :
    Policy.QueueReservation}

# Verifies empty get fits exact encoding peak.
law empty_get_fits_exact_encoding_peak:
  {Policy.tx.get.bound(0, 0, 28n) ==
    Policy.Bounded{0, 28n} : Policy.BoundDecision}

# Verifies empty get rejects one byte below encoding peak.
law empty_get_rejects_one_byte_below_encoding_peak:
  {Policy.tx.get.bound(0, 0, 27n) ==
    Policy.TooLarge{} : Policy.BoundDecision}

# Verifies one byte get accounts for both live buffers.
law one_byte_get_accounts_for_both_live_buffers:
  {Policy.tx.get.bound(1, 1, 30n) ==
    Policy.Bounded{1, 30n} : Policy.BoundDecision}
