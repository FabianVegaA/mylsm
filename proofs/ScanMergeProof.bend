import Base
import ../laws/ScanMerge.bend as Laws

def Laws.empty_sources_finish():
  {==}

def Laws.base_only_is_emitted():
  {==}

def Laws.base_only_ignores_delta_liveness(delta_live):
  match delta_live:
    case False{}: {==}
    case True{}: {==}

def Laws.no_heads_finish_independently_of_delta_liveness(delta_live):
  match delta_live:
    case False{}: {==}
    case True{}: {==}

def Laws.delta_only_value_is_emitted():
  {==}

def Laws.delta_only_tombstone_is_skipped():
  {==}

def Laws.lower_delta_precedes_base():
  {==}

def Laws.lower_delta_tombstone_does_not_hide_later_base():
  {==}

def Laws.lower_base_precedes_delta():
  {==}

def Laws.equal_delta_replaces_base():
  {==}

def Laws.equal_delta_tombstone_hides_base():
  {==}
