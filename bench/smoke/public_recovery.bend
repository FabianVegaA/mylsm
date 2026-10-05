import Base
import ../../mylsm.bend as MyLSM
import ../../src/Db.bend as Db

# Compile a consumer call to the public disk-recovery API.
def recovering_api(dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  MyLSM.open_recovering(dir)

# Keep the consumer fixture buildable without opening a database.
def main() -> IO(Unit):
  IO.pure(Unit, Unit{})
