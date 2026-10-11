import Base

# Continues the root search only when the current generation differs.
def contains.result(
  +generation: U32,
  roots: List<&2, U32>,
  equal: Bool
) -> Bool:
  match roots:
    case Nil{}:
      match equal:
        case True{}: True{}
        case False{}: False{}
    case Con{root, tail}:
      match equal:
        case True{}: True{}
        case False{}:
          contains.result(generation, tail, U32.is_eq(root, generation))

# Searches retained snapshot roots for one SST generation.
def contains(+generation: U32, roots: List<&2, U32>) -> Bool:
  match roots:
    case Nil{}: False{}
    case Con{root, tail}:
      contains.result(generation, tail, U32.is_eq(root, generation))

# Checks whether a generation is the one currently published by the manifest.
def current(generation: U32, published: Maybe<&1, U32>) -> Bool:
  match published:
    case None{}: False{}
    case Some{value}: U32.is_eq(value, generation)

def can_reclaim.ids(
  +generation: U32,
  published: Maybe<&1, U32>,
  roots: List<&2, U32>
) -> Bool:
  Bool.pick(Bool, current(generation, published), False{},
    Bool.pick(Bool, contains(generation, roots), False{}, True{}))

# Allows deletion only when a generation is neither published nor retained.
def can_reclaim(
  generation: U32,
  published: Maybe<&1, U32>,
  roots: List<&2, U32>
) -> Bool:
  can_reclaim.ids(generation, published, roots)
