import Base
import ../src/ResourceOptions.bend as Options

# Verifies option comparison checks the ordered field vector.
law option_comparison_checks_the_ordered_field_vector:
  for left: Options.Options
  for right: Options.Options
  {Options.same(left, right) ==
    Options.fields.same(Options.fields(left), Options.fields(right)) : Bool}

# Verifies default options compare equal.
law default_options_compare_equal:
  {Options.same(Options.defaults(), Options.defaults()) == True{} : Bool}

# Verifies default options are valid.
law default_options_are_valid:
  {Options.validate(Options.defaults()) == Options.Accepted{Options.defaults()} : Options.Decision}

# Verifies snapshot limits match defaults.
law snapshot_limits_match_defaults:
  {Options.snapshot.limits(Options.defaults()) == (64, 67108864) : U32 & U32}

# Verifies snapshot retained bytes match defaults.
law snapshot_retained_bytes_match_defaults:
  {Options.snapshot.retained.bytes(Options.defaults()) == 67108864 : U32}

# Verifies cursor per snapshot matches defaults.
law cursor_per_snapshot_matches_defaults:
  {Options.cursor.per.snapshot(Options.defaults()) == 64 : U32}

# Verifies transport frame bytes match defaults.
law transport_frame_bytes_match_defaults:
  {Options.transport.frame.bytes(Options.defaults()) == 16777216 : U32}

# Verifies transport receive bytes match defaults.
law transport_receive_bytes_match_defaults:
  {Options.transport.receive.bytes(Options.defaults()) == 16777216 : U32}

# Verifies transport connection limit matches defaults.
law transport_connection_limit_matches_defaults:
  {Options.transport.connections(Options.defaults()) == 64 : U32}

# Verifies transport frame timeout matches defaults.
law transport_frame_timeout_matches_defaults:
  {Options.transport.frame.timeout(Options.defaults()) == 30000 : U32}

# Verifies transport response timeout matches defaults.
law transport_response_timeout_matches_defaults:
  {Options.transport.response.timeout(Options.defaults()) == 30000 : U32}

# Verifies queue timeout matches defaults.
law queue_timeout_matches_defaults:
  {Options.queue.timeout(Options.defaults()) == 30000 : U32}

# Verifies queue request capacity matches defaults.
law queue_request_capacity_matches_defaults:
  {Options.queue.requests(Options.defaults()) == 64 : U32}

# Verifies queue byte capacity matches defaults.
law queue_byte_capacity_matches_defaults:
  {Options.queue.bytes(Options.defaults()) == 16777216 : U32}

# Verifies response at budget is admitted.
law response_at_budget_is_admitted:
  {Options.response.admitted(16, 16) == True{} : Bool}

# Verifies response over budget is rejected.
law response_over_budget_is_rejected:
  {Options.response.admitted(17, 16) == False{} : Bool}

# Verifies invalid transport is rejected.
law invalid_transport_is_rejected:
  {Options.validate(Options.Options{
    Options.TransportLimits{64, 16, 8, 16, 1, 1},
    Options.QueueLimits{64, 16, 1},
    Options.ReaderLimits{64, 32, 32, 64, 16, 16, 64, 64}}) ==
      Options.InvalidTransport{} : Options.Decision}

# Verifies invalid queue is rejected.
law invalid_queue_is_rejected:
  {Options.validate(Options.Options{
    Options.TransportLimits{64, 16, 16, 16, 1, 1},
    Options.QueueLimits{64, 0, 1},
    Options.ReaderLimits{64, 32, 32, 64, 16, 16, 64, 64}}) ==
      Options.InvalidQueue{} : Options.Decision}

# Verifies invalid readers are rejected.
law invalid_readers_are_rejected:
  {Options.validate(Options.Options{
    Options.TransportLimits{64, 16, 16, 16, 1, 1},
    Options.QueueLimits{64, 16, 1},
    Options.ReaderLimits{64, 32, 33, 64, 16, 16, 64, 64}}) ==
      Options.InvalidReaders{} : Options.Decision}

# Verifies frame must fit receive budget.
law frame_must_fit_receive_budget:
  {Options.transport.valid(Options.TransportLimits{4, 2, 1, 2, 1, 1}) == False{} : Bool}

# Verifies queue budget can be smaller than transport frame.
law queue_budget_can_be_smaller_than_transport_frame:
  {Options.queue.valid(Options.QueueLimits{4, 2, 1}) == True{} : Bool}

# Verifies cursor limit cannot exceed global limit.
law cursor_limit_cannot_exceed_global_limit:
  {Options.readers.valid(Options.ReaderLimits{4, 3, 5, 8, 4, 4, 8, 8}) == False{} : Bool}

# Verifies index page must fit resident budget.
law index_page_must_fit_resident_budget:
  {Options.readers.valid(Options.ReaderLimits{4, 3, 3, 8, 4, 5, 4, 8}) == False{} : Bool}

# Verifies invalid transport has specific decision.
law invalid_transport_has_specific_decision:
  {Options.validate.transport(Options.defaults(), False{}, True{}, True{}) ==
    Options.InvalidTransport{} : Options.Decision}

# Verifies invalid queue has specific decision.
law invalid_queue_has_specific_decision:
  {Options.validate.queue(Options.defaults(), False{}, True{}) ==
    Options.InvalidQueue{} : Options.Decision}

# Verifies invalid readers have specific decision.
law invalid_readers_have_specific_decision:
  {Options.validate.readers(Options.defaults(), False{}) ==
    Options.InvalidReaders{} : Options.Decision}

# Verifies default retired file budget is 64.
law default_retired_file_budget_is_64:
  {Options.reader.retired.files(Options.defaults()) == 64 : U32}
