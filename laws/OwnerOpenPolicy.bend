import Base
import ../src/coordinator/OwnerOpenPolicy.bend as Policy

# Verifies local open preserves local mode.
law local_open_preserves_local_mode:
  for matches: Bool
  {Policy.choose(True{}, matches) == Policy.UseLocal{} : Policy.Decision}

# Verifies remote mismatch is rejected.
law remote_mismatch_is_rejected:
  {Policy.choose(False{}, False{}) == Policy.RejectOptions{} : Policy.Decision}

# Verifies remote match uses existing owner.
law remote_match_uses_existing_owner:
  {Policy.choose(False{}, True{}) == Policy.UseRemote{} : Policy.Decision}
