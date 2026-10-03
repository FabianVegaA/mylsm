import Base
import ./repl_types.bend as Repl

# Pure REPL decisions and path formatting, separated from its IO executor.
def timing_should(mode: Repl.TimingMode) -> Bool:
  match mode:
    case Repl.TimingOff{}: False{}
    case Repl.TimingOn{}: True{}
    case Repl.TimingOnce{}: True{}

def timing_once(mode: Repl.TimingMode) -> Bool:
  match mode:
    case Repl.TimingOnce{}: True{}
    case _: False{}

def parent_parts(parts: List<&2, String>, acc: List<&2, String>) -> String:
  match parts:
    case Nil{}:
      "."
    case Con{last, Nil{}}:
      match acc:
        case Nil{}:
          "."
        case Con{h, t}:
          String.join(List.reverse(&2, String, Con{h, t}), "/")
    case Con{h, Con{k, t}}:
      parent_parts(Con{k, t}, Con{h, acc})

def parent_path(path: String) -> String:
  parent_parts(String.split(path, '/'), Nil{})

def restart_bounds(+count: Nat, +current: Nat) -> Bool:
  Bool.and(Nat.is_lt(0n, count), Bool.and(Nat.is_lt(count, 257n), Bool.not(Nat.is_eq(count, current))))
