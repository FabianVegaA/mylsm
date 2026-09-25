import Base
import ../src/Wal.bend as Wal

# --- WAL codec (Task 3) ---

# LAW: WAL codec round-trip (closed vectors; each is proven by {==}
# normalization alone — no manual P's, no fragility).
# The OPEN round-trip (all batches) is fuzz-verified (Task 12, 1M+ inputs)
# and its full proof is deferred: open-key/open-length joint induction is not
# currently accepted by the Bend 2.0.9 checker (syntactic P-matching over pump
# states with stuck-open tails). See spec §3.2.
# Open concat-merges attempted 2026-09-25 (Phase 2D): `{==}` rejected, needs
# the same deferred induction. Closed wal_concat_merges plus 1M fuzz stand.

# Batch fixtures (named defs: the parser rejects nested Con inside Some).
def batch_empty() -> Wal.Batch:
  Wal.Batch{Nil{}}

def batch_put1() -> Wal.Batch:
  Wal.Batch{Con{Wal.Put{"k", "v"}, Nil{}}}

def batch_del1() -> Wal.Batch:
  Wal.Batch{Con{Wal.Del{"k"}, Nil{}}}

def batch_multi() -> Wal.Batch:
  Wal.Batch{Con{Wal.Put{"a", ""}, Con{Wal.Del{"b"}, Con{Wal.Put{"", "c"}, Nil{}}}}}

law wal_rt_empty:
  {Wal.decode(Wal.encode(batch_empty())) == Some{batch_empty()} : Maybe<&2, Wal.Batch>}

law wal_rt_put1:
  {Wal.decode(Wal.encode(batch_put1())) == Some{batch_put1()} : Maybe<&2, Wal.Batch>}

law wal_rt_del1:
  {Wal.decode(Wal.encode(batch_del1())) == Some{batch_del1()} : Maybe<&2, Wal.Batch>}

law wal_rt_multi:
  {Wal.decode(Wal.encode(batch_multi())) == Some{batch_multi()} : Maybe<&2, Wal.Batch>}

# Decoder totality: every input reaches a decided fail-closed result.
law wal_fail_closed:
  for +s: String
  {Wal.is_decided(Wal.decode(s)) == True{} : Bool}

# LAW: concatenated encodings decode as one merged batch (closed; sequence
# semantics — the framing layer owns boundaries, decode consumes sequences).
law wal_concat_merges:
  {Wal.decode(Wal.encode(batch_put1()) ++ Wal.encode(batch_del1())) == Some{Wal.Batch{Con{Wal.Put{"k", "v"}, Con{Wal.Del{"k"}, Nil{}}}}} : Maybe<&2, Wal.Batch>}
