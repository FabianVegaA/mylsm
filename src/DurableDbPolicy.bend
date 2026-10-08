import Base
import ./DurableError.bend as DurableError

# Tracks whether the handle accepts data operations.
type HandleState is Data:
  Open{}
  Poisoned{}
  MaintenanceBlocked{}

# Increments the per-handle operation error count.
def next_operation_errors(count: Nat) -> Nat:
  Nat.add(count, 1n)

# Distinguishes failures before and after WAL append begins.
type AppendPhase is Data:
  BeforeAppend{}
  AppendStarted{}

# Tracks whether failed maintenance blocks later writes.
type MaintenanceState is Data:
  MaintenanceSucceeded{}
  MaintenanceFailed{error: DurableError.Error}

# Checks whether accepts data operation.
def accepts_data_operation(state: HandleState) -> Bool:
  match state:
    case Open{}:
      True{}
    case Poisoned{}:
      False{}
    case MaintenanceBlocked{}:
      False{}

# Selects handle state from the write failure stage.
def state_after_write_failure(phase: AppendPhase, current: HandleState) -> HandleState:
  match phase:
    case BeforeAppend{}:
      current
    case AppendStarted{}:
      Poisoned{}

# Blocks writes when maintenance fails.
def state_after_maintenance(result: MaintenanceState) -> HandleState:
  match result:
    case MaintenanceSucceeded{}:
      Open{}
    case MaintenanceFailed{_}:
      MaintenanceBlocked{}

# Reports maintenance separately from the confirmed commit.
def committed_maintenance(commit_error: Maybe<&2, DurableError.Error>) -> Bool:
  match commit_error:
    case Some{_}:
      False{}
    case None{}:
      True{}
