import Base
import ../scan/VisibleCursor.bend as VisibleCursor
import ./CursorCodec.bend as CursorCodec

# Keeps owner cursor IDs aligned with their live block-backed cursor values.
type Store is Type:
  Store{ids: List<&2, U32>, cursors: List<&1, VisibleCursor.Cursor>}

# Returns the current cursor count together with the untouched reader store.
type Metrics is Type:
  Metrics{count: Nat, store: Store}

# Carries a removed cursor and the aligned prefix and suffix for restoration.
type Removed is Type:
  Removed{prefix_ids: List<&2, U32>,
    prefix_cursors: List<&1, VisibleCursor.Cursor>,
    cursor: VisibleCursor.Cursor, tail_ids: List<&2, U32>,
    tail_cursors: List<&1, VisibleCursor.Cursor>}
  Missing{ids: List<&2, U32>, cursors: List<&1, VisibleCursor.Cursor>}

# Advances a bounded search through aligned cursor IDs and cursor values.
type State is Type:
  Searching{ids: List<&2, U32>, cursors: List<&1, VisibleCursor.Cursor>,
    query: U32, prefix_ids: List<&2, U32>,
    prefix_cursors: List<&1, VisibleCursor.Cursor>}
  SearchFinished{result: Removed}

# Returns one owned cursor with the remaining table or its unchanged table.
type TakeResult is Type:
  Taken{store: Store, cursor: VisibleCursor.Cursor}
  NotFound{store: Store}

# Starts with no live owner cursors.
def empty() -> Store:
  Store{Nil{}, Nil{}}

# Stores one owner-issued cursor token alongside its live reader state.
def insert(
  store: Store,
  id: U32,
  cursor: VisibleCursor.Cursor
) -> Store:
  match store:
    case Store{ids, cursors}: Store{Con{id, ids}, Con{cursor, cursors}}

def ids.count(ids: List<&2, U32>) -> Nat:
  match ids:
    case Nil{}: 0n
    case Con{_, tail}: Nat.add(1n, ids.count(tail))

def ids.count.keep.go(
  ids: List<&2, U32>,
  reversed: List<&2, U32>,
  count: Nat
) -> List<&2, U32> & Nat:
  match ids:
    case Nil{}: (List.reverse(&2, U32, reversed), count)
    case Con{id, tail}:
      ids.count.keep.go(tail, Con{id, reversed}, Nat.add(count, 1n))

def ids.count.keep(ids: List<&2, U32>) -> List<&2, U32> & Nat:
  ids.count.keep.go(ids, Nil{}, 0n)

def metrics.counted(
  counted: List<&2, U32> & Nat,
  cursors: List<&1, VisibleCursor.Cursor>
) -> Metrics:
  match counted:
    case (ids, count): Metrics{count, Store{ids, cursors}}

# Counts cursor IDs while rebuilding the aligned store for its caller.
def metrics(store: Store) -> Metrics:
  match store:
    case Store{ids, cursors}:
      metrics.counted(ids.count.keep(ids), cursors)

def ids.clone.tail(
  head: U32 & U32,
  tails: List<&2, U32> & List<&2, U32>
) -> List<&2, U32> & List<&2, U32>:
  match head:
    case (first_id, second_id):
      match tails:
        case (first_tail, second_tail):
          (Con{first_id, first_tail}, Con{second_id, second_tail})

def ids.clone.pair(ids: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match ids:
    case Nil{}: (Nil{}, Nil{})
    case Con{id, tail}:
      ids.clone.tail(CursorCodec.u32.duplicate(id), ids.clone.pair(tail))

# Restores one aligned ID and cursor pair to the reconstructed table.
def restore.prepend(
  store: Store,
  id: U32,
  cursor: VisibleCursor.Cursor
) -> Store:
  match store:
    case Store{ids, cursors}: Store{Con{id, ids}, Con{cursor, cursors}}

# Rebuilds the original table order from the scanned prefix and untouched tail.
def restore(
  prefix_ids: List<&2, U32>,
  prefix_cursors: List<&1, VisibleCursor.Cursor>,
  ids: List<&2, U32>,
  cursors: List<&1, VisibleCursor.Cursor>
) -> Store:
  match prefix_ids:
    case Nil{}: Store{ids, cursors}
    case Con{id, tail_ids}:
      match prefix_cursors:
        case Nil{}: Store{ids, cursors}
        case Con{cursor, tail_cursors}:
          restore.prepend(restore(tail_ids, tail_cursors, ids, cursors), id,
            cursor)

# Selects removal on a match or preserves the current aligned pair.
def checked(
  matches: Bool,
  tail_ids: List<&2, U32>,
  tail_cursors: List<&1, VisibleCursor.Cursor>,
  query: U32,
  id: U32,
  cursor: VisibleCursor.Cursor,
  prefix_ids: List<&2, U32>,
  prefix_cursors: List<&1, VisibleCursor.Cursor>
) -> State:
  match matches:
    case True{}:
      SearchFinished{Removed{prefix_ids, prefix_cursors, cursor, tail_ids,
        tail_cursors}}
    case False{}:
      Searching{tail_ids, tail_cursors, query, Con{id, prefix_ids},
        Con{cursor, prefix_cursors}}

def missing.restored(store: Store) -> State:
  match store:
    case Store{ids, cursors}: SearchFinished{Missing{ids, cursors}}

# Compares one stored owner token with the duplicated search token.
def compare(
  ids: U32 & U32,
  queries: U32 & U32,
  tail_ids: List<&2, U32>,
  tail_cursors: List<&1, VisibleCursor.Cursor>,
  cursor: VisibleCursor.Cursor,
  prefix_ids: List<&2, U32>,
  prefix_cursors: List<&1, VisibleCursor.Cursor>
) -> State:
  match ids:
    case (check_id, stored_id):
      match queries:
        case (query_id, retained_query):
          checked(U32.is_eq(check_id, query_id), tail_ids, tail_cursors,
            retained_query, stored_id, cursor, prefix_ids, prefix_cursors)

# Advances exactly one aligned ID/cursor pair without scanning the suffix.
def advance(state: State) -> State:
  match state:
    case SearchFinished{result}: SearchFinished{result}
    case Searching{ids, cursors, query, prefix_ids, prefix_cursors}:
      match ids:
        case Nil{}:
          missing.restored(restore(prefix_ids, prefix_cursors, Nil{}, cursors))
        case Con{id, tail_ids}:
          match cursors:
            case Nil{}: SearchFinished{Missing{ids, Nil{}}}
            case Con{cursor, tail_cursors}:
              compare(CursorCodec.u32.duplicate(id),
                CursorCodec.u32.duplicate(query), tail_ids, tail_cursors,
                cursor, prefix_ids, prefix_cursors)

def finish.missing(store: Store) -> TakeResult:
  match store:
    case Store{ids, cursors}: NotFound{Store{ids, cursors}}

def finish.removed(store: Store, cursor: VisibleCursor.Cursor) -> TakeResult:
  match store:
    case Store{ids, cursors}: Taken{Store{ids, cursors}, cursor}

# Restores the table after removal or a missing-token search.
def finish(result: Removed) -> TakeResult:
  match result:
    case Removed{prefix_ids, prefix_cursors, cursor, tail_ids, tail_cursors}:
      finish.removed(restore(prefix_ids, prefix_cursors, tail_ids,
        tail_cursors), cursor)
    case Missing{ids, cursors}: finish.missing(Store{ids, cursors})

# Bounds the linear token search by the original owner cursor count.
def process(fuel: Nat, state: State) -> TakeResult:
  match fuel:
    case 0n:
      match state:
        case SearchFinished{result}: finish(result)
        case Searching{ids, cursors, _, prefix_ids, prefix_cursors}:
          finish.missing(restore(prefix_ids, prefix_cursors, ids, cursors))
    case 1n+rest:
      match state:
        case SearchFinished{result}: finish(result)
        case _: process(rest, advance(state))

def take.copies(
  pair: List<&2, U32> & List<&2, U32>,
  cursors: List<&1, VisibleCursor.Cursor>,
  id: U32
) -> TakeResult:
  match pair:
    case (fuel_ids, search_ids):
      process(ids.count(fuel_ids), Searching{search_ids, cursors, id, Nil{}, Nil{}})

# Removes one owner cursor while preserving all unrelated cursor readers.
def take(store: Store, id: U32) -> TakeResult:
  match store:
    case Store{ids, cursors}: take.copies(ids.clone.pair(ids), cursors, id)

# Restores the advanced cursor under its original owner-issued token.
def reinsert(
  store: Store,
  id: U32,
  cursor: VisibleCursor.Cursor
) -> Store:
  insert(store, id, cursor)

def close.all.cursors(cursors: List<&1, VisibleCursor.Cursor>) -> IO(Unit):
  match cursors:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{cursor, tail}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <-
          VisibleCursor.close(cursor)
        close.all.cursors(tail)

def close.all(store: Store) -> IO(Unit):
  match store:
    case Store{_, cursors}: close.all.cursors(cursors)
