import Base
import ../src/coordinator/CoordinatorPolicy.bend as Policy

# Uses an acquired exclusive lock as the authority for local ownership.
law acquired_lock_selects_local_owner:
  {Policy.open.role(Policy.LockAcquired{}, Policy.EndpointMissing{}) ==
    Policy.LocalOwner{} : Policy.OpenRole}

# Selects the remote role only when contention and an endpoint agree.
law busy_lock_with_endpoint_selects_client:
  {Policy.open.role(Policy.LockBusy{}, Policy.EndpointPresent{}) ==
    Policy.ExistingOwnerClient{} : Policy.OpenRole}

# Keeps lock contention when no owner endpoint is published.
law busy_lock_without_endpoint_remains_busy:
  {Policy.open.role(Policy.LockBusy{}, Policy.EndpointMissing{}) ==
    Policy.ReturnBusy{} : Policy.OpenRole}

# Never interprets an endpoint inspection error as an owner.
law endpoint_inspection_failure_does_not_select_client:
  {Policy.open.role(Policy.LockBusy{}, Policy.EndpointFailed{}) ==
    Policy.PropagateOpenFailure{} : Policy.OpenRole}

# Propagates every lock failure without entering client mode.
law lock_failure_does_not_select_client:
  for endpoint: Policy.EndpointOutcome
  {Policy.open.role(Policy.LockFailed{}, endpoint) ==
    Policy.PropagateOpenFailure{} : Policy.OpenRole}

# Rejects endpoint publication while recovery is incomplete.
law owner_cannot_publish_before_recovery:
  {Policy.step(Policy.Locked{}, Policy.PublishEndpoint{}) == Policy.Reject{} : Policy.Decision}

# Allows endpoint publication after a locked recovery completes.
law owner_publishes_only_after_recovery:
  {Policy.step(Policy.Recovered{}, Policy.PublishEndpoint{}) == Policy.Advance{Policy.Serving{}} : Policy.Decision}

# Requires lock ownership before recovery can complete.
law recovery_requires_lock_ownership:
  {Policy.step(Policy.Starting{}, Policy.RecoveryComplete{}) == Policy.Reject{} : Policy.Decision}

# Rejects lock release while the endpoint may still admit clients.
law lock_release_requires_endpoint_removal:
  {Policy.step(Policy.Stopping{}, Policy.ReleaseLock{}) == Policy.Reject{} : Policy.Decision}

# Allows lock release only after endpoint removal.
law shutdown_removes_endpoint_before_lock_release:
  {Policy.step(Policy.EndpointRemoved{}, Policy.ReleaseLock{}) == Policy.Advance{Policy.Closed{}} : Policy.Decision}

# Keeps a closed owner terminal.
law closed_owner_does_not_restart:
  {Policy.step(Policy.Closed{}, Policy.AcquireLock{}) == Policy.Reject{} : Policy.Decision}

# Rejects every lifecycle event after the owner has entered a terminal failure.
law failed_owner_rejects_every_event:
  for event: Policy.OwnerEvent
  {Policy.step(Policy.Failed{}, event) == Policy.Reject{} : Policy.Decision}

# Keeps a closed owner terminal for every lifecycle event.
law closed_owner_rejects_every_event:
  for event: Policy.OwnerEvent
  {Policy.step(Policy.Closed{}, event) == Policy.Reject{} : Policy.Decision}

# Maps owner contention into the protocol's Busy response.
law busy_failure_keeps_backpressure_status:
  {Policy.failure.status(Policy.BusyFailure{}) == Policy.BusyStatus{} : Policy.ReplyStatus}

# Preserves timeout as a distinct public coordinator status.
law timeout_failure_keeps_timeout_status:
  {Policy.failure.status(Policy.TimeoutFailure{}) == Policy.TimeoutStatus{} : Policy.ReplyStatus}

# Maps a missing key or resource into the NotFound status.
law not_found_failure_keeps_absence_status:
  {Policy.failure.status(Policy.NotFoundFailure{}) == Policy.NotFoundStatus{} : Policy.ReplyStatus}

# Preserves invalid caller input as InvalidArgument.
law invalid_argument_failure_keeps_input_status:
  {Policy.failure.status(Policy.InvalidArgumentFailure{}) == Policy.InvalidArgumentStatus{} : Policy.ReplyStatus}

# Maps destination conflicts into AlreadyExists.
law already_exists_failure_keeps_conflict_status:
  {Policy.failure.status(Policy.AlreadyExistsFailure{}) == Policy.AlreadyExistsStatus{} : Policy.ReplyStatus}

# Preserves unsupported socket capability in its typed status.
law unsupported_platform_failure_maps_to_io_status:
  {Policy.failure.status(Policy.UnsupportedPlatformFailure{}) == Policy.UnsupportedPlatformStatus{} : Policy.ReplyStatus}

# Maps bounded-resource exhaustion into ResourceLimit.
law resource_limit_failure_keeps_limit_status:
  {Policy.failure.status(Policy.ResourceLimitFailure{}) == Policy.ResourceLimitStatus{} : Policy.ReplyStatus}

# Preserves stored-data corruption as a corruption response.
law corruption_failure_keeps_corruption_status:
  {Policy.failure.status(Policy.CorruptionFailure{}) == Policy.CorruptionStatus{} : Policy.ReplyStatus}

# Maps ordinary host failures into the generic IO status.
law io_failure_keeps_io_status:
  {Policy.failure.status(Policy.IoFailure{}) == Policy.IoStatus{} : Policy.ReplyStatus}

# Preserves uncertain mutation completion as CommitUnknown.
law uncertain_commit_keeps_uncertain_status:
  {Policy.failure.status(Policy.CommitUnknownFailure{}) == Policy.CommitUnknownStatus{} : Policy.ReplyStatus}
