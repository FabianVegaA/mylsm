import Base

# Represent LexerResult data used by the interactive command lexer.
type LexerResult is Data:
  LexSuccess{tokens: List<&2, String>}
  LexError{message: String}

# Represent LexerMode data used by the interactive command lexer.
type LexerMode is Data:
  LexBetween{}
  LexBare{}
  LexQuoted{}
  LexEscape{}

# Represent LexerChar data used by the interactive command lexer.
type LexerChar is Data:
  LexWhitespace{value: Char}
  LexQuote{}
  LexBackslash{}
  LexEscapeN{}
  LexEscapeT{}
  LexLiteral{value: Char}

# Classify t for the interactive command lexer.
def classify_t(char: Char, hit: Bool) -> LexerChar:
  match hit:
    case True{}:
      LexEscapeT{}
    case False{}:
      LexLiteral{char}

# Classify n for the interactive command lexer.
def classify_n(+char: Char, hit: Bool) -> LexerChar:
  match hit:
    case True{}:
      LexEscapeN{}
    case False{}:
      classify_t(char, Char.is_eq(char, 't'))

# Classify backslash for the interactive command lexer.
def classify_backslash(+char: Char, hit: Bool) -> LexerChar:
  match hit:
    case True{}:
      LexBackslash{}
    case False{}:
      classify_n(char, Char.is_eq(char, 'n'))

# Classify quote for the interactive command lexer.
def classify_quote(+char: Char, hit: Bool) -> LexerChar:
  match hit:
    case True{}:
      LexQuote{}
    case False{}:
      classify_backslash(char, Char.is_eq(char, '\\'))

# Classify space for the interactive command lexer.
def classify_space(+char: Char, hit: Bool) -> LexerChar:
  match hit:
    case True{}:
      LexWhitespace{char}
    case False{}:
      classify_quote(char, Char.is_eq(char, '"'))

# Handle classify in the interactive command lexer.
def classify(+char: Char) -> LexerChar:
  classify_space(char, Char.is_space(char))

# Classify input for the interactive command lexer.
def classify_input(input: String) -> LexerChar:
  match input:
    case SNil{}:
      LexLiteral{' '}
    case SCon{head, _}:
      classify(head)

# Finish ish for the interactive command lexer.
def finish(tokens_rev: List<&2, String>) -> LexerResult:
  LexSuccess{List.reverse(&2, String, tokens_rev)}

# Handle scan in the interactive command lexer.
def scan(
  input: String,
  mode: LexerMode,
  current: LexerChar,
  token_rev: String,
  tokens_rev: List<&2, String>,
) -> LexerResult:
  match input:
    case SNil{}:
      match mode:
        case LexBetween{}:
          finish(tokens_rev)
        case LexBare{}:
          finish(Con{String.reverse(token_rev), tokens_rev})
        case LexQuoted{}:
          LexError{"unterminated quoted token"}
        case LexEscape{}:
          LexError{"unterminated escape sequence"}
    case SCon{_, +rest}:
      match mode:
        case LexBetween{}:
          match current:
            case LexWhitespace{_}:
              scan(rest, LexBetween{}, classify_input(rest), "", tokens_rev)
            case LexQuote{}:
              scan(rest, LexQuoted{}, classify_input(rest), "", tokens_rev)
            case LexBackslash{}:
              scan(rest, LexBare{}, classify_input(rest), SCon{'\\', SNil{}}, tokens_rev)
            case LexEscapeN{}:
              scan(rest, LexBare{}, classify_input(rest), SCon{'n', SNil{}}, tokens_rev)
            case LexEscapeT{}:
              scan(rest, LexBare{}, classify_input(rest), SCon{'t', SNil{}}, tokens_rev)
            case LexLiteral{char}:
              scan(rest, LexBare{}, classify_input(rest), SCon{char, SNil{}}, tokens_rev)
        case LexBare{}:
          match current:
            case LexWhitespace{_}:
              scan(rest, LexBetween{}, classify_input(rest), "", Con{String.reverse(token_rev), tokens_rev})
            case LexQuote{}:
              scan(rest, LexQuoted{}, classify_input(rest), token_rev, tokens_rev)
            case LexBackslash{}:
              scan(rest, LexBare{}, classify_input(rest), SCon{'\\', token_rev}, tokens_rev)
            case LexEscapeN{}:
              scan(rest, LexBare{}, classify_input(rest), SCon{'n', token_rev}, tokens_rev)
            case LexEscapeT{}:
              scan(rest, LexBare{}, classify_input(rest), SCon{'t', token_rev}, tokens_rev)
            case LexLiteral{char}:
              scan(rest, LexBare{}, classify_input(rest), SCon{char, token_rev}, tokens_rev)
        case LexQuoted{}:
          match current:
            case LexWhitespace{char}:
              scan(rest, LexQuoted{}, classify_input(rest), SCon{char, token_rev}, tokens_rev)
            case LexQuote{}:
              scan(rest, LexBare{}, classify_input(rest), token_rev, tokens_rev)
            case LexBackslash{}:
              scan(rest, LexEscape{}, classify_input(rest), token_rev, tokens_rev)
            case LexEscapeN{}:
              scan(rest, LexQuoted{}, classify_input(rest), SCon{'n', token_rev}, tokens_rev)
            case LexEscapeT{}:
              scan(rest, LexQuoted{}, classify_input(rest), SCon{'t', token_rev}, tokens_rev)
            case LexLiteral{char}:
              scan(rest, LexQuoted{}, classify_input(rest), SCon{char, token_rev}, tokens_rev)
        case LexEscape{}:
          match current:
            case LexWhitespace{_}:
              LexError{"invalid escape sequence"}
            case LexQuote{}:
              scan(rest, LexQuoted{}, classify_input(rest), SCon{'"', token_rev}, tokens_rev)
            case LexBackslash{}:
              scan(rest, LexQuoted{}, classify_input(rest), SCon{'\\', token_rev}, tokens_rev)
            case LexEscapeN{}:
              scan(rest, LexQuoted{}, classify_input(rest), SCon{'\n', token_rev}, tokens_rev)
            case LexEscapeT{}:
              scan(rest, LexQuoted{}, classify_input(rest), SCon{'\t', token_rev}, tokens_rev)
            case LexLiteral{_}:
              LexError{"invalid escape sequence"}

# Tokenize ize for the interactive command lexer.
def tokenize(+input: String) -> LexerResult:
  scan(input, LexBetween{}, classify_input(input), "", Nil{})
