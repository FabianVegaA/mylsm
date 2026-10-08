import Base

# Treats only a missing-path errno as absence.
def missing_path_result(missing: Bool, +code: U32, message: String) -> Result<&1, &1, U32 & String, Bool>:
  match missing:
    case True{}:
      Done{False{}}
    case False{}:
      Fail{(code, message)}

# Ignores absent optional levels and preserves other errors.
def optional_directory_result(
  optional: Bool,
  unavailable: Bool,
  +code: U32,
  message: String
) -> Result<&1, &1, U32 & String, Unit>:
  match optional:
    case False{}:
      Fail{(code, message)}
    case True{}:
      match unavailable:
        case True{}:
          Done{Unit{}}
        case False{}:
          Fail{(code, message)}
