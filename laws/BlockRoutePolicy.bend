import Base
import ../src/scan/BlockRoutePolicy.bend as Policy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Unwraps the finite byte keys used by separator-routing witnesses.
def bytes.fixture(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Routes a lower bound before a separator into its left search interval.
law target_before_separator_searches_lower:
  {Policy.move(bytes.fixture(Bytes.from_hex("61")),
    bytes.fixture(Bytes.from_hex("62"))) == Policy.SearchLower{} : Policy.Move}

# Routes equality into the interval that can improve the selected block.
law target_equal_to_separator_searches_upper:
  {Policy.move(bytes.fixture(Bytes.from_hex("62")),
    bytes.fixture(Bytes.from_hex("62"))) == Policy.SearchUpper{} : Policy.Move}

# Routes a target after a separator into its upper search interval.
law target_after_separator_searches_upper:
  {Policy.move(bytes.fixture(Bytes.from_hex("63")),
    bytes.fixture(Bytes.from_hex("62"))) == Policy.SearchUpper{} : Policy.Move}

# A lower decision strictly discards the midpoint and upper half.
law lower_move_shrinks_search_interval:
  {Policy.advance(Policy.Search{0n, 8n, 0n}, Policy.SearchLower{}, 4n) ==
    Policy.Search{0n, 4n, 0n} : Policy.Search}

# An upper decision records its midpoint as the latest eligible separator.
law upper_move_advances_candidate:
  {Policy.advance(Policy.Search{0n, 8n, 0n}, Policy.SearchUpper{}, 4n) ==
    Policy.Search{5n, 8n, 4n} : Policy.Search}

# The midpoint stays in the half-open interval for representative odd widths.
law midpoint_is_inside_odd_interval:
  {Policy.midpoint(3n, 10n) == 6n : Nat}

# A completed search chooses the most recent eligible separator.
law completed_search_selects_latest_candidate:
  {Policy.selected_block(Policy.Search{7n, 7n, 6n}) == 6n : Nat}

# The initial candidate routes keys before the first separator to block zero.
law initial_candidate_is_first_block:
  {Policy.selected_block(Policy.Search{0n, 0n, 0n}) == 0n : Nat}
