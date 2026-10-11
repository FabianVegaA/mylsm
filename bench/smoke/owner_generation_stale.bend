import Base
import ../../src/Console.bend as Console
import ../../src/coordinator/Client.bend as Client
import ../../src/coordinator/ByteClient.bend as ByteClient
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the fixture unless the server rejects the old session generation.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Accepts only the stale-owner result for a prior generation token.
def checked(
  pair: Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (_, Fail{Client.StaleOwner{}}):
      IO.print("OWNER_GENERATION_STALE_SESSION_REJECTED")
    case (_, _): fail("old owner generation was not rejected")

def main() -> IO(Unit):
  do IO<Unit>:
    endpoint : String <- IO.try(String, Console.get_env("MYLSM_OWNER_ENDPOINT"))
    pair : Client.Session & Result<&1, &1, Client.Error,
      Maybe<&1, Bytes.Bytes>> <-
        ByteClient.get(Client.session.open(endpoint, 1), Bytes.new(0))
    checked(pair)
