import Base
import ../src/MemTable.bend as MemTable
import ../src/RecoverPure.bend as Recover

# Handle nf mem2 in the recovery laws.
def nf_mem2() -> MemTable.MemTable:
  MemTable.MT{Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}}

# Handle nf mem1 in the recovery laws.
def nf_mem1() -> MemTable.MemTable:
  MemTable.MT{Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}

# State the needs flush hi property for the recovery laws.
law needs_flush_hi:
  {Recover.needs_flush_cap(nf_mem2(), 1n) == True{} : Bool}

# State the needs flush lo property for the recovery laws.
law needs_flush_lo:
  {Recover.needs_flush_cap(nf_mem1(), 1n) == False{} : Bool}

# State the count gen one property for the recovery laws.
law count_gen_one:
  {Recover.count_gen(Con{Con{"l0-.tbl", Nil{}}, Nil{}}) == 1n : Nat}

# State the generation decimal branch property for the recovery laws.
law generation_decimal_branch:
  {Recover.gen_value_read(Some{12n}) == 12n : Nat}

# State the generation shape branches property for the recovery laws.
law generation_shape_branches:
  {(Recover.gen_valid_read(Some{12n}), Recover.gen_valid_read(None{})) == (True{}, False{}) : Bool & Bool}

# States the recovery rejects fifth manifest level property.
law recovery_rejects_fifth_manifest_level:
  {Recover.manifest_names_ok(Con{Nil{}, Con{Nil{}, Con{Nil{}, Con{Nil{}, Con{Nil{}, Nil{}}}}}}, 0n) == False{} : Bool}

# States the recovery accepts four manifest levels property.
law recovery_accepts_four_manifest_levels:
  {Recover.manifest_names_ok(Con{Nil{}, Con{Nil{}, Con{Nil{}, Con{Nil{}, Nil{}}}}}, 0n) == True{} : Bool}
