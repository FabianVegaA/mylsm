import Base
import ../../src/Console.bend as Console

def main() -> IO(Unit):
  do IO<Unit>:
    line : String <- IO.try(String, Console.read_line())
    env : String <- IO.try(String, Console.get_env("MYLSM_TEST_ENV"))
    IO.print("line=" ++ line)
    IO.print("env=" ++ env)
