import Base
import ../laws/CoordinatorPolicy.bend as Laws
import ../src/coordinator/CoordinatorPolicy.bend as Policy

def Laws.acquired_lock_selects_local_owner():
  {==}

def Laws.busy_lock_with_endpoint_selects_client():
  {==}

def Laws.busy_lock_without_endpoint_remains_busy():
  {==}

def Laws.endpoint_inspection_failure_does_not_select_client():
  {==}

def Laws.lock_failure_does_not_select_client(endpoint):
  match endpoint:
    case Policy.EndpointPresent{}: {==}
    case Policy.EndpointMissing{}: {==}
    case Policy.EndpointFailed{}: {==}

def Laws.owner_cannot_publish_before_recovery():
  {==}

def Laws.owner_publishes_only_after_recovery():
  {==}

def Laws.recovery_requires_lock_ownership():
  {==}

def Laws.lock_release_requires_endpoint_removal():
  {==}

def Laws.shutdown_removes_endpoint_before_lock_release():
  {==}

def Laws.closed_owner_does_not_restart():
  {==}

def Laws.failed_owner_rejects_every_event(event):
  match event:
    case Policy.AcquireLock{}: {==}
    case Policy.RecoveryComplete{}: {==}
    case Policy.PublishEndpoint{}: {==}
    case Policy.BeginShutdown{}: {==}
    case Policy.RemoveEndpoint{}: {==}
    case Policy.ReleaseLock{}: {==}
    case Policy.Failure{}: {==}

def Laws.closed_owner_rejects_every_event(event):
  match event:
    case Policy.AcquireLock{}: {==}
    case Policy.RecoveryComplete{}: {==}
    case Policy.PublishEndpoint{}: {==}
    case Policy.BeginShutdown{}: {==}
    case Policy.RemoveEndpoint{}: {==}
    case Policy.ReleaseLock{}: {==}
    case Policy.Failure{}: {==}

def Laws.busy_failure_keeps_backpressure_status():
  {==}

def Laws.timeout_failure_keeps_timeout_status():
  {==}

def Laws.not_found_failure_keeps_absence_status():
  {==}

def Laws.invalid_argument_failure_keeps_input_status():
  {==}

def Laws.already_exists_failure_keeps_conflict_status():
  {==}

def Laws.unsupported_platform_failure_maps_to_io_status():
  {==}

def Laws.resource_limit_failure_keeps_limit_status():
  {==}

def Laws.corruption_failure_keeps_corruption_status():
  {==}

def Laws.io_failure_keeps_io_status():
  {==}

def Laws.uncertain_commit_keeps_uncertain_status():
  {==}
