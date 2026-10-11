import Base
import ../src/transfer/RestorePolicy.bend as RestorePolicy

# An empty declaration cannot yield a current block.
law no_blocks_cannot_advance:
  {RestorePolicy.after_block(0n) == RestorePolicy.Invalid{} : RestorePolicy.Advance}

# Processing the only declared block reaches the terminal state.
law last_block_finishes:
  {RestorePolicy.after_block(1n) == RestorePolicy.Finish{} : RestorePolicy.Advance}

# Processing the first of two blocks retains exactly one.
law two_blocks_leave_one:
  {RestorePolicy.after_block(2n) == RestorePolicy.Continue{1n} : RestorePolicy.Advance}

# Processing a larger run decreases its count by exactly one.
law later_blocks_decrease_once:
  {RestorePolicy.after_block(17n) == RestorePolicy.Continue{16n} : RestorePolicy.Advance}

# Empty input requires no write page.
law empty_restore_has_no_pages:
  {RestorePolicy.write.pages(0n) == 0n : Nat}

# A restore page contains at most sixteen records.
law one_page_holds_sixteen_records:
  {RestorePolicy.write.pages(16n) == 1n : Nat}

# The first record after a full page requires another page.
law seventeenth_record_starts_second_page:
  {RestorePolicy.write.pages(17n) == 2n : Nat}

# Each page reserves a bounded sequence of state transitions and a terminal step.
law restore_fuel_covers_page_transitions:
  {RestorePolicy.write.fuel(17n) == 7n : Nat}

# The configured exchange-file byte limit is accepted.
law exchange_file_limit_is_inclusive:
  {RestorePolicy.exchange.fits(64n, 64n) == True{} : Bool}

# One byte beyond the configured exchange-file bound is rejected.
law exchange_file_over_limit_is_rejected:
  {RestorePolicy.exchange.fits(64n, 65n) == False{} : Bool}
