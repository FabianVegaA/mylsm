import Base

type TimingMode is Data:
  TimingOff{}
  TimingOn{}
  TimingOnce{}

type ComputeMode is Data:
  Cpu{}
  Gpu{}
  Auto{}

type Command is Data:
  Noop{}
  Put{key: String, value: String}
  Get{key: String}
  Del{key: String}
  Scan{lo: String, hi: String}
  Flush{}
  Compact{}
  Maintain{}
  Stats{}
  Runtime{}
  Timing{mode: TimingMode}
  Mode{mode: ComputeMode}
  Threads{count: Nat}
  Compute{fuel: Nat}
  Import{path: String}
  Export{path: String}
  Time{inner: String}
  Help{}
  Exit{}
  Invalid{message: String}
