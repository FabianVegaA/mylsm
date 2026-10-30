import Base
import ../laws/ConnectionPolicy.bend as Laws

def Laws.before_deadline_continues():
  {==}

def Laws.at_deadline_expires():
  {==}

def Laws.after_deadline_expires():
  {==}

def Laws.saturated_admission_maps_to_busy():
  {==}

def Laws.oversized_admission_maps_to_resource_limit():
  {==}

def Laws.poll_timeout_without_connections_uses_idle_bound():
  {==}

def Laws.poll_timeout_with_connections_uses_shortest_bound():
  {==}

def Laws.active_queue_waits_for_event_or_deadline(
  _frame_timeout_ms, _response_timeout_ms, _queue_timeout_ms
):
  {==}

def Laws.connection_slot_is_available_below_limit():
  {==}

def Laws.connection_limit_is_full_at_boundary():
  {==}

def Laws.connection_limit_stays_full_after_boundary():
  {==}

def Laws.connection_id_is_available_before_u32_exhaustion():
  {==}

def Laws.connection_id_exhaustion_never_wraps_to_zero():
  {==}

def Laws.partial_write_advances_only_completed_bytes():
  {==}

def Laws.write_progress_rejects_offset_past_total():
  {==}

def Laws.write_progress_rejects_count_overrun():
  {==}

def Laws.maximum_u32_offset_rejects_addition_overflow():
  {==}

def Laws.write_at_total_waits_without_advance():
  {==}

def Laws.read_chunk_minimum_is_below_frame(cap, frame_remaining,
  rx_available):
  match cap:
    case 0n:
      match frame_remaining:
        case 0n: {==}
        case 1n+_: {==}
    case 1n+cap_rest:
      match frame_remaining:
        case 0n: {==}
        case 1n+frame_rest:
          match rx_available:
            case 0n: {==}
            case 1n+rx_rest:
              Laws.read_chunk_minimum_is_below_frame(cap_rest,
                frame_rest, rx_rest)

def Laws.read_chunk_minimum_is_below_rx_capacity(cap, frame_remaining,
  rx_available):
  match cap:
    case 0n:
      match frame_remaining:
        case 0n:
          match rx_available:
            case 0n: {==}
            case 1n+_: {==}
        case 1n+_:
          match rx_available:
            case 0n: {==}
            case 1n+_: {==}
    case 1n+cap_rest:
      match frame_remaining:
        case 0n:
          match rx_available:
            case 0n: {==}
            case 1n+_: {==}
        case 1n+frame_rest:
          match rx_available:
            case 0n: {==}
            case 1n+rx_rest:
              Laws.read_chunk_minimum_is_below_rx_capacity(cap_rest,
                frame_rest, rx_rest)

def Laws.read_chunk_minimum_is_below_cap(cap, frame_remaining,
  rx_available):
  match cap:
    case 0n: {==}
    case 1n+cap_rest:
      match frame_remaining:
        case 0n: {==}
        case 1n+frame_rest:
          match rx_available:
            case 0n: {==}
            case 1n+rx_rest:
              Laws.read_chunk_minimum_is_below_cap(cap_rest,
                frame_rest, rx_rest)

def Laws.read_chunk_never_exceeds_remaining_frame(frame_remaining,
  rx_available):
  Laws.read_chunk_minimum_is_below_frame(65536n, frame_remaining,
    rx_available)

def Laws.read_chunk_never_exceeds_aggregate_rx_capacity(frame_remaining,
  rx_available):
  Laws.read_chunk_minimum_is_below_rx_capacity(65536n, frame_remaining,
    rx_available)

def Laws.read_chunk_is_bounded_to_sixty_four_kib(frame_remaining,
  rx_available):
  Laws.read_chunk_minimum_is_below_cap(65536n, frame_remaining,
    rx_available)

def Laws.zero_write_progress_preserves_offset():
  {==}

def Laws.complete_header_admits_its_declared_frame_size():
  {==}

def Laws.split_header_chunks_preserve_declared_frame_size():
  {==}

def Laws.split_payload_chunks_decode_one_request():
  {==}

def Laws.payload_chunk_cannot_exceed_declared_length():
  {==}

def Laws.empty_payload_completes_without_another_read():
  {==}
