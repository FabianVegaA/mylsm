import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM

# Builds a pure in-memory session for the compatibility namespace.
def in_memory_session() -> MyLSM.InMemory.Session<&2, Maybe<&2, String>>:
  do MyLSM.InMemory.Session<&2, Maybe<&2, String>>:
    MyLSM.InMemory.Session.put("key", "memory-value")
    value : Maybe<&2, String> <- MyLSM.InMemory.Session.get("key")
    return value

# Checks successful scoped completion.
def finish_value_matches(result: Result<&1, &1, MyLSM.SessionError, U32>) -> Bool:
  match result:
    case Done{7}: True{}
    case _: False{}

# Checks operation failure preservation.
def finish_operation_matches(result: Result<&1, &1, MyLSM.SessionError, U32>) -> Bool:
  match result:
    case Fail{MyLSM.OperationFailure{MyLSM.Error{MyLSM.IoError{}, _, _, _, _}}}: True{}
    case _: False{}

# Checks close failure preservation.
def finish_close_matches(result: Result<&1, &1, MyLSM.SessionError, U32>) -> Bool:
  match result:
    case Fail{MyLSM.CloseFailure{MyLSM.Error{MyLSM.InvalidArgumentError{}, _, _, _, _}}}: True{}
    case _: False{}

# Checks combined failure preservation.
def finish_both_matches(result: Result<&1, &1, MyLSM.SessionError, U32>) -> Bool:
  match result:
    case Fail{MyLSM.OperationAndCloseFailure{
      MyLSM.Error{MyLSM.IoError{}, _, _, _, _},
      MyLSM.Error{MyLSM.InvalidArgumentError{}, _, _, _, _}
    }}: True{}
    case _: False{}

# Exercises the scoped result combinations.
def session_finish_checks() -> Bool:
  Bool.and(
    finish_value_matches(MyLSM.Session.finish_result(
      &2, U32, Done{7}, Done{Unit{}}
    )),
    Bool.and(
      finish_operation_matches(MyLSM.Session.finish_result(
        &2, U32, Fail{MyLSM.Error{MyLSM.IoError{}, "put", "/db", 5, "write"}}, Done{Unit{}}
      )),
      Bool.and(
        finish_close_matches(MyLSM.Session.finish_result(
          &2, U32, Done{7}, Fail{MyLSM.Error{MyLSM.InvalidArgumentError{}, "close", "/db", 22, "close"}}
        )),
        finish_both_matches(MyLSM.Session.finish_result(
          &2,
          U32,
          Fail{MyLSM.Error{MyLSM.IoError{}, "put", "/db", 5, "write"}},
          Fail{MyLSM.Error{MyLSM.InvalidArgumentError{}, "close", "/db", 22, "close"}}
        ))
      )
    )
  )

# Reports the scoped result checks.
def finish_cases_result(passed: Bool) -> IO(Unit):
  match passed:
    case True{}: IO.print("SESSION_CLOSE_CASES")
    case False{}: IO.die(Unit, 1, "session completion errors were not preserved")

# Verifies the scoped create result.
def create_result(result: Result<&1, &1, MyLSM.SessionError, Maybe<&2, String>>) -> IO(Unit):
  match result:
    case Done{Some{"durable-value"}}: IO.print("SESSION_CREATED")
    case _ : IO.die(Unit, 1, "durable session did not commit its write")

# Verifies recovered data from a scoped open.
def open_result(result: Result<&1, &1, MyLSM.SessionError, Maybe<&2, String>>) -> IO(Unit):
  match result:
    case Done{Some{"durable-value"}}: IO.print("SESSION_RECOVERED")
    case _ : IO.die(Unit, 1, "durable session did not recover its write")

# Verifies session errors stop the program.
def failure_result(result: Result<&1, &1, MyLSM.SessionError, Unit>) -> IO(Unit):
  match result:
    case Fail{MyLSM.OperationFailure{MyLSM.Error{MyLSM.InvalidArgumentError{}, _, _, _, _}}}:
      IO.print("SESSION_STOPPED_ON_ERROR")
    case _ : IO.die(Unit, 1, "durable session did not return its operation error")

# Verifies open rejects a missing database.
def missing_open_result(result: Result<&1, &1, MyLSM.SessionError, Unit>) -> IO(Unit):
  match result:
    case Fail{MyLSM.OpenFailure{MyLSM.Error{MyLSM.NotFoundError{}, _, _, _, _}}}:
      IO.print("SESSION_OPEN_REQUIRES_EXISTING_DATABASE")
    case _ : IO.die(Unit, 1, "open_database created a missing database")

# Verifies create rejects an existing database.
def duplicate_create_result(result: Result<&1, &1, MyLSM.SessionError, Unit>) -> IO(Unit):
  match result:
    case Fail{MyLSM.OpenFailure{MyLSM.Error{MyLSM.AlreadyExistsError{}, _, _, _, _}}}:
      IO.print("SESSION_CREATE_REJECTS_EXISTING_DATABASE")
    case _ : IO.die(Unit, 1, "create_database accepted an existing database")

# Verifies a failed program skipped its later write.
def absent_result(result: Result<&1, &1, MyLSM.SessionError, Maybe<&2, String>>) -> IO(Unit):
  match result:
    case Done{None{}}: IO.print("SESSION_RELEASED_AFTER_ERROR")
    case _ : IO.die(Unit, 1, "durable session ran after failure or kept the lock")

# Verifies the long-lived handle can close.
def manual_closed(result: Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("SESSION_HANDLE_RETAINED")
    case _ : IO.die(Unit, 1, "manual session handle did not close")

# Closes the handle after the second program.
def manual_second(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{"durable-value"}}):
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        manual_closed(result)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "second session lost the durable value")

# Verifies one program result while retaining its handle.
def manual_value(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{"durable-value"}}):
      do IO<Unit>:
        second : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>> <- MyLSM.run_session(
          &2,
          Maybe<&2, String>,
          handle,
          do MyLSM.Session<&2, Maybe<&2, String>>:
            value : Maybe<&2, String> <- MyLSM.Session.get("key")
            return value
        )
        manual_second(second)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "manual session did not read the durable value")

# Runs a session using the explicit handle API.
def manual_opened(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>> <- MyLSM.run_session(
          &2,
          Maybe<&2, String>,
          handle,
          do MyLSM.Session<&2, Maybe<&2, String>>:
            value : Maybe<&2, String> <- MyLSM.Session.get("key")
            return value
        )
        manual_value(pair)
    case Fail{_}: IO.die(Unit, 1, "manual session open failed")

# Builds a session whose first write is invalid.
def aborting_session() -> MyLSM.Session<&2, Unit>:
  do MyLSM.Session<&2, Unit>:
    _outcome : MyLSM.WriteOutcome <- MyLSM.Session.write_batch(Nil{})
    _later_outcome : MyLSM.WriteOutcome <- MyLSM.Session.put("after-failure", "must-not-appear")
    return Unit{}

# Builds a session with no database changes.
def empty_session() -> MyLSM.Session<&2, Unit>:
  do MyLSM.Session<&2, Unit>:
    return Unit{}

# Creates a database and checks the durable session lifecycle.
def create_session(+path: String) -> IO(Unit):
  do IO<Unit>:
    missing : Result<&1, &1, MyLSM.SessionError, Unit> <- MyLSM.open_database(
      &2,
      Unit,
      path,
      empty_session()
    )
    missing_open_result(missing)
    result : Result<&1, &1, MyLSM.SessionError, Maybe<&2, String>> <- MyLSM.create_database(
      &2,
      Maybe<&2, String>,
      path,
      do MyLSM.Session<&2, Maybe<&2, String>>:
        outcome : MyLSM.WriteOutcome <- MyLSM.Session.put("key", "durable-value")
        value : Maybe<&2, String> <- MyLSM.Session.get("key")
        return value
    )
    create_result(result)
    duplicate : Result<&1, &1, MyLSM.SessionError, Unit> <- MyLSM.create_database(
      &2,
      Unit,
      path,
      empty_session()
    )
    duplicate_create_result(duplicate)

# Reopens a database and checks error cleanup.
def open_session(+path: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLSM.SessionError, Maybe<&2, String>> <- MyLSM.open_database(
      &2,
      Maybe<&2, String>,
      path,
      do MyLSM.Session<&2, Maybe<&2, String>>:
        value : Maybe<&2, String> <- MyLSM.Session.get("key")
        return value
    )
    open_result(result)
    failed : Result<&1, &1, MyLSM.SessionError, Unit> <- MyLSM.open_database(
      &2,
      Unit,
      path,
      aborting_session()
    )
    failure_result(failed)
    absent : Result<&1, &1, MyLSM.SessionError, Maybe<&2, String>> <- MyLSM.open_database(
      &2,
      Maybe<&2, String>,
      path,
      do MyLSM.Session<&2, Maybe<&2, String>>:
        value : Maybe<&2, String> <- MyLSM.Session.get("after-failure")
        return value
    )
    absent_result(absent)
    manual : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
    manual_opened(manual)

# Selects the fixture lifecycle.
def run_mode(path: String, mode: String) -> IO(Unit):
  match mode:
    case "create": create_session(path)
    case _: open_session(path)

def main() -> IO(Unit):
  do IO<Unit>:
    finish_cases_result(session_finish_checks())
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_SESSION_MODE"))
    run_mode(path, mode)
