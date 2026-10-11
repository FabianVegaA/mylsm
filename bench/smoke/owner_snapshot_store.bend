import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/coordinator/OwnerSnapshotStore.bend as Store

# Fails when an owner snapshot store transition violates its expected state.
def require(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("OWNER_SNAPSHOT_STORE_PASSED")
    case False{}: IO.die(Unit, 1, "owner snapshot store state was invalid")

# Verifies the second close leaves no roots or aggregate reservations.
def closed.last(result: Store.CloseResult) -> IO(Unit):
  match result:
    case Store.RootClosed{store}:
      require(Store.has.counts(store, 0n, 0n, 0n))
    case Store.RootCloseBusy{_}:
      IO.die(Unit, 1, "childless snapshot close unexpectedly returned busy")
    case Store.RootCloseMissing{_}:
      IO.die(Unit, 1, "older snapshot token was not closed")

# Closes the second token and passes its reconstructed store to the final close.
def closed.second(result: Store.CloseResult) -> IO(Unit):
  match result:
    case Store.RootClosed{store}:
      closed.last(Store.close(store, 1))
    case Store.RootCloseBusy{_}:
      IO.die(Unit, 1, "childless snapshot close unexpectedly returned busy")
    case Store.RootCloseMissing{_}:
      IO.die(Unit, 1, "second snapshot token was not closed")

# Reads the second token after the first lookup reconstructed the store.
def found.second(result: Store.LookupResult) -> IO(Unit):
  match result:
    case Store.RootFound{store, _}:
      closed.second(Store.close(store, 2))
    case Store.RootMissing{_}:
      IO.die(Unit, 1, "second snapshot token was not found")

# Reads the older token before passing the rebuilt store to the second lookup.
def found.first(result: Store.LookupResult, second_id: U32) -> IO(Unit):
  match result:
    case Store.RootFound{store, _}:
      found.second(Store.lookup.root(store, second_id))
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
