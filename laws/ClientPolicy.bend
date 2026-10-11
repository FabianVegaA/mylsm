# A mutation can enter the dispatched state exactly once.
import Base
import ../src/coordinator/ClientPolicy.bend as ClientPolicy
import ../src/coordinator/SessionPolicy.bend as SessionPolicy
import ../src/coordinator/Protocol.bend as Protocol

# Accepts one first dispatch.
law ready_mutation_is_dispatched_once:
  {ClientPolicy.dispatch(ClientPolicy.ClientReady{7n}, True{}) ==
    ClientPolicy.ClientDispatch{ClientPolicy.RequestDispatched{7n, True{}}} : ClientPolicy.Decision}

# Rejects a second dispatch attempt for the same request.
law dispatched_mutation_is_never_dispatched_again:
  {ClientPolicy.dispatch(ClientPolicy.RequestDispatched{7n, True{}}, True{}) ==
    ClientPolicy.ClientReject{} : ClientPolicy.Decision}

# Confirms a response from the same owner generation.
law matching_owner_response_confirms_request:
  {ClientPolicy.response(ClientPolicy.RequestDispatched{7n, True{}}, 7n) ==
    ClientPolicy.ClientConfirmed{ClientPolicy.RequestCompleted{7n}} : ClientPolicy.Decision}

# Identifies a response from an earlier owner generation as stale.
law old_owner_response_is_rejected:
  {ClientPolicy.response(ClientPolicy.RequestDispatched{7n, False{}}, 8n) ==
    ClientPolicy.ClientStaleOwner{} : ClientPolicy.Decision}

# Classifies response loss after mutation dispatch as uncertain.
law lost_dispatched_mutation_is_commit_unknown:
  {ClientPolicy.disconnect(ClientPolicy.RequestDispatched{7n, True{}}) ==
    ClientPolicy.ClientCommitUnknown{} : ClientPolicy.Decision}

# Allows a read to retry after its connection is lost.
law lost_dispatched_read_is_retryable:
  {ClientPolicy.disconnect(ClientPolicy.RequestDispatched{7n, False{}}) ==
    ClientPolicy.ClientRetryRead{} : ClientPolicy.Decision}

# Allows retry when a request was never sent to the owner.
law undispatched_request_can_be_retried:
  {ClientPolicy.disconnect(ClientPolicy.ClientReady{7n}) ==
    ClientPolicy.ClientRetryBeforeDispatch{} : ClientPolicy.Decision}

# Rejects replay after the request already completed.
law completed_request_cannot_be_replayed:
  {ClientPolicy.disconnect(ClientPolicy.RequestCompleted{7n}) ==
    ClientPolicy.ClientReject{} : ClientPolicy.Decision}

# Every dispatched mutation becomes uncertain after response loss.
law any_lost_dispatched_mutation_is_commit_unknown:
  for generation: Nat
  {ClientPolicy.disconnect(ClientPolicy.RequestDispatched{generation, True{}}) ==
    ClientPolicy.ClientCommitUnknown{} : ClientPolicy.Decision}

# Classifies byte writes, deletes, flushes, and compactions as mutations.
law write_operation_tags_are_mutations:
  {(ClientPolicy.operation.is_mutation(2) &&
    ClientPolicy.operation.is_mutation(3) &&
    ClientPolicy.operation.is_mutation(4) &&
    ClientPolicy.operation.is_mutation(5) &&
    ClientPolicy.operation.is_mutation(8)) == True{} : Bool}

# Classifies reads, stats, and unknown tags as non-mutations.
law non_mutation_operation_tags_stay_reads:
  {(Bool.not(ClientPolicy.operation.is_mutation(1)) &&
    Bool.not(ClientPolicy.operation.is_mutation(6)) &&
    Bool.not(ClientPolicy.operation.is_mutation(7)) &&
    Bool.not(ClientPolicy.operation.is_mutation(4294967295))) == True{} : Bool}

# Rejects replies whose request identifier or protocol version does not match.
law mismatched_response_correlation_is_protocol_failure:
  {ClientPolicy.response.validate(7n, True{}, False{}) ==
    ClientPolicy.ClientProtocolFailure{} : ClientPolicy.Decision}

# Rejects replies from a previous owner even when request correlation matches.
law stale_generation_precedes_response_correlation:
  {ClientPolicy.response.validate(7n, False{}, True{}) ==
    ClientPolicy.ClientStaleOwner{} : ClientPolicy.Decision}

# Confirms a correlated response from the current owner generation.
law current_generation_and_correlation_confirm:
  for generation: Nat
  {ClientPolicy.response.validate(generation, True{}, True{}) ==
    ClientPolicy.ClientConfirmed{ClientPolicy.RequestCompleted{generation}} : ClientPolicy.Decision}

# Admits a payload exactly at the encoded frame limit.
law request_payload_at_limit_is_admitted:
  {ClientPolicy.request.within_payload_limit(1073741824) == True{} : Bool}

# Rejects a payload one byte beyond the encoded frame limit.
law request_payload_over_limit_is_rejected:
  {ClientPolicy.request.within_payload_limit(1073741825) == False{} : Bool}

# Assigns the current request identifier and advances the sequence.
law request_id_sequence_advances_without_reuse:
  {ClientPolicy.request_id.take(ClientPolicy.RequestAvailable{41}) ==
    ClientPolicy.RequestAssigned{41, ClientPolicy.RequestAvailable{42}} : ClientPolicy.RequestDecision}

# Uses the final representable ID once and then becomes exhausted.
law final_request_id_is_not_reused_after_wraparound:
  {ClientPolicy.request_id.take.available((41, 42), True{}) ==
    ClientPolicy.RequestAssigned{41, ClientPolicy.RequestExhausted{}} : ClientPolicy.RequestDecision}

# Keeps request ID exhaustion terminal.
law exhausted_request_sequence_rejects_every_call:
  {ClientPolicy.request_id.take(ClientPolicy.RequestExhausted{}) ==
    ClientPolicy.RequestIdsExhausted{} : ClientPolicy.RequestDecision}

# Confirms only responses whose operation completed successfully.
law successful_owner_status_is_accepted:
  {ClientPolicy.response.accepted(Protocol.Success{}) == True{} : Bool}

# Preserves every owner failure status as a rejected operation result.
law owner_failure_statuses_are_rejected:
  {(Bool.not(ClientPolicy.response.accepted(Protocol.InvalidArgument{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.NotFound{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.Busy{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.Timeout{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.ResponseResourceLimit{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.Corruption{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.IoFailure{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.CommitUnknown{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.AlreadyExists{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.UnsupportedPlatform{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.InvalidUtf8{})) &&
    Bool.not(ClientPolicy.response.accepted(Protocol.UnsupportedFormat{}))) ==
    True{} : Bool}

# Preserves an owner value response as a present read result.
law get_success_status_has_value:
  {ClientPolicy.response.get.status(Protocol.Success{}) ==
    ClientPolicy.GetValueStatus{} : ClientPolicy.GetStatus}

# Translates the owner not-found status into an absent read result.
law get_not_found_status_is_missing:
  {ClientPolicy.response.get.status(Protocol.NotFound{}) ==
    ClientPolicy.GetMissingStatus{} : ClientPolicy.GetStatus}

# Keeps uncertain commits and other failures out of the read-value path.
law get_commit_unknown_status_is_failure:
  {ClientPolicy.response.get.status(Protocol.CommitUnknown{}) ==
    ClientPolicy.GetFailureStatus{Protocol.CommitUnknown{}} : ClientPolicy.GetStatus}

# Preserves an available request number in both copied session states.
law session_request_clone_preserves_available_number:
  {SessionPolicy.requests.clone(ClientPolicy.RequestAvailable{19}) ==
    (ClientPolicy.RequestAvailable{19}, ClientPolicy.RequestAvailable{19}) :
      ClientPolicy.RequestSequence & ClientPolicy.RequestSequence}

# Keeps exhaustion terminal in both copied session states.
law session_request_clone_preserves_exhaustion:
  {SessionPolicy.requests.clone(ClientPolicy.RequestExhausted{}) ==
    (ClientPolicy.RequestExhausted{}, ClientPolicy.RequestExhausted{}) :
      ClientPolicy.RequestSequence & ClientPolicy.RequestSequence}
