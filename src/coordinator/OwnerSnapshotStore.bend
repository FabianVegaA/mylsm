import Base
import ../ByteDurableDb.bend as ByteDb
import ../scan/Snapshot.bend as Snapshot

# Keeps logical owner accounting and retained roots in one persistent value.
type Store is Type:
  Store{registry: Snapshot.OwnerRegistry, ids: List<&2, U32>,
    roots: List<&1, ByteDb.SnapshotRoot>}

# Returns owner registration alongside the opaque identifier or rejection.
type OpenResult is Type:
  RootStored{store: Store, snapshot_id: U32}
  RootRejected{store: Store}

# Returns a cloned root while preserving its owner-held stored copy.
type LookupResult is Type:
  RootFound{store: Store, root: ByteDb.SnapshotRoot}
  RootMissing{store: Store}

# Reports explicit snapshot closure without discarding live child references.
type CloseResult is Type:
  RootClosed{store: Store}
  RootCloseBusy{store: Store}
  RootCloseMissing{store: Store}

# Returns the updated snapshot registry and an admitted owner cursor identifier.
type CursorOpenResult is Type:
  CursorStored{store: Store, cursor_id: U32}
  CursorRejected{store: Store}

# Reports cursor release while preserving owner-held snapshot roots.
type CursorCloseResult is Type:
  CursorReleased{store: Store, snapshot_id: U32}
  CursorReleaseRejected{store: Store}

# Carries aligned owner identifiers and roots through a removal search.
type RootRemoveResult is Type:
  RootRemoved{prefix_ids: List<&2, U32>,
    prefix_roots: List<&1, ByteDb.SnapshotRoot>, id: U32,
    root: ByteDb.SnapshotRoot, tail_ids: List<&2, U32>,
    tail_roots: List<&1, ByteDb.SnapshotRoot>}
  RootNotRemoved{ids: List<&2, U32>, roots: List<&1, ByteDb.SnapshotRoot>}

# Carries one bounded token search and the aligned prefix already visited.
type RootRemoveState is Type:
  RootRemoveSearch{ids: List<&2, U32>, roots: List<&1, ByteDb.SnapshotRoot>,
    snapshot_id: U32, prefix_ids: List<&2, U32>,
    prefix_roots: List<&1, ByteDb.SnapshotRoot>}
  RootRemoveDone{result: RootRemoveResult}

# Selects the registry status returned after restoring the root list.
type CloseRootsOutcome is Data:
  CloseRootsClosed{}
  CloseRootsBusy{}
  CloseRootsMissing{}

# Separates matching and mismatching tokens without consuming stored roots.
type RootCompareResult is Type:
  RootIdsMatch{registry: Snapshot.OwnerRegistry, id: U32,
    ids: List<&2, U32>, query_id: U32,
    root: ByteDb.SnapshotRoot, roots: List<&1, ByteDb.SnapshotRoot>}
  RootIdsDiffer{registry: Snapshot.OwnerRegistry, id: U32,
    ids: List<&2, U32>, query_id: U32,
    root: ByteDb.SnapshotRoot, roots: List<&1, ByteDb.SnapshotRoot>}

# Carries aligned token and root lists reconstructed after a search.
type RootRestore is Type:
  Restored{ids: List<&2, U32>, roots: List<&1, ByteDb.SnapshotRoot>}

# Advances a bounded lookup while preserving the untouched search prefix.
type RootFindState is Type:
  RootFindSearch{registry: Snapshot.OwnerRegistry, ids: List<&2, U32>,
    roots: List<&1, ByteDb.SnapshotRoot>, query_id: U32,
    prefix_ids: List<&2, U32>, prefix_roots: List<&1, ByteDb.SnapshotRoot>}
  RootFindCompare{decision: RootCompareResult,
    prefix_ids: List<&2, U32>, prefix_roots: List<&1, ByteDb.SnapshotRoot>}
  RootFindFinished{result: LookupResult}

# Starts an owner with no snapshots, cursors, or retained SST generations.
def empty() -> Store:
  Store{Snapshot.OwnerRegistry{Snapshot.ResourceIdAllocator{1, False{}},
    Snapshot.Registry{0n, 0n}, Nil{}, Nil{}}, Nil{}, Nil{}}

def open.root.allocated(
  registry: Snapshot.OwnerRegistry,
  ids: List<&2, U32>,
  roots: List<&1, ByteDb.SnapshotRoot>,
  root: ByteDb.SnapshotRoot,
  copies: U32 & U32
) -> OpenResult:
  match copies:
    case (entry_id, response_id):
      RootStored{Store{registry, Con{entry_id, ids}, Con{root, roots}},
        response_id}

def open.root.result(
  decision: Snapshot.OwnerOpenDecision,
  ids: List<&2, U32>,
  roots: List<&1, ByteDb.SnapshotRoot>,
  root: ByteDb.SnapshotRoot
) -> OpenResult:
  match decision:
    case Snapshot.OwnerSnapshotOpened{registry, snapshot_id}:
      open.root.allocated(registry, ids, roots, root,
        Snapshot.u32.duplicate(snapshot_id))
    case Snapshot.OwnerSnapshotRejected{registry}:
      RootRejected{Store{registry, ids, roots}}

def open.root.copies(
  store: Store,
  root_copies: ByteDb.SnapshotRoot & ByteDb.SnapshotRoot,
  generation: Nat,
  limits: Nat & Nat
) -> OpenResult:
  match store:
    case Store{registry, ids, roots}:
      match root_copies:
        case (request_root, retained_root):
          match request_root:
            case ByteDb.SnapshotRoot{_, _, retained_bytes, _}:
              open.root.result(Snapshot.owner.snapshot.open(registry,
                generation, retained_bytes, limits), ids, roots, retained_root)

def open.root(
  store: Store,
  root: ByteDb.SnapshotRoot,
  generation: Nat,
  limits: Nat & Nat
) -> OpenResult:
  open.root.copies(store, ByteDb.snapshot.root.clone(root), generation,
    limits)

def ids.count(ids: List<&2, U32>) -> Nat:
  match ids:
    case Nil{}: 0n
    case Con{_, tail}: Nat.add(1n, ids.count(tail))

def root.restore.prepend(
  restored: RootRestore,
  id: U32,
  root: ByteDb.SnapshotRoot
) -> RootRestore:
  match restored:
    case Restored{ids, roots}:
      Restored{Con{id, ids}, Con{root, roots}}

def root.restore(
  prefix_ids: List<&2, U32>,
  prefix_roots: List<&1, ByteDb.SnapshotRoot>,
  ids: List<&2, U32>,
  roots: List<&1, ByteDb.SnapshotRoot>
) -> RootRestore:
  match prefix_ids:
    case Nil{}: Restored{ids, roots}
    case Con{id, tail_ids}:
      match prefix_roots:
        case Nil{}: Restored{ids, roots}
        case Con{root, tail_roots}:
          root.restore.prepend(root.restore(tail_ids, tail_roots, ids, roots),
            id, root)

def root.find.matched.restored(
  registry: Snapshot.OwnerRegistry,
  found_root: ByteDb.SnapshotRoot,
  restored: RootRestore
) -> LookupResult:
  match restored:
    case Restored{restored_ids, restored_roots}:
      RootFound{Store{registry, restored_ids, restored_roots}, found_root}

def root.find.matched.prefix(
  registry: Snapshot.OwnerRegistry,
  id: U32,
  ids: List<&2, U32>,
  root_copies: ByteDb.SnapshotRoot & ByteDb.SnapshotRoot,
  roots: List<&1, ByteDb.SnapshotRoot>,
  prefix_ids: List<&2, U32>,
  prefix_roots: List<&1, ByteDb.SnapshotRoot>
) -> LookupResult:
  match root_copies:
    case (stored_root, found_root):
      root.find.matched.restored(registry, found_root,
        root.restore(prefix_ids, prefix_roots,
          Con{id, ids}, Con{stored_root, roots}))

def root.find.compare.checked(
  registry: Snapshot.OwnerRegistry,
  is_match: Bool,
  id: U32,
  query_id: U32,
  ids: List<&2, U32>,
  root: ByteDb.SnapshotRoot,
  roots: List<&1, ByteDb.SnapshotRoot>
) -> RootCompareResult:
  match is_match:
    case True{}: RootIdsMatch{registry, id, ids, query_id, root, roots}
    case False{}: RootIdsDiffer{registry, id, ids, query_id, root, roots}

def root.find.compare.ids(
  registry: Snapshot.OwnerRegistry,
  stored_ids: U32 & U32,
  query_ids: U32 & U32,
  ids: List<&2, U32>,
  root: ByteDb.SnapshotRoot,
  roots: List<&1, ByteDb.SnapshotRoot>
) -> RootCompareResult:
  match stored_ids:
    case (check_id, stored_id):
      match query_ids:
        case (query_id, retained_query_id):
          root.find.compare.checked(registry,
            U32.is_eq(check_id, query_id), stored_id, retained_query_id,
            ids, root, roots)

def root.find.compare(
  registry: Snapshot.OwnerRegistry,
  id: U32,
  ids: List<&2, U32>,
  root: ByteDb.SnapshotRoot,
  roots: List<&1, ByteDb.SnapshotRoot>,
  query_id: U32,
  prefix_ids: List<&2, U32>,
  prefix_roots: List<&1, ByteDb.SnapshotRoot>
) -> RootFindState:
  RootFindCompare{root.find.compare.ids(registry,
    Snapshot.u32.duplicate(id), Snapshot.u32.duplicate(query_id), ids, root,
    roots), prefix_ids, prefix_roots}

def root.find.empty.restored(
  registry: Snapshot.OwnerRegistry,
  restored: RootRestore
) -> RootFindState:
  match restored:
    case Restored{restored_ids, restored_roots}:
      RootFindFinished{RootMissing{Store{registry, restored_ids,
        restored_roots}}}

def root.find.advance(state: RootFindState) -> RootFindState:
  match state:
    case RootFindSearch{registry, ids, roots, query_id, prefix_ids,
        prefix_roots}:
      match ids:
        case Nil{}:
          root.find.empty.restored(registry,
            root.restore(prefix_ids, prefix_roots, Nil{}, roots))
        case Con{stored_id, tail_ids}:
          match roots:
            case Nil{}:
              RootFindFinished{RootMissing{Store{registry, ids, Nil{}}}}
            case Con{root, tail_roots}:
              root.find.compare(registry, stored_id, tail_ids, root,
                tail_roots, query_id, prefix_ids, prefix_roots)
    case RootFindCompare{decision, prefix_ids, prefix_roots}:
      match decision:
        case RootIdsMatch{registry, id, ids, _, root, roots}:
          RootFindFinished{root.find.matched.prefix(registry, id, ids,
            ByteDb.snapshot.root.clone(root), roots, prefix_ids, prefix_roots)}
        case RootIdsDiffer{registry, id, ids, query_id, root, roots}:
          RootFindSearch{registry, ids, roots, query_id, Con{id, prefix_ids},
            Con{root, prefix_roots}}
    case RootFindFinished{result}: RootFindFinished{result}

def root.find.exhausted.restored(
  registry: Snapshot.OwnerRegistry,
  restored: RootRestore
) -> LookupResult:
  match restored:
    case Restored{restored_ids, restored_roots}:
      RootMissing{Store{registry, restored_ids, restored_roots}}

def root.find.exhausted(state: RootFindState) -> LookupResult:
  match state:
    case RootFindFinished{result}: result
    case RootFindSearch{registry, ids, roots, _, prefix_ids, prefix_roots}:
      root.find.exhausted.restored(registry,
        root.restore(prefix_ids, prefix_roots, ids, roots))
    case RootFindCompare{decision, prefix_ids, prefix_roots}:
      match decision:
        case RootIdsMatch{registry, id, ids, _, root, roots}:
          root.find.exhausted.restored(registry,
            root.restore(prefix_ids, prefix_roots, Con{id, ids},
              Con{root, roots}))
        case RootIdsDiffer{registry, id, ids, _, root, roots}:
          root.find.exhausted.restored(registry,
            root.restore(prefix_ids, prefix_roots, Con{id, ids},
              Con{root, roots}))

def root.find.process(fuel: Nat, state: RootFindState) -> LookupResult:
  match fuel:
    case 0n: root.find.exhausted(state)
    case 1n+rest:
      match state:
        case RootFindFinished{result}: result
        case _:
          root.find.process(rest, root.find.advance(state))

def ids.clone.tail(
  head_ids: U32 & U32,
  tails: List<&2, U32> & List<&2, U32>
) -> List<&2, U32> & List<&2, U32>:
  match head_ids:
    case (first_id, second_id):
      match tails:
        case (first_tail, second_tail):
          (Con{first_id, first_tail}, Con{second_id, second_tail})

def ids.clone.pair(ids: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match ids:
    case Nil{}: (Nil{}, Nil{})
    case Con{id, tail}:
      ids.clone.tail(Snapshot.u32.duplicate(id), ids.clone.pair(tail))

def lookup.root.fuel(
  registry: Snapshot.OwnerRegistry,
  ids: List<&2, U32>,
  roots: List<&1, ByteDb.SnapshotRoot>,
  snapshot_id: U32,
  counts: Nat & Nat
) -> LookupResult:
  match counts:
    case (first_count, second_count):
      root.find.process(Nat.add(first_count, second_count),
        RootFindSearch{registry, ids, roots, snapshot_id, Nil{}, Nil{}})

def lookup.root.copies(
  registry: Snapshot.OwnerRegistry,
  ids: List<&2, U32> & List<&2, U32>,
  roots: List<&1, ByteDb.SnapshotRoot>,
  snapshot_id: U32
) -> LookupResult:
  match ids:
    case (fuel_ids, search_ids):
      lookup.root.fuel(registry, search_ids, roots, snapshot_id,
        Snapshot.nat.duplicate(ids.count(fuel_ids)))

def lookup.root(store: Store, snapshot_id: U32) -> LookupResult:
  match store:
    case Store{registry, ids, roots}:
      lookup.root.copies(registry, ids.clone.pair(ids), roots, snapshot_id)

def roots.count(roots: List<&1, ByteDb.SnapshotRoot>) -> Nat:
  match roots:
    case Nil{}: 0n
    case Con{_, tail}: Nat.add(1n, roots.count(tail))

def snapshot.count(store: Store) -> Nat:
  match store:
    case Store{registry, _, _}:
      match registry:
        case Snapshot.OwnerRegistry{_, reservations, _, _}:
          match reservations:
            case Snapshot.Registry{count, _}: count

def retained.bytes(store: Store) -> Nat:
  match store:
    case Store{registry, _, _}:
      match registry:
        case Snapshot.OwnerRegistry{_, reservations, _, _}:
          match reservations:
            case Snapshot.Registry{_, retained}: retained

def root.count(store: Store) -> Nat:
  match store:
    case Store{_, _, roots}: roots.count(roots)

def has.counts(
  store: Store,
  expected_snapshots: Nat,
  expected_bytes: Nat,
  expected_roots: Nat
) -> Bool:
  match store:
    case Store{registry, _, roots}:
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

# Returns aligned lists with the original prefix restored.
def root.remove.restore(restored: RootRestore) -> RootRemoveResult:
  match restored:
    case Restored{all_ids, all_roots}:
      RootNotRemoved{all_ids, all_roots}

# Chooses removal at a match or advances with the current pair in its prefix.
def root.remove.checked(
  matches: Bool,
  tail_ids: List<&2, U32>,
  tail_roots: List<&1, ByteDb.SnapshotRoot>,
  snapshot_id: U32,
  id: U32,
  root: ByteDb.SnapshotRoot,
  prefix_ids: List<&2, U32>,
  prefix_roots: List<&1, ByteDb.SnapshotRoot>
) -> RootRemoveState:
  match matches:
    case True{}: RootRemoveDone{RootRemoved{prefix_ids, prefix_roots, id,
      root, tail_ids, tail_roots}}
    case False{}:
      RootRemoveSearch{tail_ids, tail_roots, snapshot_id, Con{id, prefix_ids},
        Con{root, prefix_roots}}

# Compares copies of the token while retaining the query for later steps.
def root.remove.compare(
  token_ids: U32 & U32,
  query_ids: U32 & U32,
  tail_ids: List<&2, U32>,
  tail_roots: List<&1, ByteDb.SnapshotRoot>,
  root: ByteDb.SnapshotRoot,
  prefix_ids: List<&2, U32>,
  prefix_roots: List<&1, ByteDb.SnapshotRoot>
) -> RootRemoveState:
  match token_ids:
    case (compare_id, stored_id):
      match query_ids:
        case (compare_query, retained_query):
          root.remove.checked(U32.is_eq(compare_id, compare_query), tail_ids,
            tail_roots, retained_query, stored_id, root, prefix_ids,
            prefix_roots)

# Advances one aligned token/root pair without recursion through list size.
def root.remove.advance(state: RootRemoveState) -> RootRemoveState:
  match state:
    case RootRemoveDone{result}: RootRemoveDone{result}
    case RootRemoveSearch{ids, roots, snapshot_id, prefix_ids, prefix_roots}:
      match ids:
        case Nil{}:
          RootRemoveDone{root.remove.restore(root.restore(prefix_ids,
            prefix_roots, Nil{}, roots))}
        case Con{id, tail_ids}:
          match roots:
            case Nil{}:
              RootRemoveDone{root.remove.restore(root.restore(prefix_ids,
                prefix_roots, ids, Nil{}))}
            case Con{root, tail_roots}:
              root.remove.compare(Snapshot.u32.duplicate(id),
                Snapshot.u32.duplicate(snapshot_id), tail_ids, tail_roots,
                root, prefix_ids, prefix_roots)

# Reconstructs the untouched lists if the bounded search exhausts its fuel.
def root.remove.exhausted(state: RootRemoveState) -> RootRemoveResult:
  match state:
    case RootRemoveDone{result}: result
    case RootRemoveSearch{ids, roots, _, prefix_ids, prefix_roots}:
      root.remove.restore(root.restore(prefix_ids, prefix_roots, ids, roots))

# Processes a finite token search using one step per stored root.
def root.remove.process(fuel: Nat, state: RootRemoveState) -> RootRemoveResult:
  match fuel:
    case 0n: root.remove.exhausted(state)
    case 1n+rest:
      match state:
        case RootRemoveDone{result}: result
        case _: root.remove.process(rest, root.remove.advance(state))

# Derives bounded search fuel from an independent copy of the token list.
def root.remove.fueled(
  ids: List<&2, U32> & List<&2, U32>,
  roots: List<&1, ByteDb.SnapshotRoot>,
  snapshot_id: U32
) -> RootRemoveResult:
  match ids:
    case (fuel_ids, search_ids):
      root.remove.process(ids.count(fuel_ids), RootRemoveSearch{search_ids,
        roots, snapshot_id, Nil{}, Nil{}})

# Removes exactly the root paired with an owner-issued snapshot identifier.
def root.remove(
  ids: List<&2, U32>,
  roots: List<&1, ByteDb.SnapshotRoot>,
  snapshot_id: U32
) -> RootRemoveResult:
  root.remove.fueled(ids.clone.pair(ids), roots, snapshot_id)

# Chooses the restored root list after success, Busy, or missing-token closure.
def close.roots.busy(
  restored: RootRestore,
  registry: Snapshot.OwnerRegistry
) -> CloseResult:
  match restored:
    case Restored{ids, roots}: RootCloseBusy{Store{registry, ids, roots}}

# Removes the root after the registry reservation is released.
def close.roots.closed(
  restored: RootRestore,
  registry: Snapshot.OwnerRegistry
) -> CloseResult:
  match restored:
    case Restored{ids, roots}: RootClosed{Store{registry, ids, roots}}

# Returns the original root list when the registry rejected the token.
def close.roots.missing(
  restored: RootRestore,
  registry: Snapshot.OwnerRegistry
) -> CloseResult:
  match restored:
    case Restored{ids, roots}: RootCloseMissing{Store{registry, ids, roots}}

# Reconstructs the aligned root list after a close attempt.
def close.roots.result.checked(
  outcome: CloseRootsOutcome,
  registry: Snapshot.OwnerRegistry,
  id: U32,
  root: ByteDb.SnapshotRoot,
  prefix_ids: List<&2, U32>,
  prefix_roots: List<&1, ByteDb.SnapshotRoot>,
  tail_ids: List<&2, U32>,
  tail_roots: List<&1, ByteDb.SnapshotRoot>
) -> CloseResult:
  match outcome:
    case CloseRootsClosed{}:
      close.roots.closed(root.restore(prefix_ids, prefix_roots, tail_ids,
        tail_roots), registry)
    case CloseRootsBusy{}:
      close.roots.busy(root.restore(prefix_ids, prefix_roots,
        Con{id, tail_ids}, Con{root, tail_roots}), registry)
    case CloseRootsMissing{}:
      close.roots.missing(root.restore(prefix_ids, prefix_roots,
        Con{id, tail_ids}, Con{root, tail_roots}), registry)

# Reconstructs the aligned root list after a close attempt.
def close.roots.result(
  removed: RootRemoveResult,
  registry: Snapshot.OwnerRegistry,
  outcome: CloseRootsOutcome
) -> CloseResult:
  match removed:
    case RootRemoved{prefix_ids, prefix_roots, id, root, tail_ids,
        tail_roots}:
      close.roots.result.checked(outcome, registry, id, root, prefix_ids,
        prefix_roots, tail_ids, tail_roots)
    case RootNotRemoved{ids, roots}:
      RootCloseMissing{Store{registry, ids, roots}}

# Applies the already-proved registry close result to aligned retained roots.
def close.registry.result(
  decision: Snapshot.OwnerSnapshotCloseDecision,
  removed: RootRemoveResult
) -> CloseResult:
  match decision:
    case Snapshot.OwnerSnapshotBusy{registry}:
      close.roots.result(removed, registry, CloseRootsBusy{})
    case Snapshot.OwnerSnapshotCloseRejected{registry}:
      close.roots.result(removed, registry, CloseRootsMissing{})
    case Snapshot.OwnerSnapshotClosed{registry, _}:
      close.roots.result(removed, registry, CloseRootsClosed{})

# Applies the formal close decision only after finding the aligned retained root.
def close.removed(
  removed: RootRemoveResult,
  registry: Snapshot.OwnerRegistry,
  snapshot_id: U32
) -> CloseResult:
  match removed:
    case RootNotRemoved{ids, roots}:
      RootCloseMissing{Store{registry, ids, roots}}
    case RootRemoved{_, _, _, _, _, _}:
      close.registry.result(Snapshot.owner.snapshot.close(registry,
        snapshot_id), removed)

# Splits the requested token for root lookup and registry policy evaluation.
def close.inputs(store: Store, snapshot_ids: U32 & U32) -> CloseResult:
  match store:
    case Store{registry, ids, roots}:
      match snapshot_ids:
        case (lookup_id, close_id):
          close.removed(root.remove(ids, roots, lookup_id), registry,
            close_id)

# Closes a childless owner snapshot and releases its root from the store.
def close(store: Store, snapshot_id: U32) -> CloseResult:
  close.inputs(store, Snapshot.u32.duplicate(snapshot_id))

def cursor.open.result(
  ids: List<&2, U32>,
  roots: List<&1, ByteDb.SnapshotRoot>,
  decision: Snapshot.OwnerCursorOpenDecision
) -> CursorOpenResult:
  match decision:
    case Snapshot.OwnerCursorOpened{registry, cursor_id}:
      CursorStored{Store{registry, ids, roots}, cursor_id}
    case Snapshot.OwnerCursorRejected{registry}:
      CursorRejected{Store{registry, ids, roots}}

def cursor.open(
  store: Store,
  snapshot_id: U32,
  max_cursors: Nat
) -> CursorOpenResult:
  match store:
    case Store{registry, ids, roots}:
      cursor.open.result(ids, roots,
        Snapshot.owner.cursor.open(registry, snapshot_id, max_cursors))

def cursor.close.result(
  ids: List<&2, U32>,
  roots: List<&1, ByteDb.SnapshotRoot>,
  decision: Snapshot.OwnerCursorCloseDecision
) -> CursorCloseResult:
  match decision:
    case Snapshot.OwnerCursorClosed{registry, snapshot_id}:
      CursorReleased{Store{registry, ids, roots}, snapshot_id}
    case Snapshot.OwnerCursorCloseRejected{registry}:
      CursorReleaseRejected{Store{registry, ids, roots}}

def cursor.close(store: Store, cursor_id: U32) -> CursorCloseResult:
  match store:
    case Store{registry, ids, roots}:
      cursor.close.result(ids, roots,
        Snapshot.owner.cursor.close(registry, cursor_id))
