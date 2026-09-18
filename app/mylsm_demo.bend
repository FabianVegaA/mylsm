import Base
import ../src/Db.bend as Db
import ../src/Recover.bend as Recover
import ./demo_helpers.bend as Demo

def open_or_die(+dir: String) -> IO(Db.Db):
  IO.try(Db.Db, Recover.open_db(dir))

def put_or_die(+db: Db.Db, +k: String, +v: String) -> IO(Db.Db):
  IO.try(Db.Db, Db.db_put(db, k, v))

def delete_or_die(+db: Db.Db, +k: String) -> IO(Db.Db):
  IO.try(Db.Db, Db.db_del(db, k))

def main() -> IO(Unit):
  do IO<Unit>:
    db0 : Db.Db <- open_or_die(".mylsm-demo-data")
    db1 : Db.Db <- put_or_die(db0, "hello", "world")
    +db2 : Db.Db <- put_or_die(db1, "answer", "42")
    before : String <- IO.pure(String, Demo.show_maybe(Db.db_get(db2, "hello")))
    answer : String <- IO.pure(String, Demo.show_maybe(Db.db_get(db2, "answer")))
    +db3 : Db.Db <- delete_or_die(db2, "hello")
    after : String <- IO.pure(String, Demo.show_maybe(Db.db_get(db3, "hello")))
    compute : Nat <- IO.pure(Nat, Demo.worker_gpu!(32n, 0n))
    IO.print("MyLSM demo")
    IO.print("  hello = " ++ before)
    IO.print("  answer = " ++ answer)
    IO.print("  hello after delete = " ++ after)
    IO.print("  compute = " ++ Nat.show(compute))
    IO.print("MYLSM DEMO OK")
