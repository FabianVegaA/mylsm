import Base

# Canonical bounded decimal support for compact storage formats.
# The scanner consumes one character per recursive step and never splits input.

type Error is Data:
  Empty{}
  LeadingZero{}
  NonDigit{}
  Overflow{}
  MissingDelimiter{}

type Stop is Data:
  Delimited{delimiter: Char}
  Complete{}

type Parsed is Data:
  Dec{value: Nat, rest: String}

type Parse is Data:
  Rejected{error: Error}
  Accepted{parsed: Parsed}

type Scan is Data:
  Reading{value: Nat, started: Bool, leading_zero: Bool}
  Finished{value: Nat}
  Failed{error: Error}

def render(n: Nat) -> String:
  Nat.show(n)

def is_digit_code(+code: U32) -> Bool:
  Bool.and(U32.is_le(48, code), U32.is_le(code, 57))

def digit_dec(ok: Bool, code: U32) -> Maybe<&2, Nat>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{U32.to_nat(U32.sub(code, 48))}

def digit_of(c: Char) -> Maybe<&2, Nat>:
  +code = Char.to_u32(c)
  digit_dec(is_digit_code(code), code)

def within_digit_limit(digit_ok: Bool, acc: Nat, digit: Nat, limit: Nat) -> Bool:
  match digit_ok:
    case False{}:
      False{}
    case True{}:
      Nat.is_le(acc, Nat.div(Nat.sub(limit, digit), 10n))

def can_accumulate(acc: Nat, +digit: Nat, +limit: Nat) -> Bool:
  within_digit_limit(Nat.is_le(digit, limit), acc, digit, limit)

def accumulated(ok: Bool, acc: Nat, digit: Nat, leading_zero: Bool) -> Scan:
  match ok:
    case False{}:
      Failed{Overflow{}}
    case True{}:
      Reading{Nat.add(Nat.mul(acc, 10n), digit), True{}, leading_zero}

def next_digit_zero(started: Bool, leading_zero: Bool, +acc: Nat, +digit: Nat, limit: Nat) -> Scan:
  match started:
    case False{}:
      accumulated(can_accumulate(acc, digit, limit), acc, digit, True{})
    case True{}:
      match leading_zero:
        case True{}:
          Failed{LeadingZero{}}
        case False{}:
          accumulated(can_accumulate(acc, digit, limit), acc, digit, False{})

def next_digit_nonzero(leading_zero: Bool, +acc: Nat, +digit: Nat, limit: Nat) -> Scan:
  match leading_zero:
    case True{}:
      Failed{LeadingZero{}}
    case False{}:
      accumulated(can_accumulate(acc, digit, limit), acc, digit, False{})

def next_digit_value(+digit: Nat, started: Bool, leading_zero: Bool, acc: Nat, limit: Nat) -> Scan:
  match digit:
    case 0n:
      next_digit_zero(started, leading_zero, acc, 0n, limit)
    case 1n+p:
      next_digit_nonzero(leading_zero, acc, 1n+p, limit)

def next_digit(+digit: Maybe<&2, Nat>, started: Bool, leading_zero: Bool, acc: Nat, limit: Nat) -> Scan:
  match digit:
    case None{}:
      Failed{NonDigit{}}
    case Some{d}:
      next_digit_value(d, started, leading_zero, acc, limit)

def finish_field(started: Bool, acc: Nat) -> Scan:
  match started:
    case False{}:
      Failed{Empty{}}
    case True{}:
      Finished{acc}

def delimited_step(is_delimiter: Bool, c: Char, acc: Nat, started: Bool, leading_zero: Bool, limit: Nat) -> Scan:
  match is_delimiter:
    case True{}:
      finish_field(started, acc)
    case False{}:
      next_digit(digit_of(c), started, leading_zero, acc, limit)

def scan_step(+c: Char, st: Scan, limit: Nat, stop: Stop) -> Scan:
  match st:
    case Finished{value}:
      Finished{value}
    case Failed{error}:
      Failed{error}
    case Reading{value, started, leading_zero}:
      match stop:
        case Complete{}:
          next_digit(digit_of(c), started, leading_zero, value, limit)
        case Delimited{delimiter}:
          delimited_step(Char.is_eq(c, delimiter), c, value, started, leading_zero, limit)

def complete_end(started: Bool, value: Nat, rest: String) -> Parse:
  match started:
    case False{}:
      Rejected{Empty{}}
    case True{}:
      Accepted{Dec{value, rest}}

def scan_end(st: Scan, rest: String, stop: Stop) -> Parse:
  match st:
    case Finished{value}:
      Accepted{Dec{value, rest}}
    case Failed{error}:
      Rejected{error}
    case Reading{value, started, leading_zero}:
      match stop:
        case Delimited{delimiter}:
          Rejected{MissingDelimiter{}}
        case Complete{}:
          complete_end(started, value, rest)

def scan(rest: String, st: Scan, +limit: Nat, +stop: Stop) -> Parse:
  match rest st:
    case _ Finished{value}:
      Accepted{Dec{value, rest}}
    case _ Failed{error}:
      Rejected{error}
    case SNil{} Reading{value, started, leading_zero}:
      scan_end(Reading{value, started, leading_zero}, "", stop)
    case SCon{c, t} Reading{value, started, leading_zero}:
      scan(t, scan_step(c, Reading{value, started, leading_zero}, limit, stop), limit, stop)

def parse_with_stop(s: String, limit: Nat, stop: Stop) -> Parse:
  scan(s, Reading{0n, False{}, False{}}, limit, stop)

def parse_delimited(s: String, limit: Nat, delimiter: Char) -> Parse:
  parse_with_stop(s, limit, Delimited{delimiter})

def parse_semicolon(s: String, limit: Nat) -> Parse:
  parse_delimited(s, limit, ';')

def parse_complete(s: String, limit: Nat) -> Parse:
  parse_with_stop(s, limit, Complete{})

def parsed_value(p: Parsed) -> Nat:
  match p:
    case Dec{value, rest}:
      value

def parsed_rest(p: Parsed) -> String:
  match p:
    case Dec{value, rest}:
      rest

def is_accepted(p: Parse) -> Bool:
  match p:
    case Rejected{error}:
      False{}
    case Accepted{parsed}:
      True{}
