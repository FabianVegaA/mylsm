import Base
import ../src/Db.bend as Db
import ../src/Recover.bend as Recover

# Task 11 timing smoke benchmark. It records one acknowledged put and the
# elapsed time; larger loops can be layered on this same API after calibration.
def main() -> IO(Unit):
  do IO<Unit>:
    h : Db.Db <- IO.try(Db.Db, Recover.open_db("bench-data"))
    t0 : Nat <- IO.now()
    r : Result<&1, &1, U32 & String, Db.Db> <- Db.db_put(h, "bench-key", "v")
    _h2 : Db.Db <- IO.try(Db.Db, IO.pure(Result<&1, &1, U32 & String, Db.Db>, r))
    t1 : Nat <- IO.now()
    IO.print("single_put_elapsed_ms=" ++ Nat.show(Nat.sub(t1, t0)))
    IO.print("single_put_ops=1")
