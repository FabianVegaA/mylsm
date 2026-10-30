import Base

# Carries the state for UniqueInsertDecision.
type UniqueInsertDecision is Data:
  AlreadyListed{generations: List<&2, U32>}
  NewlyListed{generations: List<&2, U32>}

# Carries the state for UniqueCountState.
type UniqueCountState is Type:
  Scanning{remaining: List<&2, U32>, generations: List<&2, U32>, count: Nat}
  Inserting{remaining: List<&2, U32>, count: Nat,
    decision: UniqueInsertDecision}

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

def ids.copy.loop(
  remaining: List<&2, U32>,
  output: List<&2, U32>
) -> List<&2, U32>:
  match remaining:
    case Nil{}: output
    case Con{+id, tail}: ids.copy.loop(tail, Con{id, output})

def ids.copy(generations: List<&2, U32>) -> List<&2, U32>:
  ids.copy.loop(generations, Nil{})

def unique.insert.result(
  +generation: U32,
  generations: List<&2, U32>,
  already_listed: Bool
) -> UniqueInsertDecision:
  match already_listed:
    case True{}: AlreadyListed{generations}
    case False{}: NewlyListed{Con{generation, generations}}

def unique.insert(
  +generations: List<&2, U32>,
  +generation: U32
) -> UniqueInsertDecision:
  unique.insert.result(generation, generations,
    contains(generation, ids.copy(generations)))

def unique_generation_count.state.count(state: UniqueCountState) -> Nat:
  match state:
    case Scanning{_, _, count}: count
    case Inserting{_, count, _}: count

def unique_generation_count.loop(fuel: Nat, state: UniqueCountState) -> Nat:
  match fuel:
    case 0n: unique_generation_count.state.count(state)
    case 1n+rest:
      match state:
        case Scanning{remaining, generations, count}:
          match remaining:
            case Nil{}: count
            case Con{+generation, tail}:
              unique_generation_count.loop(rest,
                Inserting{tail, count,
                  unique.insert(generations, generation)})
        case Inserting{remaining, count, decision}:
          match decision:
            case AlreadyListed{generations}:
              unique_generation_count.loop(rest,
                Scanning{remaining, generations, count})
            case NewlyListed{generations}:
              unique_generation_count.loop(rest,
                Scanning{remaining, generations, Nat.add(count, 1n)})

# Handles unique generation count.
def unique_generation_count(+generations: List<&2, U32>) -> Nat:
  unique_generation_count.loop(
    Nat.add(Nat.mul(List.length(&2, U32, generations), 2n), 1n),
    Scanning{generations, Nil{}, 0n})

# Handles legacy file count.
def legacy_file_count(legacy: Bool) -> Nat:
  match legacy:
    case True{}: 1n
    case False{}: 0n

# Handles unique file count.
def unique_file_count(generations: List<&2, U32>, legacy: Bool) -> Nat:
  Nat.add(unique_generation_count(generations), legacy_file_count(legacy))
