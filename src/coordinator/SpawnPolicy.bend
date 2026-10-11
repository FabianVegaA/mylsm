import Base

# Describes one executable and its ordered argument vector.
type Decision is Type:
  SpawnReady{argv: List<String>}
  SpawnInvalid{}

# Reaches the recursive validation only after the current character is admitted.
def string.valid.go(value: String, admitted: Bool) -> Bool:
  match value:
    case SNil{}:
      match admitted:
        case True{}: True{}
        case False{}: False{}
    case SCon{Chr{scalar}, rest}:
      match admitted:
        case True{}:
          string.valid.go(rest, Bool.not(U32.is_eq(scalar, 0)))
        case False{}: False{}

# Rejects NUL characters that cannot be represented in an operating-system argument.
def string.valid(value: String) -> Bool:
  string.valid.go(value, True{})

# Requires a nonempty executable and validates its first code point.
def program.valid(program: String) -> Bool:
  match program:
    case SNil{}: False{}
    case SCon{Chr{scalar}, rest}:
      Bool.and(Bool.not(U32.is_eq(scalar, 0)), string.valid(rest))

# Continues argument validation only after the current argument is admitted.
def arguments.valid.go(arguments: List<String>, admitted: Bool) -> Bool:
  match arguments:
    case Nil{}:
      match admitted:
        case True{}: True{}
        case False{}: False{}
    case Con{argument, rest}:
      match admitted:
        case True{}:
          arguments.valid.go(rest, string.valid(argument))
        case False{}: False{}

# Validates every argument without interpreting spaces or shell metacharacters.
def arguments.valid(arguments: List<String>) -> Bool:
  arguments.valid.go(arguments, True{})

# Preserves the exact executable and argument order in the spawn vector.
def prepare.result(program: String, arguments: List<String>, valid: Bool) -> Decision:
  match valid:
    case True{}: SpawnReady{Con{program, arguments}}
    case False{}: SpawnInvalid{}

# Accumulates two independent copies of every code point in the string.
def string.clone.pair.go(value: String, left: String, right: String) -> String & String:
  match value:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      string.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

# Duplicates one string for validation and output without sharing affine ownership.
def string.clone.pair(value: String) -> String & String:
  string.clone.pair.go(value, SNil{}, SNil{})

# Reassembles an argument and its recursively duplicated tail.
def arguments.clone.pair.step(
  argument_copies: String & String,
  tail_copies: List<String> & List<String>
) -> List<String> & List<String>:
  match argument_copies:
    case (left_argument, right_argument):
      match tail_copies:
        case (left_tail, right_tail):
          (Con{left_argument, left_tail}, Con{right_argument, right_tail})

# Duplicates an ordered argument vector for validation and output.
def arguments.clone.pair(arguments: List<String>) -> List<String> & List<String>:
  match arguments:
    case Nil{}: (Nil{}, Nil{})
    case Con{argument, rest}:
      arguments.clone.pair.step(string.clone.pair(argument),
        arguments.clone.pair(rest))

# Preserves executable and arguments while validating independent copies.
def prepare.copied(
  copies: (String & String) & (List<String> & List<String>)
) -> Decision:
  match copies:
    case ((program_check, program_output), (arguments_check, arguments_output)):
      prepare.result(program_output, arguments_output,
        Bool.and(program.valid(program_check), arguments.valid(arguments_check)))

# Rejects an empty executable and any argument containing NUL.
def prepare(program: String, arguments: List<String>) -> Decision:
  prepare.copied((string.clone.pair(program), arguments.clone.pair(arguments)))
