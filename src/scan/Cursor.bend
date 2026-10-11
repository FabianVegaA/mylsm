import Base
import ../ByteMemTable.bend as ByteMemTable

# Owns the unread suffix of one ordered byte-entry source.
type Cursor is Type:
  CursorReady{entries: List<&1, ByteMemTable.Entry>}
  CursorEnded{}
  CursorClosed{}
  CursorFailed{code: U32, message: String}

# Returns one entry, terminal end, or terminal cursor error.
type Step is Type:
  CursorItem{entry: ByteMemTable.Entry, cursor: Cursor}
  CursorEnd{cursor: Cursor}
  CursorError{cursor: Cursor}

# Creates a cursor over an already ordered bounded source.
def open(entries: List<&1, ByteMemTable.Entry>) -> Cursor:
  CursorReady{entries}

# Returns at most one entry and retains the remaining source suffix.
def next(cursor: Cursor) -> Step:
  match cursor:
    case CursorReady{entries}:
      match entries:
        case Nil{}: CursorEnd{CursorEnded{}}
        case Con{entry, tail}: CursorItem{entry, CursorReady{tail}}
    case CursorEnded{}: CursorEnd{CursorEnded{}}
    case CursorClosed{}: CursorEnd{CursorClosed{}}
    case CursorFailed{code, message}:
      CursorError{CursorFailed{code, message}}

# Closes an active cursor while preserving terminal outcomes.
def close(cursor: Cursor) -> Cursor:
  match cursor:
    case CursorReady{_}: CursorClosed{}
    case CursorEnded{}: CursorEnded{}
    case CursorClosed{}: CursorClosed{}
    case CursorFailed{code, message}: CursorFailed{code, message}
