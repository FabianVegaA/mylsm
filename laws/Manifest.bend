import Base
import ../src/Manifest.bend as Manifest

# --- Manifest (Task 5): closed vectors + fuzz (same strategy as WAL) ---

def mfst_empty() -> Manifest.Manifest:
  Manifest.M{Nil{}}

def mfst_two() -> Manifest.Manifest:
  Manifest.M{Con{Con{"a.tbl", Con{"b.tbl", Nil{}}}, Con{Con{"c.tbl", Nil{}}, Nil{}}}}

law manifest_empty:
  {Manifest.parse(Manifest.serialize(mfst_empty())) == Some{mfst_empty()} : Maybe<&2, Manifest.Manifest>}

law manifest_two:
  {Manifest.parse(Manifest.serialize(mfst_two())) == Some{mfst_two()} : Maybe<&2, Manifest.Manifest>}

# Decoder totality: every input reaches a decided fail-closed result.
law manifest_fail_closed:
  for +s: String
  {Manifest.is_decided(Manifest.parse(s)) == True{} : Bool}
