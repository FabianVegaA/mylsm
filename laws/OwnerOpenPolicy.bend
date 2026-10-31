import Base
import ../src/coordinator/OwnerOpenPolicy.bend as Policy

# Verifies a local open with the supported options keeps the local handle.
law local_default_options_use_local:
  {Policy.choose(True{}, True{}) == Policy.UseLocal{} : Policy.Decision}

# Verifies a local open with unsupported options is rejected.
law local_unsupported_options_are_rejected:
  {Policy.choose(True{}, False{}) == Policy.RejectOptions{} : Policy.Decision}

# Verifies remote mismatch is rejected.
law remote_mismatch_is_rejected:
  {Policy.choose(False{}, False{}) == Policy.RejectOptions{} : Policy.Decision}

# Verifies remote match uses existing owner.
law remote_match_uses_existing_owner:
  {Policy.choose(False{}, True{}) == Policy.UseRemote{} : Policy.Decision}

# Verifies every mismatch is rejected, local or remote.
law mismatch_is_always_rejected:
  for local: Bool
  {Policy.choose(local, False{}) == Policy.RejectOptions{} : Policy.Decision}
