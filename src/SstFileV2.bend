import Base
import ./Decimal.bend as Decimal
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SstChecksum.bend as SstChecksum

# Compact SSTable v2:
#   S2;<level>;<count>;<entries>#<checksum>
#   P;<key-length>;<value-length>;<key><value>
#   D;<key-length>;<key>
# The checksum is SstChecksum.digest(body) (hub SHA-256, hex).

def max_file_chars() -> Nat:
  Nat.add(4294967295n, 1n)

def max_entries() -> Nat:
  16777216n

def max_key_chars() -> Nat:
  16777216n

def max_value_chars() -> Nat:
  1073741824n

def max_level() -> Nat:
  255n

def read_chunk_chars() -> Nat:
  1048576n

type Error is Data:
  UnknownVersion{}
  MalformedDecimal{}
  DecimalOverflow{}
  InvalidLevel{}
  EntryCountExceeded{}
  InvalidEntryTag{}
  KeyLengthExceeded{}
  ValueLengthExceeded{}
  TruncatedHeader{}
  TruncatedEntry{}
  TruncatedChecksum{}
  UnsortedOrDuplicate{}
  ChecksumMismatch{}
  TrailingData{}
  FileTooLarge{}

type Tag is Data:
  PutTag{}
  DelTag{}

type Phase is Data:
  NeedS{}
  Need2{}
  NeedHeaderSemi{}
  ReadLevel{scan: Decimal.Scan}
  ReadCount{scan: Decimal.Scan}
  ReadTag{}
  ReadTagSemi{tag: Tag}
  ReadKeyLength{tag: Tag, scan: Decimal.Scan}
  ReadValueLength{key_length: Nat, scan: Decimal.Scan}
  ReadKey{tag: Tag, remaining: Nat, value_length: Nat, reversed: String}
  ReadValue{key: String, remaining: Nat, reversed: String}
  NeedHash{}
  ReadChecksum{reversed: String}

type Transition is Data:
  Next{phase: Phase}
  LevelRead{level: Nat}
  CountRead{count: Nat}
  EntryRead{entry: MemTable.Entry}
  TransitionRejected{error: Error}

type Decoder is Data:
  Dec{
    phase: Phase,
    remaining_entries: Nat,
    previous_key: Maybe<&2, String>,
    reversed_entries: List<&2, MemTable.Entry>,
    level: Nat,
    declared_count: Nat,
    body_rev: String,
    consumed: Nat
  }
  DecoderRejected{error: Error}

type ParseResult is Data:
  ParseRejected{error: Error}
  Parsed{table: Sstable.Table}

# --- Serialization: reversed fragments followed by one String.join ---

def entry_fragments(entries: List<&2, MemTable.Entry>, acc: List<&2, String>) -> List<&2, String>:
  match entries:
    case Nil{}:
      acc
    case Con{MemTable.Entry{+key, +val}, rest}:
      match val:
        case None{}:
          entry_fragments(rest, Con{key, Con{";", Con{Decimal.render(String.length(key)), Con{"D;", acc}}}})
        case Some{+value}:
          entry_fragments(rest, Con{value, Con{key, Con{";", Con{Decimal.render(String.length(value)), Con{";", Con{Decimal.render(String.length(key)), Con{"P;", acc}}}}}}})

def header_fragments(count: Nat, level: Nat) -> List<&2, String>:
  Con{";", Con{Decimal.render(count), Con{";", Con{Decimal.render(level), Con{"S2;", Nil{}}}}}}

def body(+entries: List<&2, MemTable.Entry>, level: Nat) -> String:
  +header_reversed = header_fragments(List.length(&2, MemTable.Entry, entries), level)
  String.join(List.reverse(&2, String, entry_fragments(entries, header_reversed)), "")

def serialize(+entries: List<&2, MemTable.Entry>, level: Nat) -> String:
  +encoded_body = body(entries, level)
  encoded_body ++ "#" ++ SstChecksum.digest(encoded_body)

# --- Pure one-character decoder transitions ---

def expected_char(ok: Bool, next: Phase, error: Error) -> Transition:
  match ok:
    case True{}:
      Next{next}
    case False{}:
      TransitionRejected{error}

def decimal_error(error: Decimal.Error, overflow: Error) -> Transition:
  match error:
    case Decimal.Overflow{}:
      TransitionRejected{overflow}
    case _:
      TransitionRejected{MalformedDecimal{}}

def level_scan(scan: Decimal.Scan) -> Transition:
  match scan:
    case Decimal.Reading{value, started, leading_zero}:
      Next{ReadLevel{Decimal.Reading{value, started, leading_zero}}}
    case Decimal.Finished{value}:
      LevelRead{value}
    case Decimal.Failed{error}:
      decimal_error(error, InvalidLevel{})

def count_scan(scan: Decimal.Scan) -> Transition:
  match scan:
    case Decimal.Reading{value, started, leading_zero}:
      Next{ReadCount{Decimal.Reading{value, started, leading_zero}}}
    case Decimal.Finished{value}:
      CountRead{value}
    case Decimal.Failed{error}:
      decimal_error(error, EntryCountExceeded{})

def delete_key_length(value: Nat) -> Transition:
  match value:
    case 0n:
      EntryRead{MemTable.Entry{"", None{}}}
    case 1n+rest:
      Next{ReadKey{DelTag{}, 1n+rest, 0n, ""}}

def key_length_done(tag: Tag, value: Nat) -> Transition:
  match tag:
    case PutTag{}:
      Next{ReadValueLength{value, Decimal.Reading{0n, False{}, False{}}}}
    case DelTag{}:
      delete_key_length(value)

def key_length_scan(tag: Tag, scan: Decimal.Scan) -> Transition:
  match scan:
    case Decimal.Reading{value, started, leading_zero}:
      Next{ReadKeyLength{tag, Decimal.Reading{value, started, leading_zero}}}
    case Decimal.Failed{error}:
      decimal_error(error, KeyLengthExceeded{})
    case Decimal.Finished{value}:
      key_length_done(tag, value)

def put_lengths(key_length: Nat, value_length: Nat) -> Transition:
  match key_length:
    case 0n:
      match value_length:
        case 0n:
          EntryRead{MemTable.Entry{"", Some{""}}}
        case 1n+v:
          Next{ReadValue{"", 1n+v, ""}}
    case 1n+k:
      Next{ReadKey{PutTag{}, 1n+k, value_length, ""}}

def value_length_scan(key_length: Nat, scan: Decimal.Scan) -> Transition:
  match scan:
    case Decimal.Reading{value, started, leading_zero}:
      Next{ReadValueLength{key_length, Decimal.Reading{value, started, leading_zero}}}
    case Decimal.Failed{error}:
      decimal_error(error, ValueLengthExceeded{})
    case Decimal.Finished{value}:
      put_lengths(key_length, value)

def tag_del(is_del: Bool) -> Transition:
  match is_del:
    case True{}:
      Next{ReadTagSemi{DelTag{}}}
    case False{}:
      TransitionRejected{InvalidEntryTag{}}

def tag_put(is_put: Bool, c: Char) -> Transition:
  match is_put:
    case True{}:
      Next{ReadTagSemi{PutTag{}}}
    case False{}:
      tag_del(Char.is_eq(c, 'D'))

def tag_step(+c: Char) -> Transition:
  tag_put(Char.is_eq(c, 'P'), c)

def key_last(tag: Tag, value_length: Nat, reversed: String) -> Transition:
  match tag:
    case DelTag{}:
      EntryRead{MemTable.Entry{String.reverse(reversed), None{}}}
    case PutTag{}:
      match value_length:
        case 0n:
          EntryRead{MemTable.Entry{String.reverse(reversed), Some{""}}}
        case 1n+v:
          Next{ReadValue{String.reverse(reversed), 1n+v, ""}}

def key_step(tag: Tag, remaining: Nat, value_length: Nat, reversed: String, c: Char) -> Transition:
  match remaining:
    case 0n:
      TransitionRejected{TruncatedEntry{}}
    case 1n+rest:
      match rest:
        case 0n:
          key_last(tag, value_length, SCon{c, reversed})
        case 1n+more:
          Next{ReadKey{tag, 1n+more, value_length, SCon{c, reversed}}}

def value_step(key: String, remaining: Nat, reversed: String, c: Char) -> Transition:
  match remaining:
    case 0n:
      TransitionRejected{TruncatedEntry{}}
    case 1n+rest:
      match rest:
        case 0n:
          EntryRead{MemTable.Entry{key, Some{String.reverse(SCon{c, reversed})}}}
        case 1n+more:
          Next{ReadValue{key, 1n+more, SCon{c, reversed}}}

def checksum_step(+reversed: String, +c: Char) -> Transition:
  Next{ReadChecksum{SCon{c, reversed}}}

def phase_step(phase: Phase, +c: Char) -> Transition:
  match phase:
    case NeedS{}:
      expected_char(Char.is_eq(c, 'S'), Need2{}, UnknownVersion{})
    case Need2{}:
      expected_char(Char.is_eq(c, '2'), NeedHeaderSemi{}, UnknownVersion{})
    case NeedHeaderSemi{}:
      expected_char(Char.is_eq(c, ';'), ReadLevel{Decimal.Reading{0n, False{}, False{}}}, UnknownVersion{})
    case ReadLevel{scan}:
      level_scan(Decimal.scan_step(c, scan, max_level(), Decimal.Delimited{';'}))
    case ReadCount{scan}:
      count_scan(Decimal.scan_step(c, scan, max_entries(), Decimal.Delimited{';'}))
    case ReadTag{}:
      tag_step(c)
    case ReadTagSemi{tag}:
      expected_char(Char.is_eq(c, ';'), ReadKeyLength{tag, Decimal.Reading{0n, False{}, False{}}}, InvalidEntryTag{})
    case ReadKeyLength{tag, scan}:
      key_length_scan(tag, Decimal.scan_step(c, scan, max_key_chars(), Decimal.Delimited{';'}))
    case ReadValueLength{key_length, scan}:
      value_length_scan(key_length, Decimal.scan_step(c, scan, max_value_chars(), Decimal.Delimited{';'}))
    case ReadKey{tag, remaining, value_length, reversed}:
      key_step(tag, remaining, value_length, reversed, c)
    case ReadValue{key, remaining, reversed}:
      value_step(key, remaining, reversed, c)
    case NeedHash{}:
      expected_char(Char.is_eq(c, '#'), ReadChecksum{SNil{}}, TruncatedChecksum{})
    case ReadChecksum{reversed}:
      checksum_step(reversed, c)

def phase_bodies(phase: Phase) -> Bool:
  match phase:
    case NeedHash{}:
      False{}
    case ReadChecksum{reversed}:
      False{}
    case _:
      True{}

def select_body(keeps: Bool, body_rev: String, c: Char) -> String:
  match keeps:
    case True{}:
      SCon{c, body_rev}
    case False{}:
      body_rev

# --- Applying transitions enforces exact count and strict key order ---

def decoder_next(phase: Phase, remaining: Nat, previous: Maybe<&2, String>, entries: List<&2, MemTable.Entry>, level: Nat, declared: Nat, body_rev: String, consumed: Nat) -> Decoder:
  Dec{phase, remaining, previous, entries, level, declared, body_rev, consumed}

def count_transition(count: Nat, previous: Maybe<&2, String>, entries: List<&2, MemTable.Entry>, level: Nat, body_rev: String, consumed: Nat) -> Decoder:
  match count:
    case 0n:
      decoder_next(NeedHash{}, 0n, previous, entries, level, 0n, body_rev, consumed)
    case 1n++rest:
      decoder_next(ReadTag{}, 1n+rest, previous, entries, level, 1n+rest, body_rev, consumed)

def ordered_entry(entry: MemTable.Entry, remaining: Nat, entries: List<&2, MemTable.Entry>, level: Nat, declared: Nat, body_rev: String, consumed: Nat) -> Decoder:
  match entry:
    case MemTable.Entry{+key, +val}:
      match remaining:
        case 0n:
          DecoderRejected{TrailingData{}}
        case 1n+rest:
          match rest:
            case 0n:
              decoder_next(NeedHash{}, 0n, Some{key}, Con{MemTable.Entry{key, val}, entries}, level, declared, body_rev, consumed)
            case 1n+more:
              decoder_next(ReadTag{}, 1n+more, Some{key}, Con{MemTable.Entry{key, val}, entries}, level, declared, body_rev, consumed)

def order_decision(cmp: Cmp, entry: MemTable.Entry, remaining: Nat, entries: List<&2, MemTable.Entry>, level: Nat, declared: Nat, body_rev: String, consumed: Nat) -> Decoder:
  match cmp:
    case LT{}:
      ordered_entry(entry, remaining, entries, level, declared, body_rev, consumed)
    case _:
      DecoderRejected{UnsortedOrDuplicate{}}

def entry_transition(+entry: MemTable.Entry, remaining: Nat, previous: Maybe<&2, String>, entries: List<&2, MemTable.Entry>, level: Nat, declared: Nat, body_rev: String, consumed: Nat) -> Decoder:
  match entry:
    case MemTable.Entry{+key, +val}:
      match previous:
        case None{}:
          ordered_entry(MemTable.Entry{key, val}, remaining, entries, level, declared, body_rev, consumed)
        case Some{+old}:
          order_decision(Keys.cmp(old, key), MemTable.Entry{key, val}, remaining, entries, level, declared, body_rev, consumed)

def apply_transition(transition: Transition, remaining: Nat, previous: Maybe<&2, String>, entries: List<&2, MemTable.Entry>, level: Nat, declared: Nat, body_rev: String, consumed: Nat) -> Decoder:
  match transition:
    case TransitionRejected{error}:
      DecoderRejected{error}
    case Next{phase}:
      decoder_next(phase, remaining, previous, entries, level, declared, body_rev, consumed)
    case LevelRead{new_level}:
      decoder_next(ReadCount{Decimal.Reading{0n, False{}, False{}}}, remaining, previous, entries, new_level, declared, body_rev, consumed)
    case CountRead{count}:
      count_transition(count, previous, entries, level, body_rev, consumed)
    case EntryRead{entry}:
      entry_transition(entry, remaining, previous, entries, level, declared, body_rev, consumed)

def decoder_step_live(+phase: Phase, remaining: Nat, previous: Maybe<&2, String>, entries: List<&2, MemTable.Entry>, level: Nat, declared: Nat, body_rev: String, consumed: Nat, +c: Char) -> Decoder:
  +next_body = select_body(phase_bodies(phase), body_rev, c)
  apply_transition(phase_step(phase, c), remaining, previous, entries, level, declared, next_body, Nat.add(consumed, 1n))

def decoder_step_bounded(within: Bool, phase: Phase, remaining: Nat, previous: Maybe<&2, String>, entries: List<&2, MemTable.Entry>, level: Nat, declared: Nat, body_rev: String, consumed: Nat, c: Char) -> Decoder:
  match within:
    case False{}:
      DecoderRejected{FileTooLarge{}}
    case True{}:
      decoder_step_live(phase, remaining, previous, entries, level, declared, body_rev, consumed, c)

def decoder_step(decoder: Decoder, c: Char) -> Decoder:
  match decoder:
    case DecoderRejected{error}:
      DecoderRejected{error}
    case Dec{phase, remaining_entries, previous_key, reversed_entries, level, declared_count, body_rev, +consumed}:
      decoder_step_bounded(Nat.is_lt(consumed, max_file_chars()), phase, remaining_entries, previous_key, reversed_entries, level, declared_count, body_rev, consumed, c)

# --- EOF validation and table construction ---

def checksum_decision(equal: Bool, entries: List<&2, MemTable.Entry>, level: Nat) -> ParseResult:
  match equal:
    case False{}:
      ParseRejected{ChecksumMismatch{}}
    case True{}:
      Parsed{Sstable.from_sorted_unique(List.reverse(&2, MemTable.Entry, entries), level)}

def checksum_value(+claimed_rev: String, entries: List<&2, MemTable.Entry>, level: Nat, +body_rev: String) -> ParseResult:
  checksum_decision(SstChecksum.verify(String.reverse(body_rev), String.reverse(claimed_rev)), entries, level)

def finish_decoder(decoder: Decoder) -> ParseResult:
  match decoder:
    case DecoderRejected{error}:
      ParseRejected{error}
    case Dec{phase, remaining_entries, previous_key, reversed_entries, level, declared_count, body_rev, consumed}:
      match phase:
        case ReadChecksum{reversed}:
          checksum_value(reversed, reversed_entries, level, body_rev)
        case NeedS{}:
          ParseRejected{TruncatedHeader{}}
        case Need2{}:
          ParseRejected{TruncatedHeader{}}
        case NeedHeaderSemi{}:
          ParseRejected{TruncatedHeader{}}
        case ReadLevel{scan}:
          ParseRejected{TruncatedHeader{}}
        case ReadCount{scan}:
          ParseRejected{TruncatedHeader{}}
        case NeedHash{}:
          ParseRejected{TruncatedChecksum{}}
        case _:
          ParseRejected{TruncatedEntry{}}

def decode_go(rest: String, decoder: Decoder) -> ParseResult:
  match rest:
    case SNil{}:
      finish_decoder(decoder)
    case SCon{c, t}:
      decode_go(t, decoder_step(decoder, c))

def parse_result(s: String) -> ParseResult:
  decode_go(s, Dec{NeedS{}, 0n, None{}, Nil{}, 0n, 0n, "", 0n})

def parse_wrap(result: ParseResult) -> Maybe<&2, Sstable.Table>:
  match result:
    case ParseRejected{error}:
      None{}
    case Parsed{table}:
      Some{table}

def parse(s: String) -> Maybe<&2, Sstable.Table>:
  parse_wrap(parse_result(s))

# Useful pure projections for laws and streaming-state agreement.
def parser_decides(_result: ParseResult) -> Bool:
  True{}

def error_of(result: ParseResult) -> Maybe<&2, Error>:
  match result:
    case ParseRejected{error}:
      Some{error}
    case Parsed{table}:
      None{}
