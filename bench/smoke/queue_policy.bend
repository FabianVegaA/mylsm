import Base
import ../../src/coordinator/QueuePolicy.bend as Policy

# Checks the exact-capacity admission result.
def valid(decision: Policy.Decision) -> Bool:
  match decision:
    case Policy.Accepted{4n, 16n}: True{}
    case _: False{}

# Reports whether the boundary decision matched its expected result.
def result(passed: Bool) -> IO(Unit):
  match passed:
    case True{}: IO.print("QUEUE_POLICY_BOUNDARY_ACCEPTED")
    case False{}: IO.die(Unit, 1, "queue boundary policy mismatch")

def main() -> IO(Unit):
  result(valid(Policy.admit(3n, 12n, 4n, 4n, 16n)))
