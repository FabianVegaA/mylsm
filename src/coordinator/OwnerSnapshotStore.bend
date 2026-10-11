import Base
import ../ByteDurableDb.bend as ByteDb
import ../scan/Snapshot.bend as Snapshot

# Associates an owner-issued snapshot identifier with its retained storage root.
type SnapshotRootEntry is Type:
  SnapshotRootEntry{id: U32, root: ByteDb.SnapshotRoot}

# Keeps logical owner accounting and retained roots in one persistent value.
type Store is Type:
  Store{registry: Snapshot.OwnerRegistry,
    roots: List<&1, SnapshotRootEntry>}

# Returns owner registration alongside the opaque identifier or rejection.
type OpenResult is Type:
  RootStored{store: Store, snapshot_id: U32}
  RootRejected{store: Store}

# Starts an owner with no snapshots, cursors, or retained SST generations.
def empty() -> Store:
  Store{Snapshot.OwnerRegistry{Snapshot.ResourceIdAllocator{1, False{}},
    Snapshot.Registry{0n, 0n}, Nil{}, Nil{}}, Nil{}}

def open.root.allocated(
  registry: Snapshot.OwnerRegistry,
  roots: List<&1, SnapshotRootEntry>,
  root: ByteDb.SnapshotRoot,
  ids: U32 & U32
) -> OpenResult:
  match ids:
    case (entry_id, response_id):
      RootStored{Store{registry, Con{SnapshotRootEntry{entry_id, root}, roots}},
        response_id}

def open.root.result(
  decision: Snapshot.OwnerOpenDecision,
  roots: List<&1, SnapshotRootEntry>,
  root: ByteDb.SnapshotRoot
) -> OpenResult:
  match decision:
    case Snapshot.OwnerSnapshotOpened{registry, snapshot_id}:
      open.root.allocated(registry, roots, root,
        Snapshot.u32.duplicate(snapshot_id))
    case Snapshot.OwnerSnapshotRejected{registry}:
      RootRejected{Store{registry, roots}}

def open.root.copies(
  store: Store,
  root_copies: ByteDb.SnapshotRoot & ByteDb.SnapshotRoot,
  generation: Nat,
  limits: Nat & Nat
) -> OpenResult:
  match store:
    case Store{registry, roots}:
      match root_copies:
        case (request_root, retained_root):
          match request_root:
            case ByteDb.SnapshotRoot{_, _, retained_bytes, _}:
              open.root.result(Snapshot.owner.snapshot.open(registry,
                generation, retained_bytes, limits), roots, retained_root)

def open.root(
  store: Store,
  root: ByteDb.SnapshotRoot,
  generation: Nat,
  limits: Nat & Nat
) -> OpenResult:
  open.root.copies(store, ByteDb.snapshot.root.clone(root), generation,
    limits)

def roots.count(roots: List<&1, SnapshotRootEntry>) -> Nat:
  match roots:
    case Nil{}: 0n
    case Con{_, tail}: Nat.add(1n, roots.count(tail))

def snapshot.count(store: Store) -> Nat:
  match store:
    case Store{registry, _}:
      match registry:
        case Snapshot.OwnerRegistry{_, reservations, _, _}:
          match reservations:
            case Snapshot.Registry{count, _}: count

def retained.bytes(store: Store) -> Nat:
  match store:
    case Store{registry, _}:
      match registry:
        case Snapshot.OwnerRegistry{_, reservations, _, _}:
          match reservations:
            case Snapshot.Registry{_, retained}: retained

def root.count(store: Store) -> Nat:
  match store:
    case Store{_, roots}: roots.count(roots)

def has.counts(
  store: Store,
  expected_snapshots: Nat,
  expected_bytes: Nat,
  expected_roots: Nat
) -> Bool:
  match store:
    case Store{registry, roots}:
      match registry:
        case Snapshot.OwnerRegistry{_, reservations, _, _}:
          match reservations:
            case Snapshot.Registry{count, retained}:
              Nat.is_eq(count, expected_snapshots) &&
                Nat.is_eq(retained, expected_bytes) &&
                Nat.is_eq(roots.count(roots), expected_roots)

def empty.snapshot.count() -> Nat:
  snapshot.count(empty())

def empty.retained.bytes() -> Nat:
  retained.bytes(empty())

def empty.root.count() -> Nat:
  root.count(empty())

def empty.valid() -> Bool:
  has.counts(empty(), 0n, 0n, 0n)
