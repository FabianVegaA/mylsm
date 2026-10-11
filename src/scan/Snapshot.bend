import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

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

# Tracks one published SST generation and its live reader references.
type FileGeneration is Data:
  FileGeneration{id: Nat, size: Nat, references: Nat}

# Keeps the current generation separate from all reader-retained generations.
type GenerationRegistry is Data:
  GenerationRegistry{current: FileGeneration,
    retired: List<&2, FileGeneration>}

# Reports a successful generation pin or preserves the registry on a missing identifier.
type GenerationPinDecision is Data:
  Pinned{registry: GenerationRegistry}
  MissingGeneration{registry: GenerationRegistry}

# Reports an incremented reader count for a located retired generation.
type RetiredPin is Data:
  RetiredPinned{retired: List<&2, FileGeneration>}
  RetiredPinMissing{retired: List<&2, FileGeneration>}

# Reports a retained, reclaimed, or missing retired generation during release.
type RetiredRelease is Data:
  RetiredReleased{retired: List<&2, FileGeneration>}
  RetiredReclaimed{retired: List<&2, FileGeneration>, number: Nat, bytes: Nat}
  RetiredMissing{retired: List<&2, FileGeneration>}

# Reports a decremented reference or identifies files reclaimed after the last reader.
type GenerationReleaseDecision is Data:
  GenerationReleased{registry: GenerationRegistry}
  GenerationReclaimed{registry: GenerationRegistry, number: Nat, bytes: Nat}
  MissingReference{registry: GenerationRegistry}

# Carries the next owner resource identifier and terminal exhaustion state.
type ResourceIdAllocator is Data:
  ResourceIdAllocator{next_id: U32, exhausted: Bool}

# Reports an allocated owner identifier or preserves an exhausted allocator.
type ResourceIdDecision is Data:
  ResourceIdAllocated{id: U32, allocator: ResourceIdAllocator}
  ResourceIdExhausted{allocator: ResourceIdAllocator}

# Associates each owner-managed snapshot identifier with its generation and children.
type SnapshotResource is Data:
  SnapshotResource{id: U32, generation: Nat, retained_bytes: Nat,
    cursor_count: Nat}

# Holds aggregate snapshot reservations and their owner-issued identifiers.
type OwnerRegistry is Data:
  OwnerRegistry{allocator: ResourceIdAllocator, reservations: Registry,
    snapshots: List<&2, SnapshotResource>}

# Reports an admitted owner snapshot or the exact registry after rejection.
type OwnerOpenDecision is Data:
  OwnerSnapshotOpened{registry: OwnerRegistry, snapshot_id: U32}
  OwnerSnapshotRejected{registry: OwnerRegistry}

# Reports a snapshot cursor-reference update or preserves its prior resource.
type SnapshotCursorDecision is Data:
  SnapshotCursorAcquired{resource: SnapshotResource}
  SnapshotCursorLimit{resource: SnapshotResource}
  SnapshotCursorReleased{resource: SnapshotResource}
  SnapshotCursorUnderflow{resource: SnapshotResource}



def nat.duplicate.step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (left, right): (Nat.add(1n, left), Nat.add(1n, right))

def nat.duplicate(value: Nat) -> Nat & Nat:
  match value:
    case 0n: (0n, 0n)
    case 1n+rest: nat.duplicate.step(nat.duplicate(rest))

def allocate_resource_id.maximum(
  next_ids: U32 & U32,
  at_max: Bool
) -> ResourceIdDecision:
  match next_ids:
    case (next_id, increment_id):
      match at_max:
        case True{}:
          ResourceIdAllocated{next_id,
            ResourceIdAllocator{increment_id, True{}}}
        case False{}:
          ResourceIdAllocated{next_id,
            ResourceIdAllocator{U32.add(increment_id, 1), False{}}}

def u32.bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

def u32.clone.pair.results(
  results: (Bytes.Bytes & Maybe<&2, U32>) & (Bytes.Bytes & Maybe<&2, U32>)
) -> U32 & U32:
  match results:
    case ((_, Some{first}), (_, Some{second})): (first, second)
    case _: (0, 0)

def u32.clone.pair.bytes(bytes: Bytes.Bytes & Bytes.Bytes) -> U32 & U32:
  match bytes:
    case (left, right):
      u32.clone.pair.results((Bytes.get.u32be(left, 0),
        Bytes.get.u32be(right, 0)))

def u32.clone.pair.buffers(
  +len: U32,
  buffers: Array<U32> & Array<U32>
) -> U32 & U32:
  match buffers:
    case (left, right):
      u32.clone.pair.bytes((Bytes.Bytes{len, left}, Bytes.Bytes{len, right}))

def u32.duplicate.encoded(bytes: Bytes.Bytes) -> U32 & U32:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      u32.clone.pair.buffers(len,
        Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

def u32.duplicate(value: U32) -> U32 & U32:
  u32.duplicate.encoded(u32.bytes(value))

def allocate_resource_id.at_limit(
  copies: U32 & U32,
  exhausted: Bool
) -> ResourceIdDecision:
  match copies:
    case (next_id, check_id):
      match exhausted:
        case True{}:
          ResourceIdExhausted{ResourceIdAllocator{next_id, exhausted}}
        case False{}:
          allocate_resource_id.maximum(u32.duplicate(next_id),
            U32.is_eq(check_id, 4294967295))

# Allocates one nonrecycled owner resource identifier without integer wraparound.
def allocate_resource_id(
  allocator: ResourceIdAllocator
) -> ResourceIdDecision:
  match allocator:
    case ResourceIdAllocator{next_id, exhausted}:
      allocate_resource_id.at_limit(u32.duplicate(next_id), exhausted)

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

def owner.snapshot.open.release(
  allocator: ResourceIdAllocator,
  snapshots: List<&2, SnapshotResource>,
  decision: RegistryReleaseDecision
) -> OwnerOpenDecision:
  match decision:
    case Released{reservations}:
      OwnerSnapshotRejected{OwnerRegistry{allocator, reservations, snapshots}}
    case InvalidRelease{reservations}:
      OwnerSnapshotRejected{OwnerRegistry{allocator, reservations, snapshots}}

def owner.snapshot.open.created(
  ids: U32 & U32,
  allocator: ResourceIdAllocator,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  generation: Nat,
  retained_bytes: Nat
) -> OwnerOpenDecision:
  match ids:
    case (snapshot_id, entry_id):
      OwnerSnapshotOpened{OwnerRegistry{allocator, reservations,
        Con{SnapshotResource{entry_id, generation, retained_bytes, 0n}, snapshots}},
        snapshot_id}

def owner.snapshot.open.id(
  allocation: ResourceIdDecision,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  generation: Nat,
  retained_bytes: Nat
) -> OwnerOpenDecision:
  match allocation:
    case ResourceIdAllocated{id, allocator}:
      owner.snapshot.open.created(u32.duplicate(id), allocator, reservations,
        snapshots, generation, retained_bytes)
    case ResourceIdExhausted{allocator}:
      owner.snapshot.open.release(allocator, snapshots,
        registry.release(reservations, retained_bytes))

def owner.snapshot.open.reserved(
  allocator: ResourceIdAllocator,
  snapshots: List<&2, SnapshotResource>,
  generation: Nat,
  requests: Nat & Nat,
  decision: RegistryDecision
) -> OwnerOpenDecision:
  match requests:
    case (retained_bytes, release_bytes):
      match decision:
        case Admitted{reservations}:
          owner.snapshot.open.id(allocate_resource_id(allocator), reservations,
            snapshots, generation, release_bytes)
        case Rejected{reservations}:
          OwnerSnapshotRejected{OwnerRegistry{allocator, reservations, snapshots}}

def owner.snapshot.open.budget(
  allocator: ResourceIdAllocator,
  snapshots: List<&2, SnapshotResource>,
  generation: Nat,
  requested_bytes: Nat & Nat,
  release_bytes: Nat,
  limits: Nat & Nat,
  reservations: Registry
) -> OwnerOpenDecision:
  match requested_bytes:
    case (retained_for_entry, retained_for_admission):
      match limits:
        case (max_snapshots, max_retained_bytes):
          owner.snapshot.open.reserved(allocator, snapshots, generation,
            (retained_for_entry, release_bytes),
            registry.reserve(reservations, retained_for_admission,
              max_snapshots, max_retained_bytes))

def owner.snapshot.open.available(
  allocator: ResourceIdAllocator,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  generation: Nat,
  requests: Nat & Nat,
  limits: Nat & Nat
) -> OwnerOpenDecision:
  match allocator:
    case ResourceIdAllocator{next_id, exhausted}:
      match exhausted:
        case True{}:
          OwnerSnapshotRejected{OwnerRegistry{allocator, reservations, snapshots}}
        case False{}:
          match requests:
            case (requested_bytes, release_bytes):
              owner.snapshot.open.budget(allocator, snapshots, generation,
                nat.duplicate(requested_bytes), release_bytes, limits,
                reservations)

def owner.snapshot.open(
  owner: OwnerRegistry,
  generation: Nat,
  requested_bytes: Nat,
  limits: Nat & Nat
) -> OwnerOpenDecision:
  match owner:
    case OwnerRegistry{allocator, reservations, snapshots}:
      owner.snapshot.open.available(allocator, reservations, snapshots,
        generation, nat.duplicate(requested_bytes), limits)

def snapshot.resource.duplicate.parts(
  ids: U32 & U32,
  generations: Nat & Nat,
  retained: Nat & Nat,
  cursors: Nat & Nat
) -> SnapshotResource & SnapshotResource:
  match ids:
    case (first_id, second_id):
      match generations:
        case (first_generation, second_generation):
          match retained:
            case (first_bytes, second_bytes):
              match cursors:
                case (first_count, second_count):
                  (SnapshotResource{first_id, first_generation, first_bytes,
                    first_count}, SnapshotResource{second_id, second_generation,
                    second_bytes, second_count})

def snapshot.resource.duplicate(resource: SnapshotResource) -> SnapshotResource & SnapshotResource:
  match resource:
    case SnapshotResource{id, generation, retained_bytes, cursor_count}:
      snapshot.resource.duplicate.parts(u32.duplicate(id),
        nat.duplicate(generation), nat.duplicate(retained_bytes),
        nat.duplicate(cursor_count))

def snapshot.resource.cursor.acquire.result(
  resource: SnapshotResource,
  admitted: Bool
) -> SnapshotCursorDecision:
  match resource:
    case SnapshotResource{id, generation, retained_bytes, cursor_count}:
      match admitted:
        case True{}:
          SnapshotCursorAcquired{SnapshotResource{id, generation,
            retained_bytes, Nat.add(cursor_count, 1n)}}
        case False{}: SnapshotCursorLimit{resource}

def snapshot.resource.cursor.acquire.checked(
  resource: SnapshotResource,
  cursor_count: Nat,
  max_cursors: Nat
) -> SnapshotCursorDecision:
  snapshot.resource.cursor.acquire.result(resource,
    Nat.is_lt(cursor_count, max_cursors))

def snapshot.resource.cursor.acquire.copied(
  copies: SnapshotResource & SnapshotResource,
  max_cursors: Nat
) -> SnapshotCursorDecision:
  match copies:
    case (for_check, for_update):
      match for_check:
        case SnapshotResource{_, _, _, cursor_count}:
          snapshot.resource.cursor.acquire.checked(for_update, cursor_count,
            max_cursors)

# Acquires one child reference without changing a snapshot at its cursor limit.
def snapshot.resource.cursor.acquire(
  resource: SnapshotResource,
  max_cursors: Nat
) -> SnapshotCursorDecision:
  snapshot.resource.cursor.acquire.copied(
    snapshot.resource.duplicate(resource), max_cursors)

def snapshot.resource.cursor.release.result(
  resource: SnapshotResource,
  has_reference: Bool
) -> SnapshotCursorDecision:
  match resource:
    case SnapshotResource{id, generation, retained_bytes, cursor_count}:
      match has_reference:
        case True{}:
          SnapshotCursorReleased{SnapshotResource{id, generation,
            retained_bytes, Nat.sub(cursor_count, 1n)}}
        case False{}: SnapshotCursorUnderflow{resource}

def snapshot.resource.cursor.release.checked(
  resource: SnapshotResource,
  cursor_count: Nat
) -> SnapshotCursorDecision:
  snapshot.resource.cursor.release.result(resource,
    Nat.is_lt(0n, cursor_count))

def snapshot.resource.cursor.release.copied(
  copies: SnapshotResource & SnapshotResource
) -> SnapshotCursorDecision:
  match copies:
    case (for_check, for_update):
      match for_check:
        case SnapshotResource{_, _, _, cursor_count}:
          snapshot.resource.cursor.release.checked(for_update, cursor_count)

# Releases one child reference and preserves the resource on underflow.
def snapshot.resource.cursor.release(
  resource: SnapshotResource
) -> SnapshotCursorDecision:
  snapshot.resource.cursor.release.copied(
    snapshot.resource.duplicate(resource))

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

def publish.registry.current(
  current: FileGeneration,
  retired: List<&2, FileGeneration>,
  next_bytes: Nat
) -> GenerationRegistry:
  match current:
    case FileGeneration{+id, +size, references}:
      match references:
        case 0n:
          GenerationRegistry{FileGeneration{Nat.add(id, 1n),
            next_bytes, 0n}, retired}
        case 1n+rest:
          GenerationRegistry{FileGeneration{Nat.add(id, 1n),
            next_bytes, 0n}, Con{FileGeneration{id, size, 1n+rest}, retired}}

def publish.registry(
  registry: GenerationRegistry,
  next_bytes: Nat
) -> GenerationRegistry:
  match registry:
    case GenerationRegistry{current, retired}:
      publish.registry.current(current, retired, next_bytes)

def pin.retired.prepend(
  id: Nat,
  size: Nat,
  references: Nat,
  result: RetiredPin
) -> RetiredPin:
  match result:
    case RetiredPinned{retired}:
      RetiredPinned{Con{FileGeneration{id, size, references}, retired}}
    case RetiredPinMissing{retired}:
      RetiredPinMissing{Con{FileGeneration{id, size, references}, retired}}

def pin.retired.loop(
  retired: List<&2, FileGeneration>,
  +target: Nat,
  matches: Bool
) -> RetiredPin:
  match retired:
    case Nil{}: RetiredPinMissing{Nil{}}
    case Con{FileGeneration{+id, +size, +references}, Nil{}}:
      match matches:
        case True{}:
          RetiredPinned{Con{FileGeneration{id, size,
            Nat.add(references, 1n)}, Nil{}}}
        case False{}:
          RetiredPinMissing{Con{FileGeneration{id, size,
            references}, Nil{}}}
    case Con{FileGeneration{+id, +size, +references},
        Con{FileGeneration{+next_id, +next_size, +next_references}, rest}}:
      match matches:
        case True{}:
          RetiredPinned{Con{FileGeneration{id, size,
            Nat.add(references, 1n)},
            Con{FileGeneration{next_id, next_size, next_references}, rest}}}
        case False{}:
          pin.retired.prepend(id, size, references,
            pin.retired.loop(Con{FileGeneration{next_id, next_size,
              next_references}, rest}, target,
              Nat.is_eq(next_id, target)))

def pin.retired(
  +retired: List<&2, FileGeneration>,
  +target: Nat
) -> RetiredPin:
  match retired:
    case Nil{}: RetiredPinMissing{Nil{}}
    case Con{generation, _}:
      match generation:
        case FileGeneration{+id, _, _}:
          pin.retired.loop(retired, target, Nat.is_eq(id, target))

def pin.registry.retired(
  id: Nat,
  size: Nat,
  references: Nat,
  retired: RetiredPin
) -> GenerationPinDecision:
  match retired:
    case RetiredPinned{retired}:
      Pinned{GenerationRegistry{FileGeneration{id, size, references}, retired}}
    case RetiredPinMissing{retired}:
      MissingGeneration{GenerationRegistry{FileGeneration{id, size,
        references}, retired}}

def pin.registry.decision(
  +id: Nat,
  +size: Nat,
  +references: Nat,
  +retired: List<&2, FileGeneration>,
  +target: Nat,
  matches: Bool
) -> GenerationPinDecision:
  match matches:
    case True{}:
      Pinned{GenerationRegistry{FileGeneration{id, size,
        Nat.add(references, 1n)}, retired}}
    case False{}:
      pin.registry.retired(id, size, references,
        pin.retired(retired, target))

def pin.registry.current(
  current: FileGeneration,
  retired: List<&2, FileGeneration>,
  +target: Nat
) -> GenerationPinDecision:
  match current:
    case FileGeneration{+id, +size, references}:
      pin.registry.decision(id, size, references, retired, target,
        Nat.is_eq(id, target))

# Increments the reference count of one current or retired generation.
def pin_generation(
  registry: GenerationRegistry,
  target: Nat
) -> GenerationPinDecision:
  match registry:
    case GenerationRegistry{current, retired}:
      pin.registry.current(current, retired, target)

def release.retired.prepend(
  id: Nat,
  size: Nat,
  references: Nat,
  result: RetiredRelease
) -> RetiredRelease:
  match result:
    case RetiredReleased{retired}:
      RetiredReleased{Con{FileGeneration{id, size, references}, retired}}
    case RetiredReclaimed{retired, number, bytes}:
      RetiredReclaimed{Con{FileGeneration{id, size, references}, retired},
        number, bytes}
    case RetiredMissing{retired}:
      RetiredMissing{Con{FileGeneration{id, size, references}, retired}}

def release.retired.references(
  id: Nat,
  size: Nat,
  references: Nat,
  tail: List<&2, FileGeneration>
) -> RetiredRelease:
  match references:
    case 0n:
      RetiredMissing{Con{FileGeneration{id, size, references}, tail}}
    case 1n:
      RetiredReclaimed{tail, id, size}
    case 1n+rest:
      RetiredReleased{Con{FileGeneration{id, size, rest}, tail}}

def release.retired.loop(
  retired: List<&2, FileGeneration>,
  +target: Nat,
  matches: Bool
) -> RetiredRelease:
  match retired:
    case Nil{}: RetiredMissing{Nil{}}
    case Con{FileGeneration{+id, +size, +references}, Nil{}}:
      match matches:
        case True{}:
          release.retired.references(id, size, references, Nil{})
        case False{}:
          RetiredMissing{Con{FileGeneration{id, size,
            references}, Nil{}}}
    case Con{FileGeneration{+id, +size, +references},
        Con{FileGeneration{+next_id, +next_size, +next_references}, rest}}:
      match matches:
        case True{}:
          release.retired.references(id, size, references,
            Con{FileGeneration{next_id, next_size, next_references}, rest})
        case False{}:
          release.retired.prepend(id, size, references,
            release.retired.loop(Con{FileGeneration{next_id, next_size,
              next_references}, rest}, target,
              Nat.is_eq(next_id, target)))

def release.retired(
  +retired: List<&2, FileGeneration>,
  +target: Nat
) -> RetiredRelease:
  match retired:
    case Nil{}: RetiredMissing{Nil{}}
    case Con{generation, _}:
      match generation:
        case FileGeneration{+id, _, _}:
          release.retired.loop(retired, target, Nat.is_eq(id, target))

def release.registry.retired(
  id: Nat,
  size: Nat,
  references: Nat,
  result: RetiredRelease
) -> GenerationReleaseDecision:
  match result:
    case RetiredReleased{retired}:
      GenerationReleased{GenerationRegistry{
        FileGeneration{id, size, references}, retired}}
    case RetiredReclaimed{retired, number, bytes}:
      GenerationReclaimed{GenerationRegistry{
        FileGeneration{id, size, references}, retired}, number, bytes}
    case RetiredMissing{retired}:
      MissingReference{GenerationRegistry{
        FileGeneration{id, size, references}, retired}}

def release.registry.references(
  id: Nat,
  size: Nat,
  references: Nat,
  retired: List<&2, FileGeneration>
) -> GenerationReleaseDecision:
  match references:
    case 0n:
      MissingReference{GenerationRegistry{
        FileGeneration{id, size, references}, retired}}
    case 1n+rest:
      GenerationReleased{GenerationRegistry{FileGeneration{id, size, rest},
        retired}}

def release.registry.decision(
  +id: Nat,
  +size: Nat,
  +references: Nat,
  +retired: List<&2, FileGeneration>,
  +target: Nat,
  matches: Bool
) -> GenerationReleaseDecision:
  match matches:
    case True{}:
      release.registry.references(id, size, references, retired)
    case False{}:
      release.registry.retired(id, size, references,
        release.retired(retired, target))

def release.registry.current(
  current: FileGeneration,
  retired: List<&2, FileGeneration>,
  +target: Nat
) -> GenerationReleaseDecision:
  match current:
    case FileGeneration{+id, +size, references}:
      release.registry.decision(id, size, references, retired, target,
        Nat.is_eq(id, target))

def release_generation.in(
  registry: GenerationRegistry,
  target: Nat
) -> GenerationReleaseDecision:
  match registry:
    case GenerationRegistry{current, retired}:
      release.registry.current(current, retired, target)

def release_generation.from_registry(
  registry: GenerationRegistry,
  target: Nat
) -> GenerationReleaseDecision:
  release_generation.in(registry, target)

# Releases one reference and reclaims a retired generation after its final reader.
def release_generation(retired: RetiredGeneration) -> RetentionDecision:
  match retired:
    case NoRetained{}: InvalidReference{}
    case GenerationRetained{generation, bytes, references}:
      match references:
        case 0n: InvalidReference{}
        case 1n: Reclaim{generation, bytes}
        case 1n+rest: Keep{generation, bytes, rest}
