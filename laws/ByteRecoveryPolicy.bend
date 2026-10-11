import Base
import ../src/ByteRecoveryPolicy.bend as Policy

# Identifies index-budget overflow as a resource limit.
law index_budget_overflow_is_a_resource_limit:
  {Policy.is_resource_limit(Policy.resource_limit_error_code()) == True{} : Bool}

# Keeps a corruption code out of the resource-limit category.
law malformed_sst_is_not_a_resource_limit:
  {Policy.is_resource_limit(4294967292) == False{} : Bool}
