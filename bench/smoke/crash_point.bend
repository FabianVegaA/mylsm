import Base
import ../../src/CrashPoint.bend as CrashPoint

def main() -> IO(Unit):
  do IO<Unit>:
    _hit : Unit <- IO.try(Unit, CrashPoint.hit("smoke.stop"))
    IO.print("crash_point_smoke_program=complete")
