import Base
import ../src/Wal.bend as Wal
import ../src/MemTable.bend as MemTable
import ../src/Recover.bend as Recover

# Small local fixture duplicated from the WAL domain.
def batch_put1() -> Wal.Batch:
  Wal.Batch{Con{Wal.Put{"k", "v"}, Nil{}}}

# --- Recovery + maintenance (Task 10): closed vectors (spec law 7) ---

# LAW: frame length parses (closed)
law frame_len_ok:
  {Recover.frame_len(Recover.frame_of("abc")) == Some{3n} : Maybe<&2, Nat>}

# LAW: single-frame replay applies the batch (closed; composes wal_rt)
law replay_single:
  {Recover.replay_mem(Recover.frame_of(Wal.encode(batch_put1()))) == MemTable.MT{Con{MemTable.Entry{"k", Some{"v"}}, Nil{}}} : MemTable.MemTable}

# LAW: torn tail replays to the valid prefix — here empty (closed)
law replay_torn:
  {Recover.replay_mem("---;ab") == MemTable.empty() : MemTable.MemTable}

def nf_mem2() -> MemTable.MemTable:
  MemTable.MT{Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}}

def nf_mem1() -> MemTable.MemTable:
  MemTable.MT{Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}

# LAW: flush gate fires above cap (closed)
law needs_flush_hi:
  {Recover.needs_flush_cap(nf_mem2(), 1n) == True{} : Bool}

# LAW: flush gate rests at/below cap (closed)
law needs_flush_lo:
  {Recover.needs_flush_cap(nf_mem1(), 1n) == False{} : Bool}

# LAW: counter restores to max dashes + 1 (closed)
law count_gen_one:
  {Recover.count_gen(Con{Con{"l0-.tbl", Nil{}}, Nil{}}) == 1n : Nat}


law generation_decimal_branch:
  {Recover.gen_value_read(Some{12n}) == 12n : Nat}

law generation_shape_branches:
  {(Recover.gen_valid_read(Some{12n}), Recover.gen_valid_read(None{})) == (True{}, False{}) : Bool & Bool}


# LAW: recovery equivalence — replayed reads equal pre-crash reads (closed)
law recover_equiv:
  {MemTable.get(Recover.replay_mem(Recover.frame_of(Wal.encode(batch_put1()))), "k") == MemTable.get(MemTable.MT{Con{MemTable.Entry{"k", Some{"v"}}, Nil{}}}, "k") : Maybe<&2, String>}
