import Base
import ./ClientPolicy.bend as ClientPolicy

# Duplicates the request sequence carried by the same client session state.
def requests.clone(
  sequence: ClientPolicy.RequestSequence
) -> ClientPolicy.RequestSequence & ClientPolicy.RequestSequence:
  match sequence:
    case ClientPolicy.RequestAvailable{+id}:
      (ClientPolicy.RequestAvailable{id}, ClientPolicy.RequestAvailable{id})
    case ClientPolicy.RequestExhausted{}:
      (ClientPolicy.RequestExhausted{}, ClientPolicy.RequestExhausted{})
