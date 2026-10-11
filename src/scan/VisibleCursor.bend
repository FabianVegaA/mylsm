import Base
import ../ByteMemTable.bend as ByteMemTable
import ../Keys.bend as Keys
import ./ByteRange.bend as ByteRange
import ./RangeCursor.bend as RangeCursor
import ./ScanMerge.bend as ScanMerge
import ./SstCursor.bend as SstCursor
import ./VisibleSeekPolicy.bend as VisibleSeekPolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Retains one SST head and one ordered delta source between reads.
type Cursor is Type:
  Active{base: Maybe<&1, SstCursor.Cursor>, pending: Maybe<&1, ByteMemTable.Entry>,
    delta: List<&1, ByteMemTable.Entry>, bounds: RangeCursor.Bounds}
  Ended{}
  Closed{}
  Failed{error: U32 & String}

# Returns one visible item, filtered source step, terminal end, or IO error.
type Step is Type:
  Item{entry: ByteMemTable.Entry, cursor: Cursor}
  Skip{cursor: Cursor}
  End{}
  Error{error: U32 & String}

# Carries one in-range delta entry or exhaustion at the upper bound.
type DeltaHead is Type:
  DeltaReady{entry: ByteMemTable.Entry, tail: List<&1, ByteMemTable.Entry>}
  DeltaDone{}

# Normalizes the block cursor outcome before merge resolution.
type BaseResult is Type:
  BaseItem{cursor: SstCursor.Cursor, entry: ByteMemTable.Entry}
  BaseSkip{cursor: SstCursor.Cursor}
  BaseDone{}
  BaseError{error: U32 & String}

# Holds both source heads while the byte comparator decides their order.
type CompareState is Type:
  Compare{base: Maybe<&1, SstCursor.Cursor>, base_entry: ByteMemTable.Entry,
    delta_entry: ByteMemTable.Entry, delta_tail: List<&1, ByteMemTable.Entry>,
    bounds: RangeCursor.Bounds, order: Cmp}

# Preserves comparison metadata while cloning an affine delta entry.
type ResolveState is Type:
  Resolve{base: Maybe<&1, SstCursor.Cursor>, base_entry: ByteMemTable.Entry,
    delta_tail: List<&1, ByteMemTable.Entry>, bounds: RangeCursor.Bounds,
    order: Cmp}

def bytes.second(copies: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match copies:
    case (_, second): second

def bytes.first(copies: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match copies:
    case (first, _): first

# Opens the merge state over an already bounded SST cursor and captured delta.
def open(
  base: Maybe<&1, SstCursor.Cursor>,
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> Cursor:
  Active{base, None{}, delta, bounds}

def base.seek(base: Maybe<&1, SstCursor.Cursor>, lower: Maybe<&1, Bytes.Bytes>) -> Maybe<&1, SstCursor.Cursor>:
  match base:
    case Some{cursor}: Some{SstCursor.seek(cursor, lower)}
    case None{}: None{}

def lower.triple.second(
  first: Bytes.Bytes,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>:
  match copies:
    case (second, third): (Some{first}, Some{second}, Some{third})

def lower.triple.copy(
  values: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>
) -> Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>:
  match values:
    case (None{}, None{}): (None{}, None{}, None{})
    case (None{}, Some{_}): (None{}, None{}, None{})
    case (Some{_}, None{}): (None{}, None{}, None{})
    case (Some{first}, Some{second}):
      lower.triple.second(first, ByteMemTable.bytes.clone(second))

def lower.triple(
  lower: Maybe<&1, Bytes.Bytes>
) ->
  Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>:
  lower.triple.copy(ByteMemTable.value.clone(lower))

def seek.ready(
  base: Maybe<&1, SstCursor.Cursor>,
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  lowers: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>
) -> Cursor:
  match lowers:
    case (base_lower, (delta_lower, bounds_lower)):
      Active{base.seek(base, base_lower), None{}, RangeCursor.seek(delta, delta_lower),
        VisibleSeekPolicy.seek.bounds(bounds, bounds_lower)}

# Advances every retained source to the same inclusive lower key.
def seek(cursor: Cursor, lower: Maybe<&1, Bytes.Bytes>) -> Cursor:
  match cursor:
    case Active{base, _, delta, bounds}:
      seek.ready(base, delta, bounds, lower.triple(lower))
    case Ended{}: Ended{}
    case Closed{}: Closed{}
    case Failed{error}: Failed{error}

def delta.head.result(
  reached: Bool,
  entry: ByteMemTable.Entry,
  tail: List<&1, ByteMemTable.Entry>
) -> DeltaHead:
  match reached:
    case True{}: DeltaDone{}
    case False{}: DeltaReady{entry, tail}

def delta.head.checked(
  entry: ByteMemTable.Entry,
  tail: List<&1, ByteMemTable.Entry>,
  key: Bytes.Bytes,
  upper: Maybe<&1, Bytes.Bytes>
) -> DeltaHead:
  delta.head.result(ByteRange.at_or_after_upper(key, upper), entry, tail)

def delta.head.cloned(
  entries: ByteMemTable.Entry & ByteMemTable.Entry,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> DeltaHead:
  match entries:
    case (entry, copied):
      match copied:
        case ByteMemTable.Entry{key, _}:
          match bounds:
            case RangeCursor.Bounds{_, upper, _}:
              delta.head.checked(entry, tail, key, upper)

def delta.head(
  entry: ByteMemTable.Entry,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> DeltaHead:
  delta.head.cloned(ByteMemTable.entry.clone(entry), tail, bounds)

def delta.next(entries: List<&1, ByteMemTable.Entry>, bounds: RangeCursor.Bounds) -> DeltaHead:
  match entries:
    case Nil{}: DeltaDone{}
    case Con{entry, tail}: delta.head(entry, tail, bounds)

def base.result(result: SstCursor.Step) -> BaseResult:
  match result:
    case SstCursor.Item{entry, cursor}: BaseItem{cursor, entry}
    case SstCursor.Skip{cursor}: BaseSkip{cursor}
    case SstCursor.End{}: BaseDone{}
    case SstCursor.Error{error}: BaseError{error}

def delta.visible.key(
  key: Bytes.Bytes & Bytes.Bytes,
  bounds: RangeCursor.Bounds
) -> Bool:
  RangeCursor.matches.key(key, bounds)

def delta.visible(entry: ByteMemTable.Entry, bounds: RangeCursor.Bounds) -> Bool:
  match entry:
    case ByteMemTable.Entry{key, _}:
      delta.visible.key(ByteMemTable.bytes.clone(key), bounds)

def delta.live(value: Maybe<&1, Bytes.Bytes>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}

def delta.output.result(
  visible: Bool,
  live: Bool,
  entry: ByteMemTable.Entry,
  base: Maybe<&1, SstCursor.Cursor>,
  pending: Maybe<&1, ByteMemTable.Entry>,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> Step:
  match visible:
    case True{}:
      match live:
        case True{}: Item{entry, Active{base, pending, tail, bounds}}
        case False{}: Skip{Active{base, pending, tail, bounds}}
    case False{}: Skip{Active{base, pending, tail, bounds}}

def delta.output.checks(
  entry: ByteMemTable.Entry,
  checks: ByteMemTable.Entry & ByteMemTable.Entry,
  base: Maybe<&1, SstCursor.Cursor>,
  pending: Maybe<&1, ByteMemTable.Entry>,
  tail: List<&1, ByteMemTable.Entry>,
  copies: RangeCursor.Bounds & RangeCursor.Bounds
) -> Step:
  match checks:
    case (visible_entry, live_entry):
      match live_entry:
        case ByteMemTable.Entry{_, value}:
          match copies:
            case (checked, retained):
              delta.output.result(delta.visible(visible_entry, checked),
                delta.live(value), entry, base, pending, tail, retained)

def delta.output.bounds(
  entries: ByteMemTable.Entry & ByteMemTable.Entry,
  base: Maybe<&1, SstCursor.Cursor>,
  pending: Maybe<&1, ByteMemTable.Entry>,
  tail: List<&1, ByteMemTable.Entry>,
  copies: RangeCursor.Bounds & RangeCursor.Bounds
) -> Step:
  match entries:
    case (entry, checked_entry):
      delta.output.checks(entry, ByteMemTable.entry.clone(checked_entry),
        base, pending, tail, copies)

def delta.output(
  entry: ByteMemTable.Entry,
  base: Maybe<&1, SstCursor.Cursor>,
  pending: Maybe<&1, ByteMemTable.Entry>,
  tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> Step:
  delta.output.bounds(ByteMemTable.entry.clone(entry), base, pending, tail,
    RangeCursor.bounds.clone(bounds))

def decision.step(
  decision: ScanMerge.Decision,
  base: Maybe<&1, SstCursor.Cursor>,
  base_entry: ByteMemTable.Entry,
  delta_entry: ByteMemTable.Entry,
  delta_tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> Step:
  match decision:
    case ScanMerge.EmitDelta{}:
      delta.output(delta_entry, base, Some{base_entry}, delta_tail, bounds)
    case ScanMerge.EmitBase{}:
      match base:
        case Some{cursor}:
          Item{base_entry, Active{Some{cursor}, None{},
            Con{delta_entry, delta_tail}, bounds}}
        case None{}: End{}
    case ScanMerge.EmitBoth{}:
      delta.output(delta_entry, base, None{}, delta_tail, bounds)
    case ScanMerge.SkipDelta{}:
      Skip{Active{base, Some{base_entry}, delta_tail, bounds}}
    case ScanMerge.SkipBoth{}:
      Skip{Active{base, None{}, delta_tail, bounds}}
    case ScanMerge.Finished{}: End{}

def compare.order.only(result: Bytes.Bytes & Bytes.Bytes & Cmp) -> Cmp:
  match result:
    case (_, _, order): order

def compare.order(base_key: Bytes.Bytes, delta_key: Bytes.Bytes) -> Cmp:
  compare.order.only(Keys.Bytes.cmp.with_inputs(delta_key, base_key))

def compare.final(
  base: Maybe<&1, SstCursor.Cursor>,
  base_entry: ByteMemTable.Entry,
  delta_entry: ByteMemTable.Entry,
  delta_tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  base_key: Bytes.Bytes,
  delta_key: Bytes.Bytes,
) -> CompareState:
  Compare{base, base_entry, delta_entry, delta_tail, bounds,
    compare.order(base_key, delta_key)}

def compare.delta.copied(
  base: Maybe<&1, SstCursor.Cursor>,
  base_entry: ByteMemTable.Entry,
  delta_entries: ByteMemTable.Entry & ByteMemTable.Entry,
  delta_tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  base_key: Bytes.Bytes
) -> CompareState:
  match delta_entries:
    case (delta_entry, delta_probe):
      match delta_probe:
        case ByteMemTable.Entry{key, _}:
          compare.final(base, base_entry, delta_entry, delta_tail, bounds,
            base_key, key)

def compare.base.copied(
  base: Maybe<&1, SstCursor.Cursor>,
  base_entries: ByteMemTable.Entry & ByteMemTable.Entry,
  delta_entry: ByteMemTable.Entry,
  delta_tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> CompareState:
  match base_entries:
    case (base_entry, base_probe):
      match base_probe:
        case ByteMemTable.Entry{key, _}:
          compare.delta.copied(base, base_entry,
            ByteMemTable.entry.clone(delta_entry), delta_tail, bounds, key)

# Clones source heads and computes their canonical byte ordering.
def compare(
  base: Maybe<&1, SstCursor.Cursor>,
  base_entry: ByteMemTable.Entry,
  delta_entry: ByteMemTable.Entry,
  delta_tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> CompareState:
  compare.base.copied(base, ByteMemTable.entry.clone(base_entry),
    delta_entry, delta_tail, bounds)

def resolve.delta.pair(
  state: ResolveState,
  delta_entries: ByteMemTable.Entry & ByteMemTable.Entry
) -> Step:
  match state:
    case Resolve{base, base_entry, delta_tail, bounds, order}:
      match delta_entries:
        case (delta_entry, delta_probe):
          match delta_probe:
            case ByteMemTable.Entry{_, value}:
              decision.step(ScanMerge.choose(True{}, True{},
                delta.live(value), order), base, base_entry, delta_entry,
                delta_tail, bounds)

def resolve.compared(state: CompareState) -> Step:
  match state:
    case Compare{base, base_entry, delta_entry, delta_tail, bounds, order}:
      resolve.delta.pair(Resolve{base, base_entry, delta_tail, bounds, order},
        ByteMemTable.entry.clone(delta_entry))

# Applies the shared newest-wins decision to the current source heads.
def resolve(
  base: Maybe<&1, SstCursor.Cursor>,
  base_entry: ByteMemTable.Entry,
  delta_entry: ByteMemTable.Entry,
  delta_tail: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> Step:
  resolve.compared(compare(base, base_entry, delta_entry, delta_tail, bounds))

def ready.delta(
  base: Maybe<&1, SstCursor.Cursor>,
  pending: Maybe<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  head: DeltaHead
) -> Step:
  match base:
    case Some{base_cursor}:
      match pending:
        case Some{base_entry}:
          match head:
            case DeltaDone{}:
              Item{base_entry, Active{Some{base_cursor}, None{}, Nil{}, bounds}}
            case DeltaReady{entry, tail}:
              resolve(Some{base_cursor}, base_entry, entry, tail, bounds)
        case None{}: End{}
    case None{}:
      match pending:
        case None{}:
          match head:
            case DeltaDone{}: End{}
            case DeltaReady{entry, tail}:
              delta.output(entry, None{}, None{}, tail, bounds)
        case Some{_}: End{}

def ready.copied(
  base: Maybe<&1, SstCursor.Cursor>,
  pending: Maybe<&1, ByteMemTable.Entry>,
  delta: List<&1, ByteMemTable.Entry>,
  copies: RangeCursor.Bounds & RangeCursor.Bounds
) -> Step:
  match copies:
    case (bounds, delta_bounds):
      ready.delta(base, pending, bounds, delta.next(delta, delta_bounds))

# Resolves one already-read SST head against the next bounded delta head.
def ready(
  base: Maybe<&1, SstCursor.Cursor>,
  pending: Maybe<&1, ByteMemTable.Entry>,
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> Step:
  ready.copied(base, pending, delta, RangeCursor.bounds.clone(bounds))

def base.next.convert(
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  result: BaseResult
) -> IO(Step):
  match result:
    case BaseItem{cursor, entry}:
      IO.pure(Step, ready(Some{cursor}, Some{entry}, delta, bounds))
    case BaseSkip{cursor}:
      IO.pure(Step, Skip{Active{Some{cursor}, None{}, delta, bounds}})
    case BaseDone{}:
      IO.pure(Step, ready(None{}, None{}, delta, bounds))
    case BaseError{error}: IO.pure(Step, Error{error})

def base.next.result(
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  result: SstCursor.Step
) -> IO(Step):
  base.next.convert(delta, bounds, base.result(result))

# Advances the SST source by at most one record and merges one visible result.
def next(cursor: Cursor) -> IO(Step):
  match cursor:
    case Active{Some{base}, None{}, delta, bounds}:
      do IO<Step>:
        result : SstCursor.Step <- SstCursor.next(base)
        step : Step <- base.next.result(delta, bounds, result)
        return step
    case Active{base, pending, delta, bounds}:
      IO.pure(Step, ready(base, pending, delta, bounds))
    case Ended{}: IO.pure(Step, End{})
    case Closed{}: IO.pure(Step, End{})
    case Failed{error}: IO.pure(Step, Error{error})

# Closes the active SST file descriptor and leaves no source owned by the caller.
def close(cursor: Cursor) -> IO(Result<&1, &1, U32 & String, Unit>):
  match cursor:
    case Active{Some{base}, _, _, _}: SstCursor.close(base)
    case _:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
