import Base

# Describes which source heads advance and whether a visible record is emitted.
type Decision is Data:
  Finished{}
  EmitBase{}
  EmitDelta{}
  EmitBoth{}
  SkipDelta{}
  SkipBoth{}

# Emits a delta value or advances past a delta tombstone without a base head.
def delta.without.base(live: Bool) -> Decision:
  match live:
    case True{}: EmitDelta{}
    case False{}: SkipDelta{}

# Emits an SST head when no newer delta head is available.
def base.without.delta() -> Decision:
  EmitBase{}

# Applies ordering and tombstone precedence when both sources have a head.
def both.live(live: Bool, order: Cmp) -> Decision:
  match live:
    case True{}:
      match order:
        case LT{}: EmitDelta{}
        case EQ{}: EmitBoth{}
        case GT{}: EmitBase{}
    case False{}:
      match order:
        case LT{}: SkipDelta{}
        case EQ{}: SkipBoth{}
        case GT{}: EmitBase{}

# Exposes the two-head comparison transition for the top-level selector.
def both(live: Bool, order: Cmp) -> Decision:
  both.live(live, order)

# Selects the next merge transition for sorted SST and delta heads.
def choose(
  base_exists: Bool,
  delta_exists: Bool,
  delta_live: Bool,
  order: Cmp
) -> Decision:
  match base_exists:
    case True{}:
      match delta_exists:
        case True{}: both(delta_live, order)
        case False{}: base.without.delta()
    case False{}:
      match delta_exists:
        case True{}: delta.without.base(delta_live)
        case False{}: Finished{}
