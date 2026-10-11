import Base

# Reports whether the requested snapshot fits the retained-resource limits.
type Decision is Data:
  Retained{snapshot_count: Nat, retained_bytes: Nat}
  ResourceLimit{}

# Holds the aggregate reservation counters for one database owner.
type Registry is Data:
  Registry{snapshot_count: Nat, retained_bytes: Nat}

# Returns the updated registry or its unchanged prior state after rejection.
type RegistryDecision is Data:
  Admitted{registry: Registry}
  Rejected{registry: Registry}

# Reports a snapshot release or preserves the registry on invalid release.
type RegistryReleaseDecision is Data:
  Released{registry: Registry}
  InvalidRelease{registry: Registry}

# Couples snapshot closure to child checks and aggregate reservation release.
type SnapshotCloseDecision is Data:
  SnapshotClosed{registry: Registry}
  SnapshotBusy{registry: Registry}
  InvalidSnapshotClose{registry: Registry}

# Tracks whether a snapshot is open and how many cursors still reference it.
type Lifecycle is Data:
  Live{cursor_count: Nat}
  Closed{}

# Reports a lifecycle transition, a live-child conflict, or an invalid action.
type LifecycleDecision is Data:
  Advanced{lifecycle: Lifecycle}
  Busy{}
  Invalid{}

# Reports a published generation and whether its predecessor remains retained.
type GenerationDecision is Data:
  Published{current: Nat, retired: RetiredGeneration}

# Represents one older SST generation while snapshots still reference it.
type RetiredGeneration is Data:
  NoRetained{}
  GenerationRetained{generation: Nat, bytes: Nat, references: Nat}

# Reports whether releasing a generation reference keeps or reclaims its files.
type RetentionDecision is Data:
  Keep{generation: Nat, bytes: Nat, references: Nat}
  Reclaim{generation: Nat, bytes: Nat}
  InvalidReference{}

# Produces the updated reservation only when both bounds admit it.
def reserve.result(
  count: Nat,
  retained_bytes: Nat,
  admitted: Bool & Bool
) -> Decision:
  match admitted:
    case (True{}, True{}):
      Retained{Nat.add(count, 1n), retained_bytes}
    case _:
      ResourceLimit{}

# Increments both copies of a recursively duplicated natural number.
def nat.duplicate.step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (left, right): (Nat.add(1n, left), Nat.add(1n, right))

# Creates two equal natural numbers without reusing an affine value.
def nat.duplicate(value: Nat) -> Nat & Nat:
  match value:
    case 0n: (0n, 0n)
    case 1n+rest: nat.duplicate.step(nat.duplicate(rest))

# Computes the updated retained-byte total and both admission checks.
def reserve.bytes(
  retained: Nat & Nat,
  requested: Nat & Nat,
  snapshot_count: Nat & Nat,
  max_snapshots: Nat,
  max_retained_bytes: Nat
) -> Nat & (Nat & (Bool & Bool)):
  match retained:
    case (retained_value, retained_check):
      match requested:
        case (requested_value, requested_check):
          match snapshot_count:
            case (count_output, count_check):
              (count_output,
                (Nat.add(retained_value, requested_value),
                  (Nat.is_lt(count_check, max_snapshots),
                  Nat.is_le(Nat.add(retained_check, requested_check), max_retained_bytes))))

# Unpacks the reservation calculation into its public decision.
def reserve.result.checked(pair: Nat & (Nat & (Bool & Bool))) -> Decision:
  match pair:
    case (count, (retained_bytes, admitted)):
      reserve.result(count, retained_bytes, admitted)

# Decides whether one snapshot fits the configured count and byte limits.
def reserve(
  snapshot_count: Nat,
  retained_bytes: Nat,
  requested_bytes: Nat,
  max_snapshots: Nat,
  max_retained_bytes: Nat
) -> Decision:
  reserve.result.checked(reserve.bytes(nat.duplicate(retained_bytes),
    nat.duplicate(requested_bytes), nat.duplicate(snapshot_count), max_snapshots,
    max_retained_bytes))

# Preserves the prior registry when a reservation fails either configured bound.
def registry.reserve.result(original: Registry, decision: Decision) -> RegistryDecision:
  match decision:
    case Retained{snapshot_count, retained_bytes}:
      Admitted{Registry{snapshot_count, retained_bytes}}
    case ResourceLimit{}: Rejected{original}

# Applies a reservation decision while keeping a copy of the prior counters.
def registry.reserve.input(
  copies: (Nat & Nat) & (Nat & Nat),
  requested_bytes: Nat,
  max_snapshots: Nat,
  max_retained_bytes: Nat
) -> RegistryDecision:
  match copies:
    case ((count_input, count_original), (bytes_input, bytes_original)):
      registry.reserve.result(Registry{count_original, bytes_original},
      reserve(count_input, bytes_input, requested_bytes,
          max_snapshots, max_retained_bytes))

# Duplicates the byte counter so an admitted decision can update while rejection preserves it.
def registry.reserve.count(
  count_copies: Nat & Nat,
  retained_bytes: Nat,
  requested_bytes: Nat,
  max_snapshots: Nat,
  max_retained_bytes: Nat
) -> RegistryDecision:
  match count_copies:
    case (count_input, count_original):
      registry.reserve.input(((count_input, count_original),
        nat.duplicate(retained_bytes)), requested_bytes,
        max_snapshots, max_retained_bytes)

# Reserves one snapshot against the aggregate counters and preserves state on rejection.
def registry.reserve(
  registry: Registry,
  requested_bytes: Nat,
  max_snapshots: Nat,
  max_retained_bytes: Nat
) -> RegistryDecision:
  match registry:
    case Registry{snapshot_count, retained_bytes}:
      registry.reserve.count(nat.duplicate(snapshot_count), retained_bytes,
        requested_bytes, max_snapshots, max_retained_bytes)

# Keeps the original counters when release preconditions do not hold.
def registry.release.result(
  counters: Nat & Nat,
  original: Registry,
  admitted: Bool & Bool
) -> RegistryReleaseDecision:
  match counters:
    case (snapshot_count, retained_bytes):
      match admitted:
        case (True{}, True{}):
          Released{Registry{snapshot_count, retained_bytes}}
        case _: InvalidRelease{original}

# Separates byte arithmetic inputs so both admission checks retain their values.
def registry.release.input.bytes(
  count_copies: Nat & Nat,
  count_original: Nat,
  bytes_copies: Nat & Nat,
  bytes_original: Nat,
  release_copies: Nat & Nat
) -> RegistryReleaseDecision:
  match count_copies:
    case (count_for_subtract, count_for_check):
      match bytes_copies:
        case (bytes_for_subtract, bytes_for_check):
          match release_copies:
            case (released_for_subtract, released_for_check):
              registry.release.result(
                (Nat.sub(count_for_subtract, 1n),
                  Nat.sub(bytes_for_subtract, released_for_subtract)),
                Registry{count_original, bytes_original},
                (Nat.is_lt(0n, count_for_check),
                  Nat.is_le(released_for_check, bytes_for_check)))

# Validates positive snapshot ownership and sufficient retained bytes before decrementing.
def registry.release.input(
  copies: (Nat & Nat) & (Nat & Nat),
  released_bytes: Nat
) -> RegistryReleaseDecision:
  match copies:
    case ((count_input, count_original), (bytes_input, bytes_original)):
      registry.release.input.bytes(nat.duplicate(count_input), count_original,
        nat.duplicate(bytes_input), bytes_original,
        nat.duplicate(released_bytes))

# Duplicates the counters so invalid releases preserve the exact prior registry.
def registry.release.count(
  count_copies: Nat & Nat,
  retained_bytes: Nat,
  released_bytes: Nat
) -> RegistryReleaseDecision:
  match count_copies:
    case (count_input, count_original):
      registry.release.input(((count_input, count_original),
        nat.duplicate(retained_bytes)), released_bytes)

# Releases one closed snapshot's reservation without changing active readers.
def registry.release(registry: Registry, released_bytes: Nat) -> RegistryReleaseDecision:
  match registry:
    case Registry{snapshot_count, retained_bytes}:
      registry.release.count(nat.duplicate(snapshot_count), retained_bytes,
        released_bytes)

# Maps a valid registry release to successful snapshot closure.
def snapshot.close.registry(decision: RegistryReleaseDecision) -> SnapshotCloseDecision:
  match decision:
    case Released{registry}: SnapshotClosed{registry}
    case InvalidRelease{registry}: InvalidSnapshotClose{registry}

# Leaves registry accounting untouched while a cursor still references the snapshot.
def snapshot.close(
  lifecycle: Lifecycle,
  registry: Registry,
  released_bytes: Nat
) -> SnapshotCloseDecision:
  match lifecycle:
    case Closed{}: InvalidSnapshotClose{registry}
    case Live{cursor_count}:
      match cursor_count:
        case 0n:
          snapshot.close.registry(registry.release(registry, released_bytes))
        case 1n+rest: SnapshotBusy{registry}

# Adds a cursor reference to an open snapshot.
def cursor.acquire(lifecycle: Lifecycle) -> LifecycleDecision:
  match lifecycle:
    case Live{cursor_count}: Advanced{Live{Nat.add(cursor_count, 1n)}}
    case Closed{}: Invalid{}

# Releases one cursor reference, rejecting underflow and closed snapshots.
def cursor.release(lifecycle: Lifecycle) -> LifecycleDecision:
  match lifecycle:
    case Live{cursor_count}:
      match cursor_count:
        case 0n: Invalid{}
        case 1n+rest: Advanced{Live{rest}}
    case Closed{}: Invalid{}

# Closes a snapshot only after its final cursor reference has been released.
def close(lifecycle: Lifecycle) -> LifecycleDecision:
  match lifecycle:
    case Live{cursor_count}:
      match cursor_count:
        case 0n: Advanced{Closed{}}
        case 1n+rest: Busy{}
    case Closed{}: Invalid{}

# Publishes a generation from independent copies of its current identifier.
def publish_generation.copied(
  copies: Nat & Nat,
  current_bytes: Nat,
  references: Nat
) -> GenerationDecision:
  match copies:
    case (next_source, retained_source):
      match references:
        case 0n: Published{Nat.add(next_source, 1n), NoRetained{}}
        case 1n+rest:
          Published{Nat.add(next_source, 1n),
            GenerationRetained{retained_source, current_bytes, 1n+rest}}

# Publishes a new current generation and retains its predecessor while referenced.
def publish_generation(
  current: Nat,
  current_bytes: Nat,
  references: Nat
) -> GenerationDecision:
  publish_generation.copied(nat.duplicate(current), current_bytes, references)

# Releases one reference and reclaims a retired generation after its final reader.
def release_generation(retired: RetiredGeneration) -> RetentionDecision:
  match retired:
    case NoRetained{}: InvalidReference{}
    case GenerationRetained{generation, bytes, references}:
      match references:
        case 0n: InvalidReference{}
        case 1n: Reclaim{generation, bytes}
        case 1n+rest: Keep{generation, bytes, rest}
