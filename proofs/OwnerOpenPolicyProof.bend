import Base
import ../laws/OwnerOpenPolicy.bend as Laws

def Laws.local_default_options_use_local():
  {==}

def Laws.local_unsupported_options_are_rejected():
  {==}

def Laws.remote_mismatch_is_rejected():
  {==}

def Laws.remote_match_uses_existing_owner():
  {==}

def Laws.mismatch_is_always_rejected(local):
  match local:
    case True{}: {==}
    case False{}: {==}
