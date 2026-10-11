import Base
import ../src/scan/ScanMerge.bend as ScanMerge

# Two exhausted sources produce terminal completion.
law empty_sources_finish:
  {ScanMerge.choose(False{}, False{}, False{}, EQ{}) == ScanMerge.Finished{} : ScanMerge.Decision}

# An SST value remains visible without a delta mutation.
law base_only_is_emitted:
  {ScanMerge.choose(True{}, False{}, False{}, EQ{}) == ScanMerge.EmitBase{} : ScanMerge.Decision}

# A base result is independent of the delta liveness flag when no delta head exists.
law base_only_ignores_delta_liveness:
  for delta_live: Bool
  {ScanMerge.choose(True{}, False{}, delta_live, EQ{}) == ScanMerge.EmitBase{} : ScanMerge.Decision}

# Exhausted sources finish independently of unused delta metadata.
law no_heads_finish_independently_of_delta_liveness:
  for delta_live: Bool
  {ScanMerge.choose(False{}, False{}, delta_live, EQ{}) == ScanMerge.Finished{} : ScanMerge.Decision}

# A delta value is visible when the SST source has no head.
law delta_only_value_is_emitted:
  {ScanMerge.choose(False{}, True{}, True{}, EQ{}) == ScanMerge.EmitDelta{} : ScanMerge.Decision}

# A standalone tombstone advances without producing a result.
law delta_only_tombstone_is_skipped:
  {ScanMerge.choose(False{}, True{}, False{}, EQ{}) == ScanMerge.SkipDelta{} : ScanMerge.Decision}

# A lower delta key is emitted before the later SST key.
law lower_delta_precedes_base:
  {ScanMerge.choose(True{}, True{}, True{}, LT{}) == ScanMerge.EmitDelta{} : ScanMerge.Decision}

# A lower tombstone cannot suppress an unrelated later SST key.
law lower_delta_tombstone_does_not_hide_later_base:
  {ScanMerge.choose(True{}, True{}, False{}, LT{}) == ScanMerge.SkipDelta{} : ScanMerge.Decision}

# A lower SST key is emitted before a later delta key.
law lower_base_precedes_delta:
  {ScanMerge.choose(True{}, True{}, True{}, GT{}) == ScanMerge.EmitBase{} : ScanMerge.Decision}

# Equal keys emit the newer delta value and advance both sources.
law equal_delta_replaces_base:
  {ScanMerge.choose(True{}, True{}, True{}, EQ{}) == ScanMerge.EmitBoth{} : ScanMerge.Decision}

# An equal delta tombstone suppresses the SST key entirely.
law equal_delta_tombstone_hides_base:
  {ScanMerge.choose(True{}, True{}, False{}, EQ{}) == ScanMerge.SkipBoth{} : ScanMerge.Decision}
