import Base

# Carries the token being read and the finished tokens in reverse order.
type TokenState is Type:
  TokenState{current: String, done: List<&2, String>}

# Reports whether a character belongs to an identifier token.
def token.char(+character: Char) -> Bool:
  Char.is_alpha(character) || Char.is_digit(character) || Char.is_eq(character, '_') ||
    Char.is_eq(character, '.')

def tokens.flush(current: String, done: List<&2, String>) -> List<&2, String>:
  match current:
    case SNil{}: done
    case SCon{character, rest}: Con{String.reverse(SCon{character, rest}), done}

def tokens.advance.decided(
  is_token: Bool,
  state: TokenState,
  character: Char
) -> TokenState:
  match is_token:
    case True{}:
      match state:
        case TokenState{current, done}: TokenState{SCon{character, current}, done}
    case False{}:
      match state:
        case TokenState{current, done}:
          TokenState{SNil{}, tokens.flush(current, done)}

def tokens.advance(+character: Char, state: TokenState) -> TokenState:
  tokens.advance.decided(token.char(character), state, character)

def tokens.go(text: String, state: TokenState) -> List<&2, String>:
  match text:
    case SNil{}:
      match state:
        case TokenState{current, done}:
          List.reverse(&2, String, tokens.flush(current, done))
    case SCon{character, rest}: tokens.go(rest, tokens.advance(character, state))

# Splits text into maximal runs of identifier characters and dots.
def tokens(text: String) -> List<&2, String>:
  tokens.go(text, TokenState{SNil{}, Nil{}})

def suffixes.after.decided(
  is_dot: Bool,
  rest: String,
  tail: List<&2, String>
) -> List<&2, String>:
  match is_dot:
    case True{}: Con{rest, tail}
    case False{}: tail

def suffixes.after(text: String) -> List<&2, String>:
  match text:
    case SNil{}: Nil{}
    case SCon{+character, +rest}:
      suffixes.after.decided(Char.is_eq(character, '.'), rest, suffixes.after(rest))

# Lists a token and every part of it that follows a dot.
def suffixes(+token: String) -> List<&2, String>:
  Con{token, suffixes.after(token)}

def definition.first(found: List<&2, String>) -> Maybe<&2, String>:
  match found:
    case Nil{}: None{}
    case Con{name, _}: Some{name}

def definition.head.decided(is_token: Bool, rest: String) -> Maybe<&2, String>:
  match is_token:
    case True{}: definition.first(tokens(rest))
    case False{}: None{}

def definition.head(rest: String) -> Maybe<&2, String>:
  match rest:
    case SNil{}: None{}
    case SCon{+character, tail}: definition.head.decided(token.char(character), SCon{character, tail})

def definition.prefixed(starts: Bool, line: String) -> Maybe<&2, String>:
  match starts:
    case True{}: definition.head(String.drop(line, 4n))
    case False{}: None{}

# Reads the defined name from a line that starts with def.
def definition(+line: String) -> Maybe<&2, String>:
  definition.prefixed(String.starts_with(line, "def "), line)

def definitions.push(
  found: Maybe<&2, String>,
  rest: List<&2, String>
) -> List<&2, String>:
  match found:
    case None{}: rest
    case Some{name}: Con{name, rest}

def definitions.go(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, rest}:
      definitions.push(definition(line), definitions.go(rest))

# Lists the names defined in a text, in order.
def definitions(text: String) -> List<&2, String>:
  definitions.go(String.lines(text))

def count.add.got(pair: Map<&2, Nat> & Nat, key: String) -> Map<&2, Nat>:
  match pair:
    case (counts, seen): Map.set(&2, Nat, counts, key, Nat.add(seen, 1n))

def count.add(counts: Map<&2, Nat>, +key: String) -> Map<&2, Nat>:
  count.add.got(Map.get(Nat, 0n, counts, key), key)

def count.keys(keys: List<&2, String>, counts: Map<&2, Nat>) -> Map<&2, Nat>:
  match keys:
    case Nil{}: counts
    case Con{key, rest}: count.keys(rest, count.add(counts, key))

def count.tokens(found: List<&2, String>, counts: Map<&2, Nat>) -> Map<&2, Nat>:
  match found:
    case Nil{}: counts
    case Con{token, rest}: count.tokens(rest, count.keys(suffixes(token), counts))

# Adds every token suffix of a text to the reference counts.
def count(counts: Map<&2, Nat>, text: String) -> Map<&2, Nat>:
  count.tokens(tokens(text), counts)

def unused.counted(pair: Map<&2, Nat> & Nat) -> Map<&2, Nat> & Bool:
  match pair:
    case (counts, seen): (counts, Nat.is_le(seen, 1n))

def unused.named(
  is_main: Bool,
  counts: Map<&2, Nat>,
  name: String
) -> Map<&2, Nat> & Bool:
  match is_main:
    case True{}: (counts, False{})
    case False{}: unused.counted(Map.get(Nat, 0n, counts, name))

# Reports whether a name appears only in its own definition, keeping the counts.
def unused.kept(counts: Map<&2, Nat>, +name: String) -> Map<&2, Nat> & Bool:
  unused.named(String.eq(name, "main"), counts, name)

def unused.result(pair: Map<&2, Nat> & Bool) -> Bool:
  match pair:
    case (_, result): result

# Reports whether a name appears only in its own definition.
def unused(counts: Map<&2, Nat>, +name: String) -> Bool:
  unused.result(unused.kept(counts, name))

def allowed.entry(+entry: String, +path: String, +name: String) -> Bool:
  (String.ends_with(entry, "/") && String.starts_with(path, entry)) ||
    String.eq(entry, path) || String.eq(entry, path ++ " " ++ name)

def allowed.go(
  allow: List<&2, String>,
  +path: String,
  +name: String,
  found: Bool
) -> Bool:
  match allow:
    case Nil{}: found
    case Con{entry, rest}:
      match found:
        case True{}: True{}
        case False{}: allowed.go(rest, path, name, allowed.entry(entry, path, name))

# Reports whether an allowlist entry covers a path or one of its names.
def allowed(allow: List<&2, String>, +path: String, +name: String) -> Bool:
  allowed.go(allow, path, name, False{})

def targeted.entry(+target: String, +path: String) -> Bool:
  String.eq(target, path) || String.starts_with(path, target ++ "/")

def targeted.go(targets: List<&2, String>, +path: String, found: Bool) -> Bool:
  match targets:
    case Nil{}: found
    case Con{target, rest}:
      match found:
        case True{}: True{}
        case False{}: targeted.go(rest, path, targeted.entry(target, path))

# Reports whether a path is one of the targets or lies below one.
def targeted(targets: List<&2, String>, +path: String) -> Bool:
  targeted.go(targets, path, False{})

# Holds a defined name and how often it appears inside its own block.
type Definition is Type:
  Definition{name: String, own: Nat}

# Tracks whether the scan is inside a definition block.
type BlockState is Type:
  Outside{}
  Inside{name: String, own: Nat}

# Carries the open block and the definitions already closed.
type BlockStep is Type:
  BlockStep{state: BlockState, done: List<&1, Definition>}

def matches.add(hit: Bool, total: Nat) -> Nat:
  match hit:
    case True{}: Nat.add(total, 1n)
    case False{}: total

def matches.keys(keys: List<&2, String>, +name: String, total: Nat) -> Nat:
  match keys:
    case Nil{}: total
    case Con{key, rest}: matches.keys(rest, name, matches.add(String.eq(key, name), total))

def matches.tokens(found: List<&2, String>, +name: String, total: Nat) -> Nat:
  match found:
    case Nil{}: total
    case Con{token, rest}:
      matches.tokens(rest, name, matches.keys(suffixes(token), name, total))

# Counts how often a line mentions a name.
def matches(+name: String, line: String) -> Nat:
  matches.tokens(tokens(line), name, 0n)

def block.close(state: BlockState, done: List<&1, Definition>) -> List<&1, Definition>:
  match state:
    case Outside{}: done
    case Inside{name, own}: Con{Definition{name, own}, done}

def block.continues(line: String) -> Bool:
  match line:
    case SNil{}: True{}
    case SCon{+character, _}: Char.is_space(character) || Char.is_eq(character, ')')

def block.opened(found: Maybe<&2, String>, line: String) -> BlockState:
  match found:
    case None{}: Outside{}
    case Some{+name}: Inside{name, matches(name, line)}

def block.extend(state: BlockState, line: String) -> BlockState:
  match state:
    case Outside{}: Outside{}
    case Inside{+name, own}: Inside{name, Nat.add(own, matches(name, line))}

def block.other(continues: Bool, line: String, step: BlockStep) -> BlockStep:
  match continues:
    case True{}:
      match step:
        case BlockStep{state, done}: BlockStep{block.extend(state, line), done}
    case False{}:
      match step:
        case BlockStep{state, done}: BlockStep{Outside{}, block.close(state, done)}

def block.line.decided(starts: Bool, +line: String, step: BlockStep) -> BlockStep:
  match starts:
    case True{}:
      match step:
        case BlockStep{state, done}:
          BlockStep{block.opened(definition(line), line), block.close(state, done)}
    case False{}: block.other(block.continues(line), line, step)

def block.line(+line: String, step: BlockStep) -> BlockStep:
  block.line.decided(String.starts_with(line, "def "), line, step)

def defined.go(lines: List<&2, String>, step: BlockStep) -> List<&1, Definition>:
  match lines:
    case Nil{}:
      match step:
        case BlockStep{state, done}: List.reverse(&1, Definition, block.close(state, done))
    case Con{line, rest}: defined.go(rest, block.line(line, step))

# Lists each definition with the number of mentions inside its own block.
def defined(text: String) -> List<&1, Definition>:
  defined.go(String.lines(text), BlockStep{Outside{}, Nil{}})

def unused.own.counted(pair: Map<&2, Nat> & Nat, own: Nat) -> Map<&2, Nat> & Bool:
  match pair:
    case (counts, seen): (counts, Nat.is_le(seen, own))

def unused.own.named(
  is_main: Bool,
  counts: Map<&2, Nat>,
  name: String,
  own: Nat
) -> Map<&2, Nat> & Bool:
  match is_main:
    case True{}: (counts, False{})
    case False{}: unused.own.counted(Map.get(Nat, 0n, counts, name), own)

# Reports whether a name appears only inside its own block, keeping the counts.
def unused.own(counts: Map<&2, Nat>, +name: String, own: Nat) -> Map<&2, Nat> & Bool:
  unused.own.named(String.eq(name, "main"), counts, name, own)

def report.step(
  checked: Map<&2, Nat> & Bool,
  name: String,
  found: List<&2, String>
) -> Map<&2, Nat> & List<&2, String>:
  match checked:
    case (counts, True{}): (counts, Con{name, found})
    case (counts, False{}): (counts, found)

def report.go(
  found: List<&1, Definition>,
  state: Map<&2, Nat> & List<&2, String>
) -> List<&2, String>:
  match found:
    case Nil{}:
      match state:
        case (_, names): List.reverse(&2, String, names)
    case Con{Definition{+name, own}, rest}:
      match state:
        case (counts, names):
          report.go(rest, report.step(unused.own(counts, name, own), name, names))

# Lists the definitions in one text that nothing else in it references.
def report(+text: String) -> List<&2, String>:
  report.go(defined(text), (count(Map.new(&2, Nat), text), Nil{}))
