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

# Identifies one owner-managed cursor and its parent snapshot.
type CursorResource is Data:
  CursorResource{id: U32, snapshot_id: U32}

# Holds aggregate snapshot reservations and their owner-issued identifiers.
type OwnerRegistry is Data:
  OwnerRegistry{allocator: ResourceIdAllocator, reservations: Registry,
    snapshots: List<&2, SnapshotResource>, cursors: List<&2, CursorResource>}

# Reports an admitted owner snapshot or the exact registry after rejection.
type OwnerOpenDecision is Data:
  OwnerSnapshotOpened{registry: OwnerRegistry, snapshot_id: U32}
  OwnerSnapshotRejected{registry: OwnerRegistry}

# Reports a cursor acquisition or the unchanged owner registry on rejection.
type OwnerCursorOpenDecision is Data:
  OwnerCursorOpened{registry: OwnerRegistry, cursor_id: U32}
  OwnerCursorRejected{registry: OwnerRegistry}

# Reports cursor removal with enough context to restore it after invalid release.
type CursorListRemoveDecision is Data:
  CursorListRemoved{prefix: List<&2, CursorResource>,
    resource: CursorResource,
    tail: List<&2, CursorResource>}
  CursorListMissing{cursors: List<&2, CursorResource>}

# Carries the recursive cursor-ID search with its untouched list prefix.
type CursorListRemoveState is Type:
  CursorSearch{cursors: List<&2, CursorResource>, cursor_id: U32,
    prefix: List<&2, CursorResource>}
  CursorCompareCopies{copies: CursorResource & CursorResource,
    tail: List<&2, CursorResource>, cursor_ids: U32 & U32,
    prefix: List<&2, CursorResource>}
  CursorCompare{matches: Bool, resource: CursorResource,
    tail: List<&2, CursorResource>, cursor_id: U32,
    prefix: List<&2, CursorResource>}

# Reports cursor closure or preserves owner accounting on invalid release.
type OwnerCursorCloseDecision is Data:
  OwnerCursorClosed{registry: OwnerRegistry, snapshot_id: U32}
  OwnerCursorCloseRejected{registry: OwnerRegistry}

# Reports snapshot closure, live-child Busy, or unchanged registry rejection.
type OwnerSnapshotCloseDecision is Data:
  OwnerSnapshotClosed{registry: OwnerRegistry, resource: SnapshotResource}
  OwnerSnapshotBusy{registry: OwnerRegistry}
  OwnerSnapshotCloseRejected{registry: OwnerRegistry}

# Reports replacement of one snapshot's cursor count in the owner registry.
type SnapshotListCursorDecision is Data:
  SnapshotListUpdated{snapshots: List<&2, SnapshotResource>}
  SnapshotListRejected{snapshots: List<&2, SnapshotResource>}
  SnapshotListClosed{prefix: List<&2, SnapshotResource>,
    resource: SnapshotResource, tail: List<&2, SnapshotResource>}
  SnapshotListBusy{snapshots: List<&2, SnapshotResource>}

# Selects whether a snapshot child reference is acquired or released.
type SnapshotCursorAction is Data:
  SnapshotCursorAcquire{max_cursors: Nat}
  SnapshotCursorRelease{}
  SnapshotCursorClose{}

# Carries the recursive snapshot lookup without losing the original list prefix.
type SnapshotListCursorState is Type:
  SnapshotCursorSearch{snapshots: List<&2, SnapshotResource>,
    snapshot_id: U32, action: SnapshotCursorAction,
    prefix: List<&2, SnapshotResource>}
  SnapshotCursorCompareCopies{copies: SnapshotResource & SnapshotResource,
    tail: List<&2, SnapshotResource>, snapshot_ids: U32 & U32,
    action: SnapshotCursorAction, prefix: List<&2, SnapshotResource>}
  SnapshotCursorCompare{matches: Bool, resource: SnapshotResource,
    tail: List<&2, SnapshotResource>, snapshot_id: U32,
    action: SnapshotCursorAction,
    prefix: List<&2, SnapshotResource>}

# Reports a snapshot cursor-reference update or preserves its prior resource.
type SnapshotCursorDecision is Data:
  SnapshotCursorAcquired{resource: SnapshotResource}
  SnapshotCursorLimit{resource: SnapshotResource}
  SnapshotCursorReleased{resource: SnapshotResource}
  SnapshotCursorUnderflow{resource: SnapshotResource}

def point_read.matches(order: Cmp) -> Bool:
  match order:
    case EQ{}: True{}
    case _: False{}



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
  cursors: List<&2, CursorResource>,
  decision: RegistryReleaseDecision
) -> OwnerOpenDecision:
  match decision:
    case Released{reservations}:
      OwnerSnapshotRejected{OwnerRegistry{allocator, reservations, snapshots,
        cursors}}
    case InvalidRelease{reservations}:
      OwnerSnapshotRejected{OwnerRegistry{allocator, reservations, snapshots,
        cursors}}

def owner.snapshot.open.created(
  ids: U32 & U32,
  allocator: ResourceIdAllocator,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  cursors: List<&2, CursorResource>,
  generation: Nat,
  retained_bytes: Nat
) -> OwnerOpenDecision:
  match ids:
    case (snapshot_id, entry_id):
      OwnerSnapshotOpened{OwnerRegistry{allocator, reservations,
        Con{SnapshotResource{entry_id, generation, retained_bytes, 0n}, snapshots},
        cursors},
        snapshot_id}

def owner.snapshot.open.id(
  allocation: ResourceIdDecision,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  cursors: List<&2, CursorResource>,
  generation: Nat,
  retained_bytes: Nat
) -> OwnerOpenDecision:
  match allocation:
    case ResourceIdAllocated{id, allocator}:
      owner.snapshot.open.created(u32.duplicate(id), allocator, reservations,
        snapshots, cursors, generation, retained_bytes)
    case ResourceIdExhausted{allocator}:
      owner.snapshot.open.release(allocator, snapshots, cursors,
        registry.release(reservations, retained_bytes))

def owner.snapshot.open.reserved(
  allocator: ResourceIdAllocator,
  snapshots: List<&2, SnapshotResource>,
  cursors: List<&2, CursorResource>,
  generation: Nat,
  requests: Nat & Nat,
  decision: RegistryDecision
) -> OwnerOpenDecision:
  match requests:
    case (retained_bytes, release_bytes):
      match decision:
        case Admitted{reservations}:
          owner.snapshot.open.id(allocate_resource_id(allocator), reservations,
            snapshots, cursors, generation, release_bytes)
        case Rejected{reservations}:
          OwnerSnapshotRejected{OwnerRegistry{allocator, reservations,
            snapshots, cursors}}

def owner.snapshot.open.budget(
  allocator: ResourceIdAllocator,
  snapshots: List<&2, SnapshotResource>,
  cursors: List<&2, CursorResource>,
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
          owner.snapshot.open.reserved(allocator, snapshots, cursors,
            generation, (retained_for_entry, release_bytes),
            registry.reserve(reservations, retained_for_admission,
              max_snapshots, max_retained_bytes))

def owner.snapshot.open.available(
  allocator: ResourceIdAllocator,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  cursors: List<&2, CursorResource>,
  generation: Nat,
  requests: Nat & Nat,
  limits: Nat & Nat
) -> OwnerOpenDecision:
  match allocator:
    case ResourceIdAllocator{next_id, exhausted}:
      match exhausted:
        case True{}:
          OwnerSnapshotRejected{OwnerRegistry{allocator, reservations,
            snapshots, cursors}}
        case False{}:
          match requests:
            case (requested_bytes, release_bytes):
              owner.snapshot.open.budget(allocator, snapshots, cursors,
                generation, nat.duplicate(requested_bytes), release_bytes, limits,
                reservations)

def owner.snapshot.open(
  owner: OwnerRegistry,
  generation: Nat,
  requested_bytes: Nat,
  limits: Nat & Nat
) -> OwnerOpenDecision:
  match owner:
    case OwnerRegistry{allocator, reservations, snapshots, cursors}:
      owner.snapshot.open.available(allocator, reservations, snapshots,
        cursors,
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

def snapshot.list.cursor.restore(
  prefix: List<&2, SnapshotResource>,
  snapshots: List<&2, SnapshotResource>
) -> List<&2, SnapshotResource>:
  match prefix:
    case Nil{}: snapshots
    case Con{resource, tail}:
      snapshot.list.cursor.restore(tail, Con{resource, snapshots})

def snapshot.list.cursor.length.keep.go(
  snapshots: List<&2, SnapshotResource>,
  reversed: List<&2, SnapshotResource>,
  length: Nat
) -> List<&2, SnapshotResource> & Nat:
  match snapshots:
    case Nil{}:
      (List.reverse(&2, SnapshotResource, reversed), length)
    case Con{resource, tail}:
      snapshot.list.cursor.length.keep.go(tail, Con{resource, reversed},
        Nat.add(length, 1n))

def snapshot.list.cursor.length.keep(
  snapshots: List<&2, SnapshotResource>
) -> List<&2, SnapshotResource> & Nat:
  snapshot.list.cursor.length.keep.go(snapshots, Nil{}, 0n)

def snapshot.list.cursor.resolve(
  prefix: List<&2, SnapshotResource>,
  tail: List<&2, SnapshotResource>,
  acquired: SnapshotCursorDecision
) -> SnapshotListCursorDecision:
  match acquired:
    case SnapshotCursorAcquired{resource}:
      SnapshotListUpdated{snapshot.list.cursor.restore(prefix,
        Con{resource, tail})}
    case SnapshotCursorLimit{resource}:
      SnapshotListRejected{snapshot.list.cursor.restore(prefix,
        Con{resource, tail})}
    case SnapshotCursorReleased{resource}:
      SnapshotListUpdated{snapshot.list.cursor.restore(prefix,
        Con{resource, tail})}
    case SnapshotCursorUnderflow{resource}:
      SnapshotListRejected{snapshot.list.cursor.restore(prefix,
        Con{resource, tail})}

def snapshot.list.cursor.close.result(
  can_close: Bool,
  prefix: List<&2, SnapshotResource>,
  resource: SnapshotResource,
  tail: List<&2, SnapshotResource>
) -> SnapshotListCursorDecision:
  match can_close:
    case True{}: SnapshotListClosed{prefix, resource, tail}
    case False{}:
      SnapshotListBusy{snapshot.list.cursor.restore(prefix,
        Con{resource, tail})}

def snapshot.list.cursor.close.resource(
  copies: SnapshotResource & SnapshotResource,
  prefix: List<&2, SnapshotResource>,
  tail: List<&2, SnapshotResource>
) -> SnapshotListCursorDecision:
  match copies:
    case (for_check, for_update):
      match for_check:
        case SnapshotResource{_, _, _, cursor_count}:
          snapshot.list.cursor.close.result(Nat.is_eq(cursor_count, 0n),
            prefix, for_update, tail)

def snapshot.list.cursor.action(
  prefix: List<&2, SnapshotResource>,
  tail: List<&2, SnapshotResource>,
  resource: SnapshotResource,
  action: SnapshotCursorAction
) -> SnapshotListCursorDecision:
  match action:
    case SnapshotCursorAcquire{max_cursors}:
      snapshot.list.cursor.resolve(prefix, tail,
        snapshot.resource.cursor.acquire(resource, max_cursors))
    case SnapshotCursorRelease{}:
      snapshot.list.cursor.resolve(prefix, tail,
        snapshot.resource.cursor.release(resource))
    case SnapshotCursorClose{}:
      snapshot.list.cursor.close.resource(
        snapshot.resource.duplicate(resource), prefix, tail)

def snapshot.list.cursor.exhausted(
  state: SnapshotListCursorState
) -> SnapshotListCursorDecision:
  match state:
    case SnapshotCursorSearch{snapshots, _, _, prefix}:
      SnapshotListRejected{snapshot.list.cursor.restore(prefix, snapshots)}
    case SnapshotCursorCompareCopies{copies, tail, _, _, prefix}:
      match copies:
        case (_, resource):
          SnapshotListRejected{snapshot.list.cursor.restore(prefix,
            Con{resource, tail})}
    case SnapshotCursorCompare{_, resource, tail, _, _, prefix}:
      SnapshotListRejected{snapshot.list.cursor.restore(prefix,
        Con{resource, tail})}

# Updates exactly one snapshot cursor count and preserves every unrelated entry.
def snapshot.list.cursor.acquire.loop(
  fuel: Nat,
  state: SnapshotListCursorState
) -> SnapshotListCursorDecision:
  match fuel:
    case 0n:
      snapshot.list.cursor.exhausted(state)
    case 1n+rest:
      match state:
        case SnapshotCursorSearch{snapshots, snapshot_id, action,
            prefix}:
          match snapshots:
            case Nil{}:
              SnapshotListRejected{snapshot.list.cursor.restore(prefix,
                Nil{})}
            case Con{resource, tail}:
              snapshot.list.cursor.acquire.loop(rest,
                SnapshotCursorCompareCopies{
                  snapshot.resource.duplicate(resource), tail,
                  u32.duplicate(snapshot_id), action, prefix})
        case SnapshotCursorCompareCopies{copies, tail, snapshot_ids,
            action, prefix}:
          match copies:
            case (for_check, for_update):
              match for_check:
                case SnapshotResource{id, _, _, _}:
                  match snapshot_ids:
                    case (current_id, next_id):
                      snapshot.list.cursor.acquire.loop(rest,
                        SnapshotCursorCompare{U32.is_eq(id, current_id),
                          for_update, tail, next_id, action, prefix})
        case SnapshotCursorCompare{matches, resource, tail, snapshot_id,
            action, prefix}:
          match matches:
            case True{}:
              snapshot.list.cursor.action(prefix, tail, resource, action)
            case False{}:
              snapshot.list.cursor.acquire.loop(rest,
                SnapshotCursorSearch{tail, snapshot_id, action,
                  Con{resource, prefix}})

def snapshot.list.cursor.acquire.measured(
  measured: List<&2, SnapshotResource> & Nat,
  snapshot_id: U32,
  action: SnapshotCursorAction
) -> SnapshotListCursorDecision:
  match measured:
    case (snapshots, length):
      snapshot.list.cursor.acquire.loop(
        Nat.add(Nat.mul(3n, length), 1n),
        SnapshotCursorSearch{snapshots, snapshot_id, action, Nil{}})

# Adds one cursor reference to the owner record identified by its snapshot ID.
def snapshot.list.cursor.acquire(
  snapshots: List<&2, SnapshotResource>,
  snapshot_id: U32,
  max_cursors: Nat
) -> SnapshotListCursorDecision:
  snapshot.list.cursor.acquire.measured(
    snapshot.list.cursor.length.keep(snapshots), snapshot_id,
    SnapshotCursorAcquire{max_cursors})

# Releases exactly one cursor reference from the matching snapshot resource.
def snapshot.list.cursor.release(
  snapshots: List<&2, SnapshotResource>,
  snapshot_id: U32
) -> SnapshotListCursorDecision:
  snapshot.list.cursor.acquire.measured(
    snapshot.list.cursor.length.keep(snapshots), snapshot_id,
    SnapshotCursorRelease{})

# Removes a childless snapshot record and reports Busy while cursors remain.
def snapshot.list.cursor.close(
  snapshots: List<&2, SnapshotResource>,
  snapshot_id: U32
) -> SnapshotListCursorDecision:
  snapshot.list.cursor.acquire.measured(
    snapshot.list.cursor.length.keep(snapshots), snapshot_id,
    SnapshotCursorClose{})

def owner.cursor.open.ready(
  cursor_ids: U32 & U32,
  allocator: ResourceIdAllocator,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  cursors: List<&2, CursorResource>,
  snapshot_id: U32
) -> OwnerCursorOpenDecision:
  match cursor_ids:
    case (cursor_id, entry_id):
      OwnerCursorOpened{OwnerRegistry{allocator, reservations, snapshots,
        Con{CursorResource{entry_id, snapshot_id}, cursors}}, cursor_id}

def owner.cursor.open.allocated(
  allocation: ResourceIdDecision,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  cursors: List<&2, CursorResource>,
  snapshot_id: U32
) -> OwnerCursorOpenDecision:
  match allocation:
    case ResourceIdAllocated{cursor_id, next_allocator}:
      owner.cursor.open.ready(u32.duplicate(cursor_id), next_allocator,
        reservations, snapshots, cursors, snapshot_id)
    case ResourceIdExhausted{allocator}:
      OwnerCursorRejected{OwnerRegistry{allocator, reservations,
        snapshots, cursors}}

def owner.cursor.open.snapshot(
  allocator: ResourceIdAllocator,
  reservations: Registry,
  cursors: List<&2, CursorResource>,
  snapshot_id: U32,
  updated: SnapshotListCursorDecision
) -> OwnerCursorOpenDecision:
  match updated:
    case SnapshotListUpdated{snapshots}:
      owner.cursor.open.allocated(allocate_resource_id(allocator),
        reservations, snapshots, cursors, snapshot_id)
    case SnapshotListRejected{snapshots}:
      OwnerCursorRejected{OwnerRegistry{allocator, reservations, snapshots,
        cursors}}
    case SnapshotListClosed{prefix, resource, tail}:
      OwnerCursorRejected{OwnerRegistry{allocator, reservations,
        snapshot.list.cursor.restore(prefix, Con{resource, tail}), cursors}}
    case SnapshotListBusy{snapshots}:
      OwnerCursorRejected{OwnerRegistry{allocator, reservations, snapshots,
        cursors}}

def owner.cursor.open.request(
  allocator: ResourceIdAllocator,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  cursors: List<&2, CursorResource>,
  snapshot_ids: U32 & U32,
  max_cursors: Nat
) -> OwnerCursorOpenDecision:
  match snapshot_ids:
    case (cursor_snapshot_id, lookup_snapshot_id):
      owner.cursor.open.snapshot(allocator, reservations, cursors,
        cursor_snapshot_id,
        snapshot.list.cursor.acquire(snapshots, lookup_snapshot_id,
          max_cursors))

# Rejects cursor opens when the owner ID space is exhausted.
def owner.cursor.open.available(
  owner: OwnerRegistry,
  snapshot_id: U32,
  max_cursors: Nat
) -> OwnerCursorOpenDecision:
  match owner:
    case OwnerRegistry{allocator, reservations, snapshots, cursors}:
      match allocator:
        case ResourceIdAllocator{_, exhausted}:
          match exhausted:
            case True{}:
              OwnerCursorRejected{OwnerRegistry{allocator, reservations,
                snapshots, cursors}}
            case False{}:
              owner.cursor.open.request(allocator, reservations, snapshots,
                cursors, u32.duplicate(snapshot_id), max_cursors)

# Acquires a unique owner cursor ID and a child reference on its snapshot.
def owner.cursor.open(
  owner: OwnerRegistry,
  snapshot_id: U32,
  max_cursors: Nat
) -> OwnerCursorOpenDecision:
  owner.cursor.open.available(owner, snapshot_id, max_cursors)

def cursor.resource.duplicate.parts(
  ids: U32 & U32,
  snapshots: U32 & U32
) -> CursorResource & CursorResource:
  match ids:
    case (first_id, second_id):
      match snapshots:
        case (first_snapshot, second_snapshot):
          (CursorResource{first_id, first_snapshot},
            CursorResource{second_id, second_snapshot})

def cursor.resource.duplicate(resource: CursorResource) -> CursorResource & CursorResource:
  match resource:
    case CursorResource{id, snapshot_id}:
      cursor.resource.duplicate.parts(u32.duplicate(id),
        u32.duplicate(snapshot_id))

def cursor.list.restore(
  prefix: List<&2, CursorResource>,
  cursors: List<&2, CursorResource>
) -> List<&2, CursorResource>:
  match prefix:
    case Nil{}: cursors
    case Con{resource, tail}:
      cursor.list.restore(tail, Con{resource, cursors})

def cursor.list.length.keep.go(
  cursors: List<&2, CursorResource>,
  reversed: List<&2, CursorResource>,
  length: Nat
) -> List<&2, CursorResource> & Nat:
  match cursors:
    case Nil{}: (List.reverse(&2, CursorResource, reversed), length)
    case Con{resource, tail}:
      cursor.list.length.keep.go(tail, Con{resource, reversed},
        Nat.add(length, 1n))

def cursor.list.length.keep(
  cursors: List<&2, CursorResource>
) -> List<&2, CursorResource> & Nat:
  cursor.list.length.keep.go(cursors, Nil{}, 0n)

def cursor.list.remove.exhausted(
  state: CursorListRemoveState
) -> CursorListRemoveDecision:
  match state:
    case CursorSearch{cursors, _, prefix}:
      CursorListMissing{cursor.list.restore(prefix, cursors)}
    case CursorCompareCopies{copies, tail, _, prefix}:
      match copies:
        case (_, resource):
          CursorListMissing{cursor.list.restore(prefix,
            Con{resource, tail})}
    case CursorCompare{_, resource, tail, _, prefix}:
      CursorListMissing{cursor.list.restore(prefix, Con{resource, tail})}

def cursor.list.remove.loop(
  fuel: Nat,
  state: CursorListRemoveState
) -> CursorListRemoveDecision:
  match fuel:
    case 0n: cursor.list.remove.exhausted(state)
    case 1n+rest:
      match state:
        case CursorSearch{cursors, cursor_id, prefix}:
          match cursors:
            case Nil{}:
              CursorListMissing{cursor.list.restore(prefix, Nil{})}
            case Con{resource, tail}:
              cursor.list.remove.loop(rest, CursorCompareCopies{
                cursor.resource.duplicate(resource), tail,
                u32.duplicate(cursor_id), prefix})
        case CursorCompareCopies{copies, tail, cursor_ids, prefix}:
          match copies:
            case (for_check, for_update):
              match for_check:
                case CursorResource{id, _}:
                  match cursor_ids:
                    case (current_id, next_id):
                      cursor.list.remove.loop(rest,
                        CursorCompare{U32.is_eq(id, current_id), for_update,
                          tail, next_id, prefix})
        case CursorCompare{matches, resource, tail, cursor_id, prefix}:
          match matches:
            case True{}:
              CursorListRemoved{prefix, resource, tail}
            case False{}:
              cursor.list.remove.loop(rest, CursorSearch{tail, cursor_id,
                Con{resource, prefix}})

def cursor.list.remove.measured(
  measured: List<&2, CursorResource> & Nat,
  cursor_id: U32
) -> CursorListRemoveDecision:
  match measured:
    case (cursors, length):
      cursor.list.remove.loop(Nat.add(Nat.mul(3n, length), 1n),
        CursorSearch{cursors, cursor_id, Nil{}})

# Removes one owner cursor ID without changing its parent snapshot count.
def cursor.list.remove(
  cursors: List<&2, CursorResource>,
  cursor_id: U32
) -> CursorListRemoveDecision:
  cursor.list.remove.measured(cursor.list.length.keep(cursors), cursor_id)

def owner.cursor.close.released(
  allocator: ResourceIdAllocator,
  reservations: Registry,
  prefix: List<&2, CursorResource>,
  resource: CursorResource,
  tail: List<&2, CursorResource>,
  snapshot_id: U32,
  released: SnapshotListCursorDecision
) -> OwnerCursorCloseDecision:
  match released:
    case SnapshotListUpdated{snapshots}:
      OwnerCursorClosed{OwnerRegistry{allocator, reservations, snapshots,
        cursor.list.restore(prefix, tail)}, snapshot_id}
    case SnapshotListRejected{snapshots}:
      OwnerCursorCloseRejected{OwnerRegistry{allocator, reservations,
        snapshots, cursor.list.restore(prefix, Con{resource, tail})}}
    case SnapshotListClosed{snapshot_prefix, snapshot_resource,
        snapshot_tail}:
      OwnerCursorCloseRejected{OwnerRegistry{allocator, reservations,
        snapshot.list.cursor.restore(snapshot_prefix,
          Con{snapshot_resource, snapshot_tail}),
        cursor.list.restore(prefix, Con{resource, tail})}}
    case SnapshotListBusy{snapshots}:
      OwnerCursorCloseRejected{OwnerRegistry{allocator, reservations,
        snapshots, cursor.list.restore(prefix, Con{resource, tail})}}

def owner.cursor.close.release.id(
  allocator: ResourceIdAllocator,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  prefix: List<&2, CursorResource>,
  resource: CursorResource,
  tail: List<&2, CursorResource>,
  snapshot_ids: U32 & U32
) -> OwnerCursorCloseDecision:
  match snapshot_ids:
    case (close_snapshot_id, lookup_snapshot_id):
      owner.cursor.close.released(allocator, reservations, prefix, resource,
        tail, close_snapshot_id,
        snapshot.list.cursor.release(snapshots, lookup_snapshot_id))

def owner.cursor.close.lookup(
  allocator: ResourceIdAllocator,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  prefix: List<&2, CursorResource>,
  tail: List<&2, CursorResource>,
  copies: CursorResource & CursorResource
) -> OwnerCursorCloseDecision:
  match copies:
    case (for_check, for_update):
      match for_check:
        case CursorResource{_, snapshot_id}:
          owner.cursor.close.release.id(allocator, reservations, snapshots,
            prefix, for_update, tail, u32.duplicate(snapshot_id))

def owner.cursor.close.removed(
  allocator: ResourceIdAllocator,
  reservations: Registry,
  snapshots: List<&2, SnapshotResource>,
  removal: CursorListRemoveDecision
) -> OwnerCursorCloseDecision:
  match removal:
    case CursorListMissing{cursors}:
      OwnerCursorCloseRejected{OwnerRegistry{allocator, reservations,
        snapshots, cursors}}
    case CursorListRemoved{prefix, resource, tail}:
      owner.cursor.close.lookup(allocator, reservations, snapshots,
        prefix, tail, cursor.resource.duplicate(resource))

# Releases one owner cursor and its parent snapshot reference atomically.
def owner.cursor.close(
  owner: OwnerRegistry,
  cursor_id: U32
) -> OwnerCursorCloseDecision:
  match owner:
    case OwnerRegistry{allocator, reservations, snapshots, cursors}:
      owner.cursor.close.removed(allocator, reservations, snapshots,
        cursor.list.remove(cursors, cursor_id))

def owner.snapshot.close.released(
  decision: RegistryReleaseDecision,
  allocator: ResourceIdAllocator,
  cursors: List<&2, CursorResource>,
  prefix: List<&2, SnapshotResource>,
  resource: SnapshotResource,
  tail: List<&2, SnapshotResource>
) -> OwnerSnapshotCloseDecision:
  match decision:
    case Released{reservations}:
      OwnerSnapshotClosed{OwnerRegistry{allocator, reservations,
        snapshot.list.cursor.restore(prefix, tail), cursors}, resource}
    case InvalidRelease{reservations}:
      OwnerSnapshotCloseRejected{OwnerRegistry{allocator, reservations,
        snapshot.list.cursor.restore(prefix, Con{resource, tail}), cursors}}

def owner.snapshot.close.resource(
  copies: SnapshotResource & SnapshotResource,
  allocator: ResourceIdAllocator,
  cursors: List<&2, CursorResource>,
  prefix: List<&2, SnapshotResource>,
  tail: List<&2, SnapshotResource>,
  reservations: Registry
) -> OwnerSnapshotCloseDecision:
  match copies:
    case (for_check, for_update):
      match for_check:
        case SnapshotResource{_, _, retained_bytes, _}:
          owner.snapshot.close.released(
            registry.release(reservations, retained_bytes), allocator,
            cursors, prefix, for_update, tail)

def owner.snapshot.close.list(
  allocator: ResourceIdAllocator,
  reservations: Registry,
  cursors: List<&2, CursorResource>,
  decision: SnapshotListCursorDecision
) -> OwnerSnapshotCloseDecision:
  match decision:
    case SnapshotListClosed{prefix, resource, tail}:
      owner.snapshot.close.resource(snapshot.resource.duplicate(resource),
        allocator, cursors, prefix, tail, reservations)
    case SnapshotListBusy{snapshots}:
      OwnerSnapshotBusy{OwnerRegistry{allocator, reservations, snapshots,
        cursors}}
    case SnapshotListRejected{snapshots}:
      OwnerSnapshotCloseRejected{OwnerRegistry{allocator, reservations,
        snapshots, cursors}}
    case SnapshotListUpdated{snapshots}:
      OwnerSnapshotCloseRejected{OwnerRegistry{allocator, reservations,
        snapshots, cursors}}

# Closes a snapshot only after its final cursor releases the retained root.
def owner.snapshot.close(
  owner: OwnerRegistry,
  snapshot_id: U32
) -> OwnerSnapshotCloseDecision:
  match owner:
    case OwnerRegistry{allocator, reservations, snapshots, cursors}:
      owner.snapshot.close.list(allocator, reservations, cursors,
        snapshot.list.cursor.close(snapshots, snapshot_id))

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
