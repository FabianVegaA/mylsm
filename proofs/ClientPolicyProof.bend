import Base
import ../laws/ClientPolicy.bend as Laws

def Laws.ready_mutation_is_dispatched_once():
  {==}

def Laws.dispatched_mutation_is_never_dispatched_again():
  {==}

def Laws.matching_owner_response_confirms_request():
  {==}

def Laws.old_owner_response_is_rejected():
  {==}

def Laws.lost_dispatched_mutation_is_commit_unknown():
  {==}

def Laws.lost_dispatched_read_is_retryable():
  {==}

def Laws.undispatched_request_can_be_retried():
  {==}

def Laws.completed_request_cannot_be_replayed():
  {==}

def Laws.any_lost_dispatched_mutation_is_commit_unknown(generation):
  match generation:
    case 0n: {==}
    case 1n+rest: {==}

def Laws.write_operation_tags_are_mutations():
  {==}

def Laws.non_mutation_operation_tags_stay_reads():
  {==}

def Laws.mismatched_response_correlation_is_protocol_failure():
  {==}

def Laws.stale_generation_precedes_response_correlation():
  {==}

def Laws.current_generation_and_correlation_confirm(generation):
  match generation:
    case 0n: {==}
    case 1n+rest: {==}
