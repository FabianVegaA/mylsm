import Base
import ../ByteMemTable.bend as ByteMemTable
import ../scan/VisibleCursor.bend as VisibleCursor
import ./Backup.bend as Backup
import ./BackupCursorPolicy.bend as Policy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Separates bounded record emission from footer emission and completion.
type Phase is Data:
  CursorBlocks{}
  CursorFooter{}
  CursorFinished{}

# Tracks one visible cursor and no more than one pending export block.
type Stream is Type:
  Stream{phase: Phase, cursor: Maybe<&1, VisibleCursor.Cursor>,
    pending: List<&1, ByteMemTable.Entry>, pending_count: Nat,
    seen: Nat, expected: Nat, entry_count: U32, block_count: U32,
    block_index: U32}

# Returns a bounded backup chunk, terminal completion, or a validation error.
type Step is Type:
  Chunk{stream: Stream, bytes: Bytes.Bytes}
  Continue{stream: Stream}
  End{}
  Failure{cursor: Maybe<&1, VisibleCursor.Cursor>, error: Backup.Error}

# Initializes the bounded cursor stream after encoding its header.
def start.ready(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  entry_count: U32,
  expected: Nat,
  block_count: U32,
  header: Bytes.Bytes
) -> Step:
  Chunk{Stream{CursorBlocks{}, cursor, Nil{}, 0n, 0n, expected,
    entry_count, block_count, 0}, header}

def start.count(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  entries: U32 & U32,
  block_count: U32,
  header: Bytes.Bytes
) -> Step:
  match entries:
    case (entry_count, expected):
      start.ready(cursor, entry_count, U32.to_nat(expected),
        block_count, header)

def start.header(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pair: Backup.Stream & Bytes.Bytes
) -> Step:
  match pair:
    case (Backup.Stream{_, _, entry_count, block_count, _}, header):
      start.count(cursor, Backup.u32.duplicate.pair(entry_count),
        block_count, header)

def start.counts(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  counts: Nat & Nat
) -> Step:
  match counts:
    case (entry_count, block_input):
      +encoded_entries = U32.from_nat(entry_count)
      +encoded_blocks = Backup.blocks.count(block_input)
      start.header(cursor, Backup.header.bytes(
        Backup.Stream{Backup.Header{}, Nil{}, encoded_entries,
          encoded_blocks, 0}))

# Emits the format header and prepares the first incremental source read.
def start(cursor: VisibleCursor.Cursor, entry_count: Nat) -> Step:
  start.counts(Some{cursor}, Backup.nat.duplicate.pair(entry_count))

def block.written(
  result: Result<&1, &1, Backup.Error, Bytes.Bytes>,
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  seen: Nat,
  expected: Nat,
  entry_count: U32,
  block_count: U32,
  next_index: U32,
  next_phase: Phase
) -> Step:
  match result:
    case Fail{error}: Failure{cursor, error}
    case Done{bytes}:
      Chunk{Stream{next_phase, cursor, Nil{}, 0n, seen,
        expected, entry_count, block_count, next_index}, bytes}

def block.index.pair(index: U32) -> U32 & U32:
  +current = U32.to_nat(index)
  (U32.from_nat(current), U32.from_nat(Policy.block.index.next(current)))

def block.encoded(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pending: List<&1, ByteMemTable.Entry>,
  seen: Nat,
  expected: Nat,
  entry_count: U32,
  block_count: U32,
  indexes: U32 & U32,
  count: Nat,
  next_phase: Phase
) -> Step:
  match indexes:
    case (encode_index, next_index):
      block.written(Backup.block.encoded(
        List.reverse(&1, ByteMemTable.Entry, pending), encode_index,
        U32.from_nat(count)), cursor, seen, expected,
        entry_count, block_count, next_index, next_phase)

def item.full(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pending: List<&1, ByteMemTable.Entry>,
  seen: Nat,
  expected: Nat,
  entry_count: U32,
  block_count: U32,
  block_index: U32,
  count: Nat,
  next_phase: Phase
) -> Step:
  block.encoded(cursor, pending, seen, expected, entry_count, block_count,
    block.index.pair(block_index), count, next_phase)

def item.decided(
  decision: Policy.AppendDecision,
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pending: List<&1, ByteMemTable.Entry>,
  expected: Nat,
  entry_count: U32,
  block_count: U32,
  block_index: U32
) -> Step:
  match decision:
    case Policy.CursorRejected{}:
      Failure{cursor, Backup.ResourceLimit{}}
    case Policy.CursorBuffer{seen, pending_count}:
      Continue{Stream{CursorBlocks{}, cursor, pending, pending_count,
        seen, expected, entry_count, block_count, block_index}}
    case Policy.CursorBlockReady{seen, pending_count}:
      item.full(cursor, pending, seen, expected, entry_count, block_count,
        block_index, pending_count, CursorBlocks{})

def item.counted(
  entry: ByteMemTable.Entry,
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pending: List<&1, ByteMemTable.Entry>,
  seen: Nat,
  pending_count: Nat,
  entry_count: U32,
  block_count: U32,
  block_index: U32,
  expected_copies: Nat & Nat
) -> Step:
  match expected_copies:
    case (for_policy, retained):
      item.decided(Policy.append(seen, pending_count, for_policy),
        cursor, Con{entry, pending}, retained, entry_count,
        block_count, block_index)

# Adds one cursor item without exceeding the declared total or block capacity.
def item(
  entry: ByteMemTable.Entry,
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pending: List<&1, ByteMemTable.Entry>,
  seen: Nat,
  pending_count: Nat,
  expected: Nat,
  entry_count: U32,
  block_count: U32,
  block_index: U32
) -> Step:
  item.counted(entry, cursor, pending, seen, pending_count,
    entry_count, block_count, block_index,
    Backup.nat.duplicate.pair(expected))

# Retains the pending block when the cursor advances over a tombstone.
def skip(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pending: List<&1, ByteMemTable.Entry>,
  pending_count: Nat,
  seen: Nat,
  expected: Nat,
  entry_count: U32,
  block_count: U32,
  block_index: U32
) -> Step:
  Continue{Stream{CursorBlocks{}, cursor, pending, pending_count, seen,
    expected, entry_count, block_count, block_index}}

def footer.ready(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  seen: Nat,
  expected: Nat,
  entry_count: U32,
  block_count: U32,
  block_index: U32,
  encoded: Backup.Stream & Bytes.Bytes
) -> Step:
  match encoded:
    case (_, bytes):
      Chunk{Stream{CursorFinished{}, cursor, Nil{}, 0n, seen,
        expected, entry_count, block_count, block_index}, bytes}

def footer.counts(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  seen: Nat,
  expected: Nat,
  entries: U32 & U32,
  blocks: U32 & U32,
  indexes: U32 & U32
) -> Step:
  match entries:
    case (encoded_entries, retained_entries):
      match blocks:
        case (encoded_blocks, retained_blocks):
          match indexes:
            case (encoded_index, retained_index):
              footer.ready(cursor, seen, expected,
                retained_entries, retained_blocks, retained_index,
                Backup.footer.bytes(Backup.Stream{Backup.Footer{}, Nil{},
                  encoded_entries, encoded_blocks, encoded_index}))

# Emits the checksum footer while retaining only terminal cursor state.
def footer(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  seen: Nat,
  expected: Nat,
  entry_count: U32,
  block_count: U32,
  block_index: U32
) -> Step:
  footer.counts(cursor, seen, expected,
    Backup.u32.duplicate.pair(entry_count),
    Backup.u32.duplicate.pair(block_count),
    Backup.u32.duplicate.pair(block_index))

def finish.decided(
  decision: Policy.FinishDecision,
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pending: List<&1, ByteMemTable.Entry>,
  seen: Nat,
  expected: Nat,
  entry_count: U32,
  block_count: U32,
  block_index: U32
) -> Step:
  match decision:
    case Policy.CursorFinishRejected{}: Failure{cursor, Backup.ResourceLimit{}}
    case Policy.CursorFooter{}:
      footer(cursor, seen, expected, entry_count, block_count, block_index)
    case Policy.CursorFinalBlock{pending_count}:
      block.encoded(cursor, pending, seen, expected, entry_count,
        block_count, block.index.pair(block_index), pending_count,
        CursorFooter{})

def finish.copied(
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pending: List<&1, ByteMemTable.Entry>,
  pending_count: Nat,
  seen_copies: Nat & Nat,
  expected_copies: Nat & Nat,
  entry_count: U32,
  block_count: U32,
  block_index: U32
) -> Step:
  match seen_copies:
    case (seen_check, seen_retained):
      match expected_copies:
        case (expected_check, expected_retained):
          finish.decided(Policy.finish(seen_check, expected_check, pending_count),
            cursor, pending, seen_retained, expected_retained, entry_count,
            block_count, block_index)

# Rejects early cursor end; emits a final partial block before the footer.
def finish(stream: Stream) -> Step:
  match stream:
    case Stream{CursorBlocks{}, cursor, pending, pending_count, seen, expected,
        entry_count, block_count, block_index}:
      finish.copied(cursor, pending, pending_count,
        Backup.nat.duplicate.pair(seen),
        Backup.nat.duplicate.pair(expected),
        entry_count, block_count, block_index)
    case Stream{_, cursor, _, _, _, _, _, _, _}: Failure{cursor, Backup.CodecFailure{}}

def advance.active(
  stream: Stream,
  source_step: VisibleCursor.Step
) -> Step:
  match stream:
    case Stream{CursorBlocks{}, cursor, pending, pending_count, seen, expected,
        entry_count, block_count, block_index}:
      match source_step:
        case VisibleCursor.Item{entry, cursor}:
          item(entry, Some{cursor}, pending, seen, pending_count, expected,
            entry_count, block_count, block_index)
        case VisibleCursor.Skip{cursor}:
          skip(Some{cursor}, pending, pending_count, seen, expected,
            entry_count, block_count, block_index)
        case VisibleCursor.End{}:
          finish(Stream{CursorBlocks{}, None{}, pending, pending_count, seen,
            expected, entry_count, block_count, block_index})
        case VisibleCursor.Error{error}:
          match error:
            case (code, message):
              Failure{None{}, Backup.SourceFailure{code, message}}
    case Stream{CursorFooter{}, cursor, pending, pending_count, seen,
        expected, entry_count, block_count, block_index}:
      footer(cursor, seen, expected, entry_count, block_count, block_index)
    case Stream{CursorFinished{}, _, _, _, _, _, _, _, _}: End{}

# Applies one result returned by the bounded visible cursor.
def advance(stream: Stream, source_step: VisibleCursor.Step) -> Step:
  advance.active(stream, source_step)
