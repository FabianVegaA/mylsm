import Base

# Convert a malformed sample to zero; the shell validator rejects malformed rows before reporting.
def read_value(value: Maybe<&2, Nat>) -> Nat:
  match value:
    case None{}: 0n
    case Some{n}: n

# Parse all decimal sample arguments into Bend naturals.
def parse_values(values: List<&1, String>, acc: List<&2, Nat>) -> List<&2, Nat>:
  match values:
    case Nil{}: acc
    case Con{head, tail}:
      parse_values(tail, Con{read_value(Nat.read(head)), acc})

# Count a Boolean predicate as zero or one.
def pick(flag: Bool) -> Nat:
  match flag:
    case True{}: 1n
    case False{}: 0n

# Count samples below a candidate rank value.
def count_lt(+value: Nat, +values: List<&2, Nat>, acc: Nat) -> Nat:
  match values:
    case Nil{}:
      acc
    case Con{head, tail}:
      count_lt(value, tail, Nat.add(acc, pick(Nat.is_lt(head, value))))

# Count samples at or below a candidate rank value.
def count_le(+value: Nat, +values: List<&2, Nat>, acc: Nat) -> Nat:
  match values:
    case Nil{}:
      acc
    case Con{head, tail}:
      count_le(value, tail, Nat.add(acc, pick(Nat.is_le(head, value))))

# Decide whether a rank falls inside a value's duplicate interval.
def rank_is_in(+rank: Nat, low: Nat, high: Nat) -> Bool:
  Bool.and(Nat.is_le(low, rank), Nat.is_lt(rank, high))

# Keep a value only when its sorted interval includes the requested rank.
def selected_value(matches: Bool, old: Nat, value: Nat) -> Nat:
  match matches:
    case True{}: Nat.max(old, value)
    case False{}: old

# Find one order statistic without sorting or mutually recursive helpers.
def select_scan(+rank: Nat, +candidates: List<&2, Nat>, +all: List<&2, Nat>, selected: Nat) -> Nat:
  match candidates:
    case Nil{}:
      selected
    case Con{value, tail}:
      +matches = rank_is_in(rank, count_lt(value, all, 0n), count_le(value, all, 0n))
      select_scan(rank, tail, all, selected_value(matches, selected, value))

# Select the upper middle sample as the median for even-sized inputs.
def select_rank(+rank: Nat, +candidates: List<&2, Nat>, +all: List<&2, Nat>) -> Nat:
  select_scan(rank, candidates, all, 0n)

# Fold the least sample from a non-empty list.
def min_value(+values: List<&2, Nat>, current: Nat) -> Nat:
  match values:
    case Nil{}: current
    case Con{head, tail}: min_value(tail, Nat.min(head, current))

# Fold the greatest sample from a non-empty list.
def max_value(+values: List<&2, Nat>, current: Nat) -> Nat:
  match values:
    case Nil{}: current
    case Con{head, tail}: max_value(tail, Nat.max(head, current))

# Calculate median and max-minus-min spread in Bend.
def stats(+values: List<&2, Nat>) -> (Nat & Nat):
  match values:
    case Nil{}:
      (0n, 0n)
    case Con{head, tail}:
      +count = List.length(&2, Nat, values)
      +middle = Nat.div(count, 2n)
      +median = select_rank(middle, values, values)
      +low = min_value(tail, head)
      +high = max_value(tail, head)
      (median, Nat.sub(high, low))

# Print calculated statistics with their sample count.
def show_stats_pair(pair: (Nat & Nat), count: Nat) -> IO(Unit):
  match pair:
    case (median, spread):
      IO.print("median=" ++ Nat.show(median) ++ " spread=" ++ Nat.show(spread) ++ " samples=" ++ Nat.show(count))

# Calculate statistics for supplied samples.
def show_stats(+values: List<&2, Nat>) -> IO(Unit):
  show_stats_pair(stats(values), List.length(&2, Nat, values))

# Reject zero elapsed time before calculating operations per second.
def report_rate_nonzero(count: Nat, +ms: Nat, is_zero: Bool) -> IO(Unit):
  match is_zero:
    case True{}:
      IO.die(Unit, U32.from_nat(2n), "elapsed time must be positive")
    case False{}:
      IO.print("throughput_ops_per_sec=" ++ Nat.show(Nat.div(Nat.mul(count, 1000n), ms)))

# Validate and unwrap the elapsed-time argument.
def report_rate_elapsed(count: Nat, elapsed: Maybe<&2, Nat>) -> IO(Unit):
  match elapsed:
    case None{}:
      IO.die(Unit, U32.from_nat(2n), "invalid elapsed time")
    case Some{+ms}:
      report_rate_nonzero(count, ms, Nat.is_eq(ms, 0n))

# Validate the operation-count argument.
def report_rate(count: Maybe<&2, Nat>, elapsed: Maybe<&2, Nat>) -> IO(Unit):
  match count:
    case None{}:
      IO.die(Unit, U32.from_nat(2n), "invalid count")
    case Some{n}:
      report_rate_elapsed(n, elapsed)

# Render a Boolean as stable report text.
def bool_text(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

# Print the final time-and-RSS comparison gate.
def compare_report_state(pass: Bool, rss_ok: Bool, elapsed_delta: Nat) -> IO(Unit):
  match pass:
    case True{}:
      IO.print("elapsed_regression_percent_x100=" ++ Nat.show(elapsed_delta) ++ " rss_ok=true status=pass")
    case False{}:
      IO.print("elapsed_regression_percent_x100=" ++ Nat.show(elapsed_delta) ++ " rss_ok=" ++ bool_text(rss_ok) ++ " status=fail")

# Apply the combined elapsed-time and peak-RSS gate.
def compare_report(time_ok: Bool, +rss_ok: Bool, elapsed_delta: Nat) -> IO(Unit):
  compare_report_state(Bool.and(time_ok, rss_ok), rss_ok, elapsed_delta)

# Forward validated gate values to the report formatter.
def compare_result_with_limit(elapsed_delta: Nat, rss_ok: Bool, time_ok: Bool) -> IO(Unit):
  compare_report(time_ok, rss_ok, elapsed_delta)

# Enforce the maximum five-percent elapsed-time regression.
def compare_result(+elapsed_delta: Nat, rss_ok: Bool) -> IO(Unit):
  compare_result_with_limit(elapsed_delta, rss_ok, Nat.is_le(elapsed_delta, 500n))

# Calculate a positive slowdown percentage scaled by one hundred.
def elapsed_delta_nonzero(+base_ms: Nat, candidate_ms: Nat, base_is_zero: Bool) -> Nat:
  match base_is_zero:
    case True{}: 100000n
    case False{}: Nat.div(Nat.mul(Nat.sub(candidate_ms, base_ms), 10000n), base_ms)

# Clamp speedups at zero regression.
def elapsed_delta_direction(base_ms: Nat, candidate_ms: Nat, is_faster: Bool, base_is_zero: Bool) -> Nat:
  match is_faster:
    case True{}: 0n
    case False{}:
      elapsed_delta_nonzero(base_ms, candidate_ms, base_is_zero)

# Compare elapsed times as integer hundredths of a percent.
def elapsed_delta_x100(+base_ms: Nat, +candidate_ms: Nat) -> Nat:
  elapsed_delta_direction(
    base_ms,
    candidate_ms,
    Nat.is_le(candidate_ms, base_ms),
    Nat.is_eq(base_ms, 0n))

# Evaluate one workload's elapsed-time and RSS metrics.
def compare_metrics(
  base_ms: Nat,
  candidate_ms: Nat,
  base_rss: Nat,
  candidate_rss: Nat
) -> IO(Unit):
  compare_result(
    elapsed_delta_x100(base_ms, candidate_ms),
    Nat.is_le(candidate_rss, base_rss))

# Validate candidate RSS and compare a complete metric tuple.
def process_compare_candidate_rss(
  base_ms: Nat,
  candidate_ms: Nat,
  base_rss: Nat,
  candidate_rss: Maybe<&2, Nat>
) -> IO(Unit):
  match candidate_rss:
    case None{}: IO.die(Unit, U32.from_nat(2n), "invalid candidate RSS")
    case Some{candidate}:
      compare_metrics(base_ms, candidate_ms, base_rss, candidate)

# Validate baseline RSS before comparing the candidate.
def process_compare_base_rss(
  base_ms: Nat,
  candidate_ms: Nat,
  base_rss: Maybe<&2, Nat>,
  candidate_rss: Maybe<&2, Nat>
) -> IO(Unit):
  match base_rss:
    case None{}: IO.die(Unit, U32.from_nat(2n), "invalid baseline RSS")
    case Some{base}:
      process_compare_candidate_rss(base_ms, candidate_ms, base, candidate_rss)

# Validate candidate elapsed time before comparing samples.
def process_compare_candidate(
  base_ms: Nat,
  candidate_ms: Maybe<&2, Nat>,
  base_rss: Maybe<&2, Nat>,
  candidate_rss: Maybe<&2, Nat>
) -> IO(Unit):
  match candidate_ms:
    case None{}: IO.die(Unit, U32.from_nat(2n), "invalid candidate time")
    case Some{candidate}:
      process_compare_base_rss(base_ms, candidate, base_rss, candidate_rss)

# Validate baseline elapsed time before comparing samples.
def process_compare_parsed(
  base_ms: Maybe<&2, Nat>,
  candidate_ms: Maybe<&2, Nat>,
  base_rss: Maybe<&2, Nat>,
  candidate_rss: Maybe<&2, Nat>
) -> IO(Unit):
  match base_ms:
    case None{}: IO.die(Unit, U32.from_nat(2n), "invalid baseline time")
    case Some{base}:
      process_compare_candidate(base, candidate_ms, base_rss, candidate_rss)

# Parse the four numeric comparison arguments.
def process_compare(values: List<&1, String>) -> IO(Unit):
  match values:
    case Con{base_ms, Con{candidate_ms, Con{base_rss, Con{candidate_rss, Nil{}}}}}:
      process_compare_parsed(Nat.read(base_ms), Nat.read(candidate_ms), Nat.read(base_rss), Nat.read(candidate_rss))
    case _:
      IO.die(Unit, U32.from_nat(2n), "usage: storage_codec_report.bend compare <base-ms> <candidate-ms> <base-rss> <candidate-rss>")

# Parse an operation count and median elapsed time.
def process_rate(values: List<&1, String>) -> IO(Unit):
  match values:
    case Con{count_text, Con{elapsed_text, Nil{}}}:
      report_rate(Nat.read(count_text), Nat.read(elapsed_text))
    case _:
      IO.die(Unit, U32.from_nat(2n), "usage: storage_codec_report.bend rate <count> <elapsed-ms>")

# Dispatch rate calculation or the comparison gate.
def process_mode_rate(is_rate: Bool, values: List<&1, String>) -> IO(Unit):
  match is_rate:
    case True{}:
      process_rate(values)
    case False{}:
      process_compare(values)

# Dispatch one report operation based on its mode.
def process_mode(is_stats: Bool, is_rate: Bool, values: List<&1, String>) -> IO(Unit):
  match is_stats:
    case True{}:
      show_stats(parse_values(values, Nil{}))
    case False{}:
      process_mode_rate(is_rate, values)

# Parse the reporter's mode and values.
def process_args(args: List<&1, String>) -> IO(Unit):
  match args:
    case Nil{}:
      IO.die(Unit, U32.from_nat(2n), "usage: storage_codec_report.bend <stats|rate> <values...>")
    case Con{+mode, values}:
      process_mode(String.eq(mode, "stats"), String.eq(mode, "rate"), values)

# Drop the executable path from IO.args.
def process_argv(args: List<&1, String>) -> IO(Unit):
  match args:
    case Nil{}:
      IO.die(Unit, U32.from_nat(2n), "missing program arguments")
    case Con{_, tail}:
      process_args(tail)

# Reporter entry point.
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1, String> <- IO.args()
    process_argv(args)
