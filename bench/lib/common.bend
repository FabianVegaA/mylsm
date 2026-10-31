import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM

# Shared bench helpers, deduplicated from million_writes.bend,
# phase3_metrics.bend, compaction_bench.bend, crash_worker.bend and app/.

# Read the environment setting for default for the benchmark fixture helpers.
def env_default(value: String, fallback: String) -> String:
  match value:
    case SNil{}: fallback
    case SCon{h, t}: SCon{h, t}

# Parse the natural-number setting for default for the benchmark fixture helpers.
def nat_default(value: Maybe<&2, Nat>, fallback: Nat) -> Nat:
  match value:
    case None{}: fallback
    case Some{n}: n

# Evaluate text for the benchmark fixture helpers.
def bool_text(ok: Bool) -> String:
  match ok:
    case True{}: "pass"
    case False{}: "fail"

# Handle the optional value for value eq for the benchmark fixture helpers.
def maybe_value_eq(got: Maybe<&2, String>, +expected: String) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{value}:
      String.eq(value, expected)

# Check benchmark samples for and for the benchmark fixture helpers.
def samples_and(first: Bool, second: Bool, third: Bool) -> Bool:
  match first:
    case False{}:
      False{}
    case True{}:
      match second:
        case False{}:
          False{}
        case True{}:
          third

def sample.read(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>,
  +expected: String
) -> MyLSM.Utf8.Handle & Bool:
  match pair:
    case (handle, Done{value}): (handle, maybe_value_eq(value, expected))
    case (handle, Fail{_}): (handle, False{})

# Reads key-N and checks it holds value-N.
def sample(handle: MyLSM.Utf8.Handle, +index: Nat) -> IO(MyLSM.Utf8.Handle & Bool):
  do IO<MyLSM.Utf8.Handle & Bool>:
    pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <-
      MyLSM.Utf8.get(handle, "key-" ++ Nat.show(index))
    return sample.read(pair, "value-" ++ Nat.show(index))

def samples.last(
  first: Bool,
  second: Bool,
  pair: MyLSM.Utf8.Handle & Bool
) -> MyLSM.Utf8.Handle & Bool:
  match pair:
    case (handle, third): (handle, samples_and(first, second, third))

def samples.middle(
  first: Bool,
  pair: MyLSM.Utf8.Handle & Bool,
  +last: Nat
) -> IO(MyLSM.Utf8.Handle & Bool):
  match pair:
    case (handle, second):
      do IO<MyLSM.Utf8.Handle & Bool>:
        third : MyLSM.Utf8.Handle & Bool <- sample(handle, last)
        return samples.last(first, second, third)

def samples.first(
  pair: MyLSM.Utf8.Handle & Bool,
  +middle: Nat,
  +last: Nat
) -> IO(MyLSM.Utf8.Handle & Bool):
  match pair:
    case (handle, first):
      do IO<MyLSM.Utf8.Handle & Bool>:
        second : MyLSM.Utf8.Handle & Bool <- sample(handle, middle)
        samples.middle(first, second, last)

# Checks the first, middle and last of count written keys.
def samples(handle: MyLSM.Utf8.Handle, +count: Nat) -> IO(MyLSM.Utf8.Handle & Bool):
  do IO<MyLSM.Utf8.Handle & Bool>:
    first : MyLSM.Utf8.Handle & Bool <- sample(handle, 0n)
    samples.first(first, Nat.div(count, 2n), Nat.sub(count, 1n))
