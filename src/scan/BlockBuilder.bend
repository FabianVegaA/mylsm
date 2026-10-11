import Base

# Reports whether a measured record appends, rolls over, or exceeds a block.
type Decision is Data:
  Append{used_bytes: Nat}
  RecordTooLarge{}
  StartNextBlock{}

# Selects a block action from an explicit fit and empty-block decision.
def decide.fits(
  required_bytes: Nat,
  current_empty: Bool,
  fits: Bool
) -> Decision:
  Bool.pick(Decision, fits,
    Append{required_bytes},
    Bool.pick(Decision, current_empty, RecordTooLarge{}, StartNextBlock{}))

# Chooses append, block rollover, or rejection for one measured record.
def decide(
  required_bytes: Nat,
  current_empty: Bool,
  fits: Bool
) -> Decision:
  decide.fits(required_bytes, current_empty, fits)
