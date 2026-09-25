import Base
import ../src/Fs.bend as Fs

def print_all(xs: List<String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      do IO<Unit>:
        IO.print(h)
        print_all(t)

def close_checked(p: (File & Result<&1, &1, U32 & String, Unit>)) -> IO(Unit):
  match p:
    case (a, b):
      do IO<Unit>:
        _u : Unit <- IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, b))
        File.close(a)

def main() -> IO(Unit):
  do IO<Unit>:
    _mk : Unit <- IO.try(Unit, Fs.make_dir("smoke-data"))
    f : File <- IO.try(File, File.open("smoke-data/a.txt", "w"))
    fr : (File & Result<&1, &1, U32 & String, Unit>) <- File.write(f, "hello")
    _cu : Unit <- close_checked(fr)
    _su : Unit <- IO.try(Unit, Fs.fsync("smoke-data/a.txt"))
    _mu : Unit <- IO.try(Unit, Fs.chmod("smoke-data/a.txt", 384))
    _nu : Unit <- IO.try(Unit, Fs.rename("smoke-data/a.txt", "smoke-data/b.txt"))
    names : List<String> <- IO.try(List<String>, Fs.read_dir("smoke-data"))
    IO.print("listed:")
    print_all(names)
    _xu : Unit <- IO.try(Unit, Fs.remove("smoke-data/b.txt"))
    IO.print("SMOKE OK")
