import Base

# Represents the validated command line accepted by the CLI.
type Command is Data:
  Demo{}
  Repl{directory: Maybe<&2, String>}
  Doctor{}
  Check{}
  Fuzz{}
  Bench{}
  Build{}
  Run{}
  Help{}

# Represents the requested automatic, CPU, or GPU device policy.
type Device is Data:
  Auto{}
  Cpu{}
  Gpu{}

# Represents the runtime implementation selected for execution.
type Backend is Data:
  PortableCpu{}
  NativeCpu{}
  NativeGpu{}
