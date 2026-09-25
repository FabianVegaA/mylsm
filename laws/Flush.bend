import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/Db.bend as Db
import ../src/Flush.bend as Flush

# Small local fixture duplicated from the merge-iterator domain.
def scan_mem() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"a", Some{"v1"}}, Nil{}}}

def fl_pre() -> Db.Db:
  Db.Db{"/d", MemTable.MT{scan_mem()}, MemTable.MT{Nil{}}, 1n, Nil{}, Nil{}, 0n, "", 2n, 0n}

def fl_post() -> Db.Db:
  Db.Db{"/d", MemTable.MT{Nil{}}, MemTable.MT{Nil{}}, 1n, Nil{}, Con{Con{Sstable.build(scan_mem(), 0n, 2n), Nil{}}, Nil{}}, 1n, "", 0n, 0n}

# LAW: pre-flush read hits (closed; kills vacuity for the pair below)
law flush_hit_pre:
  {Db.db_get(fl_pre(), "a") == Some{"v1"} : Maybe<&2, String>}

# LAW: post-flush read hits identically (closed)
law flush_hit_post:
  {Db.db_get(fl_post(), "a") == Some{"v1"} : Maybe<&2, String>}

# LAW: flush preservation shape — reads equal across the transition (closed)
law flush_preserve:
  {Db.db_get(fl_pre(), "a") == Db.db_get(fl_post(), "a") : Maybe<&2, String>}

# LAW: absent key stays absent across flush (closed; meaningful paired
# with the hit laws, which prove reads are not uniformly None)
law flush_miss:
  {Db.db_get(fl_pre(), "z") == Db.db_get(fl_post(), "z") : Maybe<&2, String>}

law table_name_decimal:
  {Flush.table_name(12n) == "l0-12.tbl" : String}
