import Base
import ../../src/MemTable.bend as MemTable
import ../../src/Sstable.bend as Sstable

# Bloom tuning harness (Phase A3): builds one table at the current Monkey
# schedule and one at double bits over the same keys, then counts observed
# false positives over absent keys. bloom_bits changes only if data supports it.

def mk_entries(fuel: Nat, +start: Nat, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      mk_entries(f, Nat.add(start, 1n), Con{MemTable.Entry{"key-" ++ Nat.show(start), Some{"v"}}, acc})

def absent_keys(fuel: Nat, +start: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      absent_keys(f, Nat.add(start, 1n), Con{"zz-quux-" ++ Nat.show(start) ++ "-wombat", acc})

def fpr_add(present: Bool, acc: Nat) -> Nat:
  match present:
    case True{}:
      Nat.add(acc, 1n)
    case False{}:
      acc

def fpr_go(+probes: List<&2, String>, +tab: Sstable.Table, acc: Nat) -> Nat:
  match probes:
    case Nil{}:
      acc
    case Con{+q, t}:
      fpr_go(t, tab, fpr_add(Sstable.maybe_present(tab, q), acc))

def report(+tag: String, +tab: Sstable.Table, +probes: Nat) -> IO(Unit):
  do IO<Unit>:
    _rp : Unit <- IO.print("bloom_schedule=" ++ tag ++ " bits=" ++ Nat.show(Sstable.table_bits(tab)) ++ " false_positives=" ++ Nat.show(fpr_go(absent_keys(probes, 0n, Nil{}), tab, 0n)) ++ " probes=" ++ Nat.show(probes))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    +size : Nat <- IO.pure(Nat, 4096n)
    +entries : List<&2, MemTable.Entry> <- IO.pure(List<&2, MemTable.Entry>, mk_entries(size, 0n, Nil{}))
    +std : Sstable.Table <- IO.pure(Sstable.Table, Sstable.build(entries, 0n, 4096n))
    +dbl : Sstable.Table <- IO.pure(Sstable.Table, Sstable.build(entries, 0n, 8192n))
    _rp : Unit <- report("monkey", std, size)
    _rq : Unit <- report("double", dbl, size)
    IO.print("bloom_tune=complete")
