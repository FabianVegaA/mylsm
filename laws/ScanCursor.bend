import Base
import ../src/scan/Cursor.bend as Cursor
import ../src/scan/RangeCursor.bend as RangeCursor
import ../src/ByteMemTable.bend as ByteMemTable
import ../src/Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.fixture(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def seek.equal(comparison: Bytes.Bytes & Bytes.Bytes & Cmp) -> Bool:
  match comparison:
    case (_, _, EQ{}): True{}
    case _: False{}

def seek.starts.at(entries: List<&1, ByteMemTable.Entry>, query: Bytes.Bytes) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{ByteMemTable.Entry{key, _}, _}:
      seek.equal(Keys.Bytes.cmp.with_inputs(key, query))

def seek.cursor.starts.at(cursor: RangeCursor.Cursor, query: Bytes.Bytes) -> Bool:
  match cursor:
    case RangeCursor.RangeReady{entries}: seek.starts.at(entries, query)
    case _: False{}

# Empty cursors transition directly to their terminal end state.
law empty_cursor_ends:
  {Cursor.next(Cursor.open(Nil{})) == Cursor.CursorEnd{Cursor.CursorEnded{}} : Cursor.Step}

# Explicit closure is terminal and cannot expose another item.
law closed_cursor_stays_closed:
  {Cursor.next(Cursor.close(Cursor.open(Nil{}))) == Cursor.CursorEnd{Cursor.CursorClosed{}} : Cursor.Step}

# An ended cursor remains ended on every later read.
law ended_cursor_stays_ended:
  {Cursor.next(Cursor.CursorEnded{}) == Cursor.CursorEnd{Cursor.CursorEnded{}} : Cursor.Step}

# Closing an ended cursor preserves its terminal result.
law closing_ended_cursor_preserves_end:
  {Cursor.close(Cursor.CursorEnded{}) == Cursor.CursorEnded{} : Cursor.Cursor}

# Read failures remain terminal and preserve their original host error.
law failed_cursor_stays_failed:
  {Cursor.next(Cursor.CursorFailed{5, "read failed"}) ==
    Cursor.CursorError{Cursor.CursorFailed{5, "read failed"}} : Cursor.Step}

# Explicit close does not erase the error observed by an active cursor.
law closing_failed_cursor_preserves_error:
  {Cursor.close(Cursor.CursorFailed{5, "read failed"}) ==
    Cursor.CursorFailed{5, "read failed"} : Cursor.Cursor}

# An entry matching the byte range and prefix is accepted by the range cursor.
law bounded_prefix_match_is_accepted:
  {RangeCursor.matches.key(
    ByteMemTable.bytes.clone(bytes.fixture(Bytes.from_hex("0001"))),
    RangeCursor.Bounds{Some{bytes.fixture(Bytes.from_hex("00"))}, None{}, Some{bytes.fixture(Bytes.from_hex("00"))}}
  ) == True{} : Bool}

# A key outside the requested prefix is rejected even inside the range.
law bounded_prefix_mismatch_is_rejected:
  {RangeCursor.matches.key(
    ByteMemTable.bytes.clone(bytes.fixture(Bytes.from_hex("ff"))),
    RangeCursor.Bounds{Some{bytes.fixture(Bytes.from_hex("00"))}, None{}, Some{bytes.fixture(Bytes.from_hex("00"))}}
  ) == False{} : Bool}

# Positions at the first key greater than or equal to the inclusive lower bound.
law lower_bound_seeks_past_earlier_keys:
  {seek.starts.at(RangeCursor.seek([
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("00")), None{}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("01")), None{}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("02")), None{}}
  ], Some{bytes.fixture(Bytes.from_hex("02"))}), bytes.fixture(Bytes.from_hex("02"))) == True{} : Bool}

# Positions an active cursor at its later inclusive seek key.
law active_cursor_seek_positions_at_lower_bound:
  {seek.cursor.starts.at(RangeCursor.seek.cursor(RangeCursor.open([
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("00")), None{}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("01")), None{}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("02")), None{}}
  ]), Some{bytes.fixture(Bytes.from_hex("02"))}),
    bytes.fixture(Bytes.from_hex("02"))) == True{} : Bool}
