import Base
import ../../src/Console.bend as Console
import ../../src/Flush.bend as Flush
import ../../src/Manifest.bend as Manifest

# Publishes a two-table manifest for an aggregate-budget validation fixture.
def published(result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "could not publish aggregate SST fixture")
    case Done{Unit{}}: IO.print("LEGACY_SST_MULTI_MANIFEST_CREATED")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, U32 & String, Unit> <-
      Flush.write_manifest(path ++ "/MANIFEST",
        Manifest.M{Con{Con{"0.tbl", Con{"1.tbl", Nil{}}},
          Con{Nil{}, Con{Nil{}, Con{Nil{}, Nil{}}}}}})
    published(result)
