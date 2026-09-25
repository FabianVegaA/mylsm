import Base
import ../src/Console.bend as Console
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable

# Bloom build matrix (Phase C1): sequential vs CPU-parallel chunks vs GPU
# chunks over the same 4096-entry table. Run the native binary with and
# without `--gpu off`; report all three rows, switch builders only on numbers.

def mk_entries(fuel: Nat, +start: Nat, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      mk_entries(f, Nat.add(start, 1n), Con{MemTable.Entry{"key-" ++ Nat.show(start), Some{"v"}}, acc})

def table_chunks(+tab: Sstable.Table) -> List<&2, List<&2, MemTable.Entry>>:
  match tab:
    case Sstable.Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      chunks

def force_bits(bloom: Sstable.Bloom) -> Nat:
  match bloom:
    case Sstable.Blm{bits, size}:
      size

def main() -> IO(Unit):
  do IO<Unit>:
    +size : Nat <- IO.pure(Nat, 4096n)
    +tab : Sstable.Table <- IO.pure(Sstable.Table, Sstable.build(mk_entries(size, 0n, Nil{}), 0n, 4096n))
    +chunks : List<&2, List<&2, MemTable.Entry>> <- IO.pure(List<&2, List<&2, MemTable.Entry>>, table_chunks(tab))
    s0 : Nat <- IO.now()
    std_bits : Nat <- IO.pure(Nat, force_bits(Sstable.bloom_of(mk_entries(size, 0n, Nil{}), Sstable.bloom_new(Sstable.bloom_bits(0n, 4096n)))))
    +s1 : Nat <- IO.now()
    par_bits : Nat <- IO.pure(Nat, force_bits(Sstable.bloom_chunks(chunks, Sstable.bloom_bits(0n, 4096n), Sstable.bloom_new(Sstable.bloom_bits(0n, 4096n)))))
    +s2 : Nat <- IO.now()
    gpu_bits : Nat <- IO.pure(Nat, force_bits(Sstable.bloom_chunks_gpu(chunks, Sstable.bloom_bits(0n, 4096n), Sstable.bloom_new(Sstable.bloom_bits(0n, 4096n)))))
    s3 : Nat <- IO.now()
    _u0 : Unit <- IO.print("bloom_seq_ms=" ++ Nat.show(Nat.sub(s1, s0)) ++ " bits=" ++ Nat.show(std_bits))
    _u1 : Unit <- IO.print("bloom_par_ms=" ++ Nat.show(Nat.sub(s2, s1)) ++ " bits=" ++ Nat.show(par_bits))
    _u2 : Unit <- IO.print("bloom_gpu_ms=" ++ Nat.show(Nat.sub(s3, s2)) ++ " bits=" ++ Nat.show(gpu_bits))
    IO.print("bloom_matrix=complete")
