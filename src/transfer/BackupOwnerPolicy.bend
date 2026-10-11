import Base
import ./Backup.bend as Backup

# Identifies a remote owner failure without importing socket effects.
type OwnerError is Data:
  ConnectHost{code: U32, message: String}
  ConnectUnsupported{}
  ReadHost{code: U32, message: String}
  ReadUnsupported{}
  ReadFailure{}
  CommitHost{code: U32, message: String}
  CommitFailure{}
  FrameTooLarge{}
  StaleOwner{}
  CorrelationMismatch{}
  MalformedResponse{}
  RequestIdsExhausted{}
  OwnerRejected{}
  UnsupportedPlatform{}

# Maps every remote cursor failure into the backup source error domain.
def source.error(error: OwnerError) -> Backup.Error:
  match error:
    case ConnectHost{code, message}:
      Backup.SourceFailure{code, message}
    case ConnectUnsupported{}:
      Backup.UnsupportedPlatform{}
    case ReadHost{code, message}:
      Backup.SourceFailure{code, message}
    case ReadUnsupported{}:
      Backup.UnsupportedPlatform{}
    case ReadFailure{}:
      Backup.SourceFailure{5, "owner snapshot cursor read failed"}
    case CommitHost{code, message}:
      Backup.SourceFailure{code, message}
    case CommitFailure{}:
      Backup.SourceFailure{5, "owner snapshot cursor state is uncertain"}
    case FrameTooLarge{}:
      Backup.SourceFailure{75, "owner cursor frame exceeded limit"}
    case StaleOwner{}:
      Backup.SourceFailure{116, "owner cursor generation is stale"}
    case CorrelationMismatch{}:
      Backup.SourceFailure{71, "owner cursor correlation mismatch"}
    case MalformedResponse{}:
      Backup.SourceFailure{71, "owner cursor response is malformed"}
    case RequestIdsExhausted{}:
      Backup.SourceFailure{75, "owner cursor request ids exhausted"}
    case OwnerRejected{}:
      Backup.SourceFailure{5, "owner rejected snapshot cursor read"}
    case UnsupportedPlatform{}: Backup.UnsupportedPlatform{}
