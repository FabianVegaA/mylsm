import Base
import ../src/coordinator/ResponseBoundPolicy.bend as Policy
import ../src/coordinator/Protocol.bend as Protocol
import ../src/ResourceOptions.bend as Options

# Verifies a fitting response keeps its status and payload.
law fitting_response_keeps_status_and_payload:
  for mutation: Bool
  for status: Protocol.ResponseStatus
  {Policy.bound(mutation, status, Policy.Fits{}) ==
    Policy.Bounded{status, True{}} : Policy.Bounded}

# Verifies an overflowing read reports a resource limit without payload.
law overflowing_read_is_resource_limit:
  for status: Protocol.ResponseStatus
  {Policy.bound(False{}, status, Policy.Overflows{}) ==
    Policy.Bounded{Protocol.ResponseResourceLimit{}, False{}} : Policy.Bounded}

# Verifies an overflowing mutation reports an uncertain commit without payload.
law overflowing_mutation_is_commit_unknown:
  for status: Protocol.ResponseStatus
  {Policy.bound(True{}, status, Policy.Overflows{}) ==
    Policy.Bounded{Protocol.CommitUnknown{}, False{}} : Policy.Bounded}

# Verifies an admitted length fits.
law admitted_length_fits:
  {Policy.outcome(True{}) == Policy.Fits{} : Policy.Outcome}

# Verifies a rejected length overflows.
law rejected_length_overflows:
  {Policy.outcome(False{}) == Policy.Overflows{} : Policy.Outcome}

# Verifies an empty payload fits a zero response budget.
law empty_payload_fits_zero_budget:
  {Options.response.admitted(0, 0) == True{} : Bool}
