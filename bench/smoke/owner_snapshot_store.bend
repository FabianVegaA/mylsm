import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/coordinator/OwnerSnapshotStore.bend as Store

# Fails when an owner snapshot store transition violates its expected state.
def require(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("OWNER_SNAPSHOT_STORE_PASSED")
    case False{}: IO.die(Unit, 1, "owner snapshot store must start empty")

# Checks that accepted admission stores a root and returns its first ID.
def opened(result: Store.OpenResult) -> IO(Unit):
  match result:
    case Store.RootStored{store, snapshot_id}:
      require(U32.is_eq(snapshot_id, 1) &&
        Store.has.counts(store, 1n, 0n, 1n))
    case Store.RootRejected{_}:
      IO.die(Unit, 1, "owner snapshot admission should retain the root")

# Checks that rejected admission preserves zero resource accounting.
def rejected(result: Store.OpenResult) -> IO(Unit):
  match result:
    case Store.RootStored{_, _}:
      IO.die(Unit, 1, "zero snapshot limit should reject admission")
    case Store.RootRejected{store}:
      require(Store.has.counts(store, 0n, 0n, 0n))

def main() -> IO(Unit):
  do IO<Unit>:
    _initial : Unit <- require(Store.empty.valid())
    _opened : Unit <- opened(Store.open.root(Store.empty(),
      ByteDb.SnapshotRoot{None{}, None{}, 0n, Nil{}}, 0n, (2n, 64n)))
    rejected(Store.open.root(Store.empty(),
      ByteDb.SnapshotRoot{None{}, None{}, 0n, Nil{}}, 0n, (0n, 64n)))
