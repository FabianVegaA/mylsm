import Base
import ../laws/Snapshot.bend as Laws

# Witnesses exact retention-budget acceptance.
def Laws.exact_retention_budget_is_accepted():
  {==}

# Witnesses rejection at the snapshot-count limit.
def Laws.snapshot_count_limit_is_rejected():
  {==}

# Witnesses rejection above the retained-byte limit.
def Laws.retained_byte_limit_is_rejected():
  {==}

def Laws.first_reservation_starts_aggregate_accounting():
  {==}

def Laws.later_reservation_accumulates_retained_bytes():
  {==}

def Laws.aggregate_retention_limit_rejects_later_reservation():
  {==}

def Laws.rejected_reservation_preserves_registry():
  {==}

def Laws.admitted_reservation_updates_registry():
  {==}

def Laws.snapshot_release_updates_registry():
  {==}

def Laws.snapshot_release_rejects_empty_registry():
  {==}

def Laws.snapshot_release_rejects_byte_underflow():
  {==}

def Laws.snapshot_close_preserves_registry_while_busy():
  {==}

def Laws.snapshot_close_releases_after_final_cursor():
  {==}

def Laws.repeated_snapshot_close_preserves_registry():
  {==}


def Laws.cursor_acquisition_increments_live_snapshot():
  {==}

def Laws.cursor_acquisition_rejects_closed_snapshot():
  {==}

def Laws.cursor_release_decrements_reference():
  {==}

def Laws.cursor_release_rejects_underflow():
  {==}

def Laws.snapshot_close_is_busy_with_live_cursors(cursor_count):
  match cursor_count:
    case 0n: {==}
    case 1n+rest: {==}

def Laws.snapshot_close_succeeds_after_final_cursor():
  {==}

def Laws.cursor_acquisition_increments_any_live_reference_count(cursor_count):
  match cursor_count:
    case 0n: {==}
    case 1n+rest: {==}

def Laws.cursor_release_decrements_any_positive_reference_count(cursor_count):
  match cursor_count:
    case 0n: {==}
    case 1n+rest: {==}

def Laws.compaction_retains_referenced_generation():
  {==}

def Laws.compaction_reclaims_unreferenced_generation():
  {==}

def Laws.generation_release_keeps_remaining_readers(references):
  match references:
    case 0n: {==}
    case 1n+rest: {==}

def Laws.generation_release_reclaims_final_reader():
  {==}

def Laws.generation_release_rejects_missing_reference():
  {==}

def Laws.publication_advances_generation_without_readers():
  {==}

def Laws.publication_retains_positive_generation_references(references):
  match references:
    case 0n: {==}
    case 1n+rest: {==}

def Laws.publication_prepends_to_retained_generations(references):
  match references:
    case 0n: {==}
    case 1n+rest: {==}

def Laws.publication_preserves_older_retained_generations():
  {==}

def Laws.pin_selected_retired_generation():
  {==}

def Laws.pin_missing_generation_preserves_registry():
  {==}

def Laws.release_final_retired_generation():
  {==}

def Laws.release_nonfinal_retired_generation():
  {==}

def Laws.release_missing_generation_preserves_registry():
  {==}
