import Base
import ../laws/OptionsCodec.bend as Laws
import ../src/ResourceOptions.bend as ResourceOptions

def Laws.option_fields_roundtrip(options):
  match options:
    case ResourceOptions.Options{transport, queue, readers}:
      match transport:
        case ResourceOptions.TransportLimits{_, _, _, _, _, _}:
          match queue:
            case ResourceOptions.QueueLimits{_, _, _}:
              match readers:
                case ResourceOptions.ReaderLimits{_, _, _, _, _, _, _, _}:
                  {==}

def Laws.wrong_length_is_malformed():
  {==}

def Laws.unknown_version_is_rejected():
  {==}
