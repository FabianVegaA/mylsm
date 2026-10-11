import Base
import ../src/coordinator/CursorCountPolicy.bend as Policy

# Counts the first owner cursor item without truncating it.
law initial_count_advances_to_one:
  {Policy.next(0) == Policy.CountContinue{1} : Policy.Decision}

# Rejects the first item beyond the maximum serialized entry count.
law maximum_count_does_not_wrap:
  {Policy.next(4294967295) == Policy.CountLimit{} : Policy.Decision}
