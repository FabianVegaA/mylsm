import Base

# Pure SSTable filename policy, shared by the flush effect and its laws.
def table_name(flushed: Nat) -> String:
  "l0-" ++ Nat.show(flushed) ++ ".tbl"
