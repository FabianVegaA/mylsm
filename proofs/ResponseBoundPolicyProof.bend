import Base
import ../src/coordinator/Protocol.bend as Protocol
import ../laws/ResponseBoundPolicy.bend as Laws

def Laws.fitting_response_keeps_status_and_payload(mutation, status):
  match mutation:
    case True{}:
      match status:
        case Protocol.Success{}: {==}
        case Protocol.InvalidArgument{}: {==}
        case Protocol.NotFound{}: {==}
        case Protocol.Busy{}: {==}
        case Protocol.Timeout{}: {==}
        case Protocol.ResponseResourceLimit{}: {==}
        case Protocol.Corruption{}: {==}
        case Protocol.IoFailure{}: {==}
        case Protocol.CommitUnknown{}: {==}
        case Protocol.AlreadyExists{}: {==}
        case Protocol.UnsupportedPlatform{}: {==}
        case Protocol.InvalidUtf8{}: {==}
        case Protocol.UnsupportedFormat{}: {==}
    case False{}:
      match status:
        case Protocol.Success{}: {==}
        case Protocol.InvalidArgument{}: {==}
        case Protocol.NotFound{}: {==}
        case Protocol.Busy{}: {==}
        case Protocol.Timeout{}: {==}
        case Protocol.ResponseResourceLimit{}: {==}
        case Protocol.Corruption{}: {==}
        case Protocol.IoFailure{}: {==}
        case Protocol.CommitUnknown{}: {==}
        case Protocol.AlreadyExists{}: {==}
        case Protocol.UnsupportedPlatform{}: {==}
        case Protocol.InvalidUtf8{}: {==}
        case Protocol.UnsupportedFormat{}: {==}

def Laws.overflowing_read_is_resource_limit(status):
  match status:
    case Protocol.Success{}: {==}
    case Protocol.InvalidArgument{}: {==}
    case Protocol.NotFound{}: {==}
    case Protocol.Busy{}: {==}
    case Protocol.Timeout{}: {==}
    case Protocol.ResponseResourceLimit{}: {==}
    case Protocol.Corruption{}: {==}
    case Protocol.IoFailure{}: {==}
    case Protocol.CommitUnknown{}: {==}
    case Protocol.AlreadyExists{}: {==}
    case Protocol.UnsupportedPlatform{}: {==}
    case Protocol.InvalidUtf8{}: {==}
    case Protocol.UnsupportedFormat{}: {==}

def Laws.overflowing_mutation_is_commit_unknown(status):
  match status:
    case Protocol.Success{}: {==}
    case Protocol.InvalidArgument{}: {==}
    case Protocol.NotFound{}: {==}
    case Protocol.Busy{}: {==}
    case Protocol.Timeout{}: {==}
    case Protocol.ResponseResourceLimit{}: {==}
    case Protocol.Corruption{}: {==}
    case Protocol.IoFailure{}: {==}
    case Protocol.CommitUnknown{}: {==}
    case Protocol.AlreadyExists{}: {==}
    case Protocol.UnsupportedPlatform{}: {==}
    case Protocol.InvalidUtf8{}: {==}
    case Protocol.UnsupportedFormat{}: {==}

def Laws.admitted_length_fits():
  {==}

def Laws.rejected_length_overflows():
  {==}

def Laws.empty_payload_fits_zero_budget():
  {==}
