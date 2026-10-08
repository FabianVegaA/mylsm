import Base
import ../src/DurableDbPolicy.bend as Policy
import ../src/DurableError.bend as DurableError

# Each returned operation error increments the handle counter.
law operation_error_count_increments:
  for count: Nat
  {Policy.next_operation_errors(count) == Nat.add(count, 1n) : Nat}

# A healthy handle accepts data operations.
law healthy_state_accepts_operations:
  {Policy.accepts_data_operation(Policy.Open{}) == True{} : Bool}

# A poisoned handle rejects data operations.
law poisoned_state_rejects_operations:
  {Policy.accepts_data_operation(Policy.Poisoned{}) == False{} : Bool}

# A failure after append starts poisons the handle.
law append_started_poisons_handle:
  {Policy.state_after_write_failure(Policy.AppendStarted{}, Policy.Open{}) == Policy.Poisoned{} : Policy.HandleState}

# A pre-append failure preserves handle state.
law pre_append_failure_preserves_handle_state:
  {Policy.state_after_write_failure(Policy.BeforeAppend{}, Policy.Open{}) == Policy.Open{} : Policy.HandleState}

# Failed maintenance blocks later writes.
law maintenance_failure_blocks_writes:
  {Policy.state_after_maintenance(Policy.MaintenanceFailed{DurableError.Error{DurableError.Io{}, "flush", "/db", 5, "disk"}}) == Policy.MaintenanceBlocked{} : Policy.HandleState}

# Maintenance failure does not revoke a confirmed commit.
law maintenance_does_not_unconfirm_commit:
  {Policy.committed_maintenance(None{}) == True{} : Bool}
