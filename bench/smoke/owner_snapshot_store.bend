import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/coordinator/OwnerSnapshotStore.bend as Store

# Fails when an owner snapshot store transition violates its expected state.
def require(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("OWNER_SNAPSHOT_STORE_PASSED")
    case False{}: IO.die(Unit, 1, "owner snapshot store state was invalid")

# Verifies a token lookup preserves its root and total owner accounting.
def found(result: Store.LookupResult) -> IO(Unit):
  match result:
    case Store.RootFound{store, _}:
      require(Store.has.counts(store, 2n, 0n, 2n))
    case Store.RootMissing{_}:
      IO.die(Unit, 1, "stored snapshot token was not found")

# Reads an older token after a lookup reconstructed the retained store.
def found.first(result: Store.LookupResult, second_id: U32) -> IO(Unit):
  match result:
    case Store.RootFound{store, _}:
      found(Store.lookup.root(store, second_id))
    case Store.RootMissing{_}:
      IO.die(Unit, 1, "older snapshot token was not found")

# Verifies the head and tail tokens after registering two retained roots.
def opened.second(result: Store.OpenResult, first_id: U32) -> IO(Unit):
  match result:
    case Store.RootStored{store, second_id}:
      found.first(Store.lookup.root(store, first_id), second_id)
    case Store.RootRejected{_}:
      IO.die(Unit, 1, "second snapshot admission was rejected")

# Registers a second root to exercise lookup past the list head.
def opened.first(result: Store.OpenResult) -> IO(Unit):
  match result:
    case Store.RootStored{store, first_id}:
      opened.second(Store.open.root(store,
        ByteDb.SnapshotRoot{None{}, None{}, 0n, Nil{}}, 0n, (2n, 64n)),
        first_id)
    case Store.RootRejected{_}:
      IO.die(Unit, 1, "first snapshot admission was rejected")

# Checks that accepted admission registers roots under owner-issued tokens.
def opened(result: Store.OpenResult) -> IO(Unit):
  opened.first(result)

# Checks that rejected admission preserves zero resource accounting.
def rejected(result: Store.OpenResult) -> IO(Unit):
  match result:
    case Store.RootStored{_, _}:
      IO.die(Unit, 1, "zero snapshot limit should reject admission")
    case Store.RootRejected{store}:
      require(Store.has.counts(store, 0n, 0n, 0n))

# Verifies an unknown token leaves an empty owner store unchanged.
def missing(result: Store.LookupResult) -> IO(Unit):
  match result:
    case Store.RootFound{_, _}:
      IO.die(Unit, 1, "unknown snapshot token resolved to a root")
    case Store.RootMissing{store}:
      require(Store.has.counts(store, 0n, 0n, 0n))

# Registers two empty retained roots under owner-issued tokens.
def admitted() -> IO(Unit):
  opened(Store.open.root(Store.empty(),
    ByteDb.SnapshotRoot{None{}, None{}, 0n, Nil{}}, 0n, (2n, 64n)))

def main() -> IO(Unit):
  do IO<Unit>:
    _initial: Unit <- require(Store.empty.valid())
    _opened: Unit <- admitted()
    _rejected: Unit <- rejected(Store.open.root(Store.empty(),
      ByteDb.SnapshotRoot{None{}, None{}, 0n, Nil{}}, 0n, (0n, 64n)))
    missing(Store.lookup.root(Store.empty(), 1))
