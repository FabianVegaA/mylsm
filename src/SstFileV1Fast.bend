import Base
import ./Decimal.bend as Decimal
import ./Keys.bend as Keys
import ./Manifest.bend as Manifest
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./Wal.bend as Wal

# Single-pass decoder for the legacy SSTable v1 representation:
#   T<level-dashes>;<wal-length-dashes>;<wal>#<decimal checksum>
# Fields and entries are accumulated in reverse, avoiding append, split, and join.

# Errors describe the first structural failure observed by the decoder.
type Error is Data:
  UnknownVersion{}
  MalformedHeader{}
  InvalidWalTag{}
  InvalidWalLength{}
  TruncatedWal{}
  RecordChecksumMismatch{}
  MissingRecordTerminator{}
  TruncatedChecksum{}
  MalformedChecksum{}
  ChecksumMismatch{}
  TrailingData{}

type Tag is Data:
  PutTag{}
  DelTag{}

type Phase is Data:
  NeedT{}
  ReadLevel{level: Nat}
  ReadWalLength{length: Nat}
  WalTag{}
  WalKeyLength{tag: Tag, length: Nat}
  WalKey{tag: Tag, remaining: Nat, reversed: String}
  WalValueLength{key: String, length: Nat}
  WalValue{key: String, remaining: Nat, reversed: String}
  WalChecksum{tag: Tag, key: String, value: String, remaining: Nat, reversed: String}
  WalSemi{entry: MemTable.Entry}
  NeedHash{}
  ReadChecksum{scan: Decimal.Scan}

type Transition is Data:
  Next{phase: Phase}
  LevelRead{level: Nat}
  WalLengthRead{length: Nat}
  EntryRead{entry: MemTable.Entry}
  Rejected{error: Error}

type Decoder is Data:
  Dec{
    phase: Phase,
    wal_remaining: Nat,
    previous_key: Maybe<&2, String>,
    strict: Bool,
    reversed_entries: List<&2, MemTable.Entry>,
    level: Nat,
    count: Nat,
    hash: U32
  }
  DecoderRejected{error: Error}

type ParseResult is Data:
  ParseRejected{error: Error}
  Parsed{table: Sstable.Table}

# --- Character-level transitions ---

def body_hash(hash: U32, c: Char) -> U32:
  U32.add(U32.mul(hash, 31), Char.to_u32(c))

def expected(ok: Bool, next: Phase, error: Error) -> Transition:
  match ok:
    case True{}:
      Next{next}
    case False{}:
      Rejected{error}

def level_step(is_dash: Bool, is_semi: Bool, level: Nat) -> Transition:
  match is_dash:
    case True{}:
      Next{ReadLevel{1n+level}}
    case False{}:
      match is_semi:
        case True{}:
          LevelRead{level}
        case False{}:
          Rejected{MalformedHeader{}}

def wal_length_step(is_dash: Bool, is_semi: Bool, length: Nat) -> Transition:
  match is_dash:
    case True{}:
      Next{ReadWalLength{1n+length}}
    case False{}:
      match is_semi:
        case True{}:
          WalLengthRead{length}
        case False{}:
          Rejected{MalformedHeader{}}

def tag_del(is_del: Bool) -> Transition:
  match is_del:
    case True{}:
      Next{WalKeyLength{DelTag{}, 0n}}
    case False{}:
      Rejected{InvalidWalTag{}}

def tag_put(is_put: Bool, +c: Char) -> Transition:
  match is_put:
    case True{}:
      Next{WalKeyLength{PutTag{}, 0n}}
    case False{}:
      tag_del(Char.is_eq(c, 'D'))

def tag_step(+c: Char) -> Transition:
  tag_put(Char.is_eq(c, 'P'), c)

def checksum_phase(tag: Tag, key: String, value: String) -> Transition:
  Next{WalChecksum{tag, key, value, 4n, ""}}

def key_length_done(tag: Tag, length: Nat) -> Transition:
  match tag length:
    case PutTag{} 0n:
      Next{WalValueLength{"", 0n}}
    case DelTag{} 0n:
      checksum_phase(DelTag{}, "", "")
    case PutTag{} 1n+rest:
      Next{WalKey{PutTag{}, 1n+rest, ""}}
    case DelTag{} 1n+rest:
      Next{WalKey{DelTag{}, 1n+rest, ""}}

def key_length_step(is_dash: Bool, is_colon: Bool, tag: Tag, length: Nat) -> Transition:
  match is_dash:
    case True{}:
      Next{WalKeyLength{tag, 1n+length}}
    case False{}:
      match is_colon:
        case True{}:
          key_length_done(tag, length)
        case False{}:
          Rejected{TruncatedWal{}}

def key_last(tag: Tag, reversed: String) -> Transition:
  match tag:
    case PutTag{}:
      Next{WalValueLength{String.reverse(reversed), 0n}}
    case DelTag{}:
      checksum_phase(DelTag{}, String.reverse(reversed), "")

def key_step(tag: Tag, remaining: Nat, reversed: String, c: Char) -> Transition:
  match remaining:
    case 0n:
      Rejected{TruncatedWal{}}
    case 1n+rest:
      match rest:
        case 0n:
          key_last(tag, SCon{c, reversed})
        case 1n+more:
          Next{WalKey{tag, 1n+more, SCon{c, reversed}}}

def value_length_done(key: String, length: Nat) -> Transition:
  match length:
    case 0n:
      checksum_phase(PutTag{}, key, "")
    case 1n+rest:
      Next{WalValue{key, 1n+rest, ""}}

def value_length_step(is_dash: Bool, is_colon: Bool, key: String, length: Nat) -> Transition:
  match is_dash:
    case True{}:
      Next{WalValueLength{key, 1n+length}}
    case False{}:
      match is_colon:
        case True{}:
          value_length_done(key, length)
        case False{}:
          Rejected{TruncatedWal{}}

def value_step(key: String, remaining: Nat, reversed: String, c: Char) -> Transition:
  match remaining:
    case 0n:
      Rejected{TruncatedWal{}}
    case 1n+rest:
      match rest:
        case 0n:
          checksum_phase(PutTag{}, key, String.reverse(SCon{c, reversed}))
        case 1n+more:
          Next{WalValue{key, 1n+more, SCon{c, reversed}}}

def checked_record(equal: Bool, tag: Tag, key: String, value: String) -> Transition:
  match equal:
    case False{}:
      Rejected{RecordChecksumMismatch{}}
    case True{}:
      match tag:
        case PutTag{}:
          Next{WalSemi{MemTable.Entry{key, Some{value}}}}
        case DelTag{}:
          Next{WalSemi{MemTable.Entry{key, None{}}}}

def checksum_expected(tag: Tag, +key: String, +value: String) -> String:
  match tag:
    case PutTag{}:
      Wal.chk4(Wal.hash3('P', key, value))
    case DelTag{}:
      Wal.chk4(Wal.hash3('D', key, value))

def checksum_last(+tag: Tag, +key: String, +value: String, reversed: String) -> Transition:
  +actual = String.reverse(reversed)
  checked_record(String.eq(actual, checksum_expected(tag, key, value)), tag, key, value)

def checksum_step(tag: Tag, key: String, value: String, remaining: Nat, reversed: String, c: Char) -> Transition:
  match remaining:
    case 0n:
      Rejected{TruncatedWal{}}
    case 1n+rest:
      match rest:
        case 0n:
          checksum_last(tag, key, value, SCon{c, reversed})
        case 1n+more:
          Next{WalChecksum{tag, key, value, 1n+more, SCon{c, reversed}}}

def semi_step(is_semi: Bool, entry: MemTable.Entry) -> Transition:
  match is_semi:
    case True{}:
      EntryRead{entry}
    case False{}:
      Rejected{MissingRecordTerminator{}}

def checksum_scan(scan: Decimal.Scan) -> Transition:
  match scan:
    case Decimal.Reading{value, started, leading_zero}:
      Next{ReadChecksum{Decimal.Reading{value, started, leading_zero}}}
    case Decimal.Finished{value}:
      Rejected{TrailingData{}}
    case Decimal.Failed{error}:
      Rejected{MalformedChecksum{}}

def phase_step(phase: Phase, +c: Char) -> Transition:
  match phase:
    case NeedT{}:
      expected(Char.is_eq(c, 'T'), ReadLevel{0n}, UnknownVersion{})
    case ReadLevel{level}:
      level_step(Char.is_eq(c, '-'), Char.is_eq(c, ';'), level)
    case ReadWalLength{length}:
      wal_length_step(Char.is_eq(c, '-'), Char.is_eq(c, ';'), length)
    case WalTag{}:
      tag_step(c)
    case WalKeyLength{tag, length}:
      key_length_step(Char.is_eq(c, '-'), Char.is_eq(c, ':'), tag, length)
    case WalKey{tag, remaining, reversed}:
      key_step(tag, remaining, reversed, c)
    case WalValueLength{key, length}:
      value_length_step(Char.is_eq(c, '-'), Char.is_eq(c, ':'), key, length)
    case WalValue{key, remaining, reversed}:
      value_step(key, remaining, reversed, c)
    case WalChecksum{tag, key, value, remaining, reversed}:
      checksum_step(tag, key, value, remaining, reversed, c)
    case WalSemi{entry}:
      semi_step(Char.is_eq(c, ';'), entry)
    case NeedHash{}:
      expected(Char.is_eq(c, '#'), ReadChecksum{Decimal.Reading{0n, False{}, False{}}}, TruncatedChecksum{})
    case ReadChecksum{scan}:
      checksum_scan(Decimal.scan_step(c, scan, 4294967295n, Decimal.Complete{}))

# --- Decoder state and exact WAL-boundary enforcement ---

def decoder_next(phase: Phase, wal_remaining: Nat, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> Decoder:
  Dec{phase, wal_remaining, previous, strict, entries, level, count, hash}

def wal_length_transition(length: Nat, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> Decoder:
  match length:
    case 0n:
      decoder_next(NeedHash{}, 0n, previous, strict, entries, level, count, hash)
    case 1n+rest:
      decoder_next(WalTag{}, 1n+rest, previous, strict, entries, level, count, hash)

def strict_cmp(cmp: Cmp, key: String) -> (Maybe<&2, String> & Bool):
  match cmp:
    case LT{}:
      (Some{key}, True{})
    case _:
      (Some{key}, False{})

def strict_next(previous: Maybe<&2, String>, +key: String, strict: Bool) -> (Maybe<&2, String> & Bool):
  match previous strict:
    case None{} False{}:
      (Some{key}, False{})
    case Some{old} False{}:
      (Some{key}, False{})
    case None{} True{}:
      (Some{key}, True{})
    case Some{old} True{}:
      strict_cmp(Keys.cmp(old, key), key)

def ordered_entry(order: (Maybe<&2, String> & Bool), entry: MemTable.Entry, next_phase: Phase, remaining: Nat, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> Decoder:
  match order:
    case (previous, strict):
      decoder_next(next_phase, remaining, previous, strict, Con{entry, entries}, level, Nat.add(count, 1n), hash)

def entry_transition(+entry: MemTable.Entry, next_phase: Phase, remaining: Nat, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> Decoder:
  match entry:
    case MemTable.Entry{+key, +value}:
      ordered_entry(strict_next(previous, key, strict), MemTable.Entry{key, value}, next_phase, remaining, entries, level, count, hash)

def regular_transition(transition: Transition, wal_remaining: Nat, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> Decoder:
  match transition:
    case Rejected{error}:
      DecoderRejected{error}
    case Next{phase}:
      decoder_next(phase, wal_remaining, previous, strict, entries, level, count, hash)
    case LevelRead{new_level}:
      decoder_next(ReadWalLength{0n}, wal_remaining, previous, strict, entries, new_level, count, hash)
    case WalLengthRead{length}:
      wal_length_transition(length, previous, strict, entries, level, count, hash)
    case EntryRead{entry}:
      DecoderRejected{InvalidWalLength{}}

def wal_next_at_end(phase: Phase, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> Decoder:
  DecoderRejected{TruncatedWal{}}

def wal_next_not_end(phase: Phase, remaining: Nat, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> Decoder:
  decoder_next(phase, remaining, previous, strict, entries, level, count, hash)

def wal_next(remaining: Nat, phase: Phase, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> Decoder:
  match remaining:
    case 0n:
      wal_next_at_end(phase, previous, strict, entries, level, count, hash)
    case 1n+rest:
      wal_next_not_end(phase, 1n+rest, previous, strict, entries, level, count, hash)

def wal_entry_phase(remaining: Nat) -> Phase:
  match remaining:
    case 0n:
      NeedHash{}
    case 1n+rest:
      WalTag{}

def wal_transition(transition: Transition, +remaining: Nat, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> Decoder:
  match transition:
    case Rejected{error}:
      DecoderRejected{error}
    case Next{phase}:
      wal_next(remaining, phase, previous, strict, entries, level, count, hash)
    case EntryRead{entry}:
      entry_transition(entry, wal_entry_phase(remaining), remaining, previous, strict, entries, level, count, hash)
    case _:
      DecoderRejected{InvalidWalLength{}}

def wal_decoder_step(phase: Phase, wal_remaining: Nat, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32, +c: Char) -> Decoder:
  match wal_remaining:
    case 0n:
      DecoderRejected{InvalidWalLength{}}
    case 1n+rest:
      +next_hash = body_hash(hash, c)
      wal_transition(phase_step(phase, c), rest, previous, strict, entries, level, count, next_hash)

def regular_hash(phase: Phase, hash: U32, c: Char) -> U32:
  match phase:
    case NeedHash{}:
      hash
    case ReadChecksum{scan}:
      hash
    case _:
      body_hash(hash, c)

def regular_decoder_step(+phase: Phase, wal_remaining: Nat, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32, +c: Char) -> Decoder:
  +next_hash = regular_hash(phase, hash, c)
  regular_transition(phase_step(phase, c), wal_remaining, previous, strict, entries, level, count, next_hash)

def decoder_step_live(phase: Phase, wal_remaining: Nat, previous: Maybe<&2, String>, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32, c: Char) -> Decoder:
  match phase:
    case WalTag{}:
      wal_decoder_step(WalTag{}, wal_remaining, previous, strict, entries, level, count, hash, c)
    case WalKeyLength{tag, length}:
      wal_decoder_step(WalKeyLength{tag, length}, wal_remaining, previous, strict, entries, level, count, hash, c)
    case WalKey{tag, remaining, reversed}:
      wal_decoder_step(WalKey{tag, remaining, reversed}, wal_remaining, previous, strict, entries, level, count, hash, c)
    case WalValueLength{key, length}:
      wal_decoder_step(WalValueLength{key, length}, wal_remaining, previous, strict, entries, level, count, hash, c)
    case WalValue{key, remaining, reversed}:
      wal_decoder_step(WalValue{key, remaining, reversed}, wal_remaining, previous, strict, entries, level, count, hash, c)
    case WalChecksum{tag, key, value, remaining, reversed}:
      wal_decoder_step(WalChecksum{tag, key, value, remaining, reversed}, wal_remaining, previous, strict, entries, level, count, hash, c)
    case WalSemi{entry}:
      wal_decoder_step(WalSemi{entry}, wal_remaining, previous, strict, entries, level, count, hash, c)
    case _:
      regular_decoder_step(phase, wal_remaining, previous, strict, entries, level, count, hash, c)

def decoder_step(decoder: Decoder, c: Char) -> Decoder:
  match decoder:
    case DecoderRejected{error}:
      DecoderRejected{error}
    case Dec{phase, wal_remaining, previous_key, strict, reversed_entries, level, count, hash}:
      decoder_step_live(phase, wal_remaining, previous_key, strict, reversed_entries, level, count, hash, c)

# --- EOF validation and legacy-compatible construction ---

def build_table(strict: Bool, +entries: List<&2, MemTable.Entry>, level: Nat, count: Nat) -> Sstable.Table:
  match strict:
    case True{}:
      Sstable.from_sorted_unique(entries, level)
    case False{}:
      Sstable.build(entries, level, count)

def checksum_decision(equal: Bool, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat) -> ParseResult:
  match equal:
    case False{}:
      ParseRejected{ChecksumMismatch{}}
    case True{}:
      Parsed{build_table(strict, List.reverse(&2, MemTable.Entry, entries), level, count)}

def checksum_value(parsed: Decimal.Parse, strict: Bool, entries: List<&2, MemTable.Entry>, level: Nat, count: Nat, hash: U32) -> ParseResult:
  match parsed:
    case Decimal.Rejected{error}:
      ParseRejected{TruncatedChecksum{}}
    case Decimal.Accepted{Decimal.Dec{value, rest}}:
      checksum_decision(Nat.is_eq(value, U32.to_nat(hash)), strict, entries, level, count)

def finish_decoder(decoder: Decoder) -> ParseResult:
  match decoder:
    case DecoderRejected{error}:
      ParseRejected{error}
    case Dec{phase, wal_remaining, previous_key, strict, reversed_entries, level, count, hash}:
      match phase:
        case ReadChecksum{scan}:
          checksum_value(Decimal.scan_end(scan, "", Decimal.Complete{}), strict, reversed_entries, level, count, hash)
        case NeedT{}:
          ParseRejected{UnknownVersion{}}
        case ReadLevel{level}:
          ParseRejected{MalformedHeader{}}
        case ReadWalLength{length}:
          ParseRejected{MalformedHeader{}}
        case NeedHash{}:
          ParseRejected{TruncatedChecksum{}}
        case _:
          ParseRejected{TruncatedWal{}}

def decode_go(rest: String, decoder: Decoder) -> ParseResult:
  match rest:
    case SNil{}:
      finish_decoder(decoder)
    case SCon{c, t}:
      decode_go(t, decoder_step(decoder, c))

def parse_result(s: String) -> ParseResult:
  decode_go(s, Dec{NeedT{}, 0n, None{}, True{}, Nil{}, 0n, 0n, 7})

def parse_wrap(result: ParseResult) -> Maybe<&2, Sstable.Table>:
  match result:
    case ParseRejected{error}:
      None{}
    case Parsed{table}:
      Some{table}

def parse(s: String) -> Maybe<&2, Sstable.Table>:
  parse_wrap(parse_result(s))

def parser_decides(result: ParseResult) -> Bool:
  True{}
