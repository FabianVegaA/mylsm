import Base
import ../src/ByteMemTable.bend as ByteMemTable
import ../src/Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Unwraps fixed hexadecimal bytes used by the closed ordering witness.
def bytes.fixture(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Builds an intentionally reverse-ordered pair of raw keys.
def reverse_order.fixture() -> ByteMemTable.Table:
  ByteMemTable.put(ByteMemTable.put(ByteMemTable.empty(),
    bytes.fixture(Bytes.from_hex("80")), bytes.fixture(Bytes.from_hex("01"))),
    bytes.fixture(Bytes.from_hex("00")), bytes.fixture(Bytes.from_hex("02")))

def retention.measurement(pair: ByteMemTable.Table & Nat) -> Nat:
  match pair:
    case (_, bytes): bytes

def retention.count(pair: ByteMemTable.Table & Nat) -> Nat:
  match pair:
    case (table, _): ByteMemTable.count(table)

def retention.payload(pair: ByteMemTable.Table & Nat) -> Nat:
  match pair:
    case (table, _): ByteMemTable.payload_bytes(table)

def probe.deleted(pair: ByteMemTable.Table & ByteMemTable.Probe) -> Bool:
  match pair:
    case (_, ByteMemTable.Deleted{}): True{}
    case (_, _): False{}

def probe.absent(pair: ByteMemTable.Table & ByteMemTable.Probe) -> Bool:
  match pair:
    case (_, ByteMemTable.Absent{}): True{}
    case (_, _): False{}

def probe.value(pair: ByteMemTable.Table & ByteMemTable.Probe) -> Bool:
  match pair:
    case (_, ByteMemTable.Present{_}): True{}
    case (_, _): False{}

def ordered.replacement.visible(pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>) -> Bool:
  match pair:
    case (_, Some{value}): Keys.Bytes.eq(value, bytes.fixture(Bytes.from_hex("3230")))
    case (_, None{}): False{}

def ordered.replacement() -> ByteMemTable.Table:
  ByteMemTable.put(ByteMemTable.put(ByteMemTable.empty(),
    bytes.fixture(Bytes.from_hex("62")), bytes.fixture(Bytes.from_hex("32"))),
    bytes.fixture(Bytes.from_hex("62")), bytes.fixture(Bytes.from_hex("3230")))

def ordered.replacement.materialized() -> ByteMemTable.Table:
  ByteMemTable.Table{ByteMemTable.ordered_entries(ordered.replacement())}

def ordered.canonical.fixture() -> ByteMemTable.Table:
  ByteMemTable.put(
    ByteMemTable.put(
      ByteMemTable.del(
        ByteMemTable.put(
          ByteMemTable.put(
            ByteMemTable.put(ByteMemTable.empty(),
              bytes.fixture(Bytes.from_hex("ff")), bytes.fixture(Bytes.from_hex("01"))),
            bytes.fixture(Bytes.from_hex("00")), bytes.fixture(Bytes.from_hex("02"))),
          bytes.fixture(Bytes.from_hex("ff")), bytes.fixture(Bytes.from_hex("03"))),
        bytes.fixture(Bytes.from_hex("00"))),
      bytes.fixture(Bytes.from_hex("0000")), bytes.fixture(Bytes.from_hex("04"))),
    bytes.fixture(Bytes.from_hex("")), bytes.fixture(Bytes.from_hex("05")))

def ordered.canonical.expected() -> List<&1, ByteMemTable.Entry>:
  [ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("")),
      Some{bytes.fixture(Bytes.from_hex("05"))}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("00")), None{}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("0000")),
      Some{bytes.fixture(Bytes.from_hex("04"))}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("ff")),
      Some{bytes.fixture(Bytes.from_hex("03"))}}]

def ordered.final.tombstone.fixture() -> ByteMemTable.Table:
  ByteMemTable.del(ordered.canonical.fixture(), bytes.fixture(Bytes.from_hex("ff")))

def ordered.final.tombstone.expected() -> List<&1, ByteMemTable.Entry>:
  [ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("")),
      Some{bytes.fixture(Bytes.from_hex("05"))}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("00")), None{}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("0000")),
      Some{bytes.fixture(Bytes.from_hex("04"))}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("ff")), None{}}]

# A byte put contributes one mutation regardless of key or value encoding.
law put_increments_count:
  for key: Bytes.Bytes
  for value: Bytes.Bytes
  {ByteMemTable.count(ByteMemTable.put(ByteMemTable.empty(), key, value)) == 1n : Nat}

# A tombstone contributes one mutation to the byte log.
law delete_increments_count:
  for key: Bytes.Bytes
  {ByteMemTable.count(ByteMemTable.del(ByteMemTable.empty(), key)) == 1n : Nat}

# Payload accounting uses stored byte lengths, including the empty key.
law payload_counts_exact_bytes:
  {ByteMemTable.payload_bytes(ByteMemTable.put(ByteMemTable.empty(),
    bytes.fixture(Bytes.from_hex("")),
    bytes.fixture(Bytes.from_hex("80ff00")))) == 3n : Nat}

# The budget walk preserves every table mutation.
law retention_preflight_preserves_entry_count:
  {retention.count(ByteMemTable.retained_bytes.keep(reverse_order.fixture())) == 2n : Nat}

# The budget walk preserves exact encoded key/value payload size.
law retention_preflight_preserves_payload_bytes:
  {retention.payload(ByteMemTable.retained_bytes.keep(reverse_order.fixture())) == 4n : Nat}

# The budget walk includes the fixed metadata estimate for each entry.
law retention_preflight_measures_entry_overhead:
  {retention.measurement(ByteMemTable.retained_bytes.keep(reverse_order.fixture())) == 68n : Nat}

# The canonical materializer orders a closed vector with high and low bytes.
law reverse_insertions_materialize_in_byte_order:
  {ByteMemTable.ordered.strict(ByteMemTable.ordered_entries(reverse_order.fixture())) == True{} : Bool}

# Materialization retains the newest value when one key is mutated twice.
law materialization_keeps_newest_duplicate_value:
  {ordered.replacement.visible(ByteMemTable.get(ordered.replacement.materialized(),
    bytes.fixture(Bytes.from_hex("62")))) == True{} : Bool}

# Materialization orders binary keys and keeps the newest value or tombstone.
law materialization_matches_binary_overwrite_and_tombstone_order:
  {ByteMemTable.ordered_entries(ordered.canonical.fixture()) ==
    ordered.canonical.expected() : List<&1, ByteMemTable.Entry>}

# Materialization keeps the newest deletion for a key.
law materialization_keeps_newest_final_tombstone:
  {ByteMemTable.ordered_entries(ordered.final.tombstone.fixture()) ==
    ordered.final.tombstone.expected() : List<&1, ByteMemTable.Entry>}

# Equal keys prefer the newer run during ordered merging.
law ordered_merge_takes_newer_for_non_greater_comparison:
  for order: Cmp
  {ByteMemTable.ordered.merge.take_newer(order) ==
    Bool.or(Cmp.is_lt(order), Cmp.is_eq(order)) : Bool}

# Presence inspection preserves the entry and reports whether it is live.
law entry_live_keep_matches_open_presence:
  for entry: ByteMemTable.Entry
  {ByteMemTable.entry.live.matches(ByteMemTable.entry.live.keep(entry)) == True{} : Bool}

# A one-run compaction keeps live values and removes tombstones.
law compaction_drops_tombstones:
  {List.length(&1, ByteMemTable.Entry, ByteMemTable.compact.live(
    ByteMemTable.ordered_entries(ByteMemTable.del(
      ByteMemTable.put(ByteMemTable.empty(), bytes.fixture(Bytes.from_hex("62")),
        bytes.fixture(Bytes.from_hex("76616c7565"))),
      bytes.fixture(Bytes.from_hex("61")))))) == 1n : Nat}

# The probe marks an explicit tombstone as a mutation.
law probe_distinguishes_tombstone:
  {probe.deleted(ByteMemTable.probe(ByteMemTable.del(ByteMemTable.empty(),
    bytes.fixture(Bytes.from_hex("61"))), bytes.fixture(Bytes.from_hex("61")))) == True{} : Bool}

# The probe leaves an untouched key absent from the delta.
law probe_distinguishes_absence:
  {probe.absent(ByteMemTable.probe(ByteMemTable.del(ByteMemTable.empty(),
    bytes.fixture(Bytes.from_hex("61"))), bytes.fixture(Bytes.from_hex("62")))) == True{} : Bool}

# The probe returns an explicit live value for a mutation.
law probe_finds_live_value:
  {probe.value(ByteMemTable.probe(ByteMemTable.put(ByteMemTable.empty(),
    bytes.fixture(Bytes.from_hex("61")), bytes.fixture(Bytes.from_hex("80"))),
    bytes.fixture(Bytes.from_hex("61")))) == True{} : Bool}

# Identical neighboring keys are rejected by the strict export-order check.
law strict_order_rejects_duplicate_keys:
  {ByteMemTable.ordered.strict([ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("61")),
    Some{bytes.fixture(Bytes.from_hex("31"))}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("61")),
      Some{bytes.fixture(Bytes.from_hex("32"))}}]) == False{} : Bool}

# Descending neighboring keys are rejected before backup or restore publication.
law strict_order_rejects_descending_keys:
  {ByteMemTable.ordered.strict([ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("62")),
    Some{bytes.fixture(Bytes.from_hex("31"))}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("61")),
      Some{bytes.fixture(Bytes.from_hex("32"))}}]) == False{} : Bool}

# A prefix followed by its extension is a valid strict byte order.
law strict_order_accepts_prefix_extension:
  {ByteMemTable.ordered.strict([ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("61")),
    Some{bytes.fixture(Bytes.from_hex("31"))}},
    ByteMemTable.Entry{bytes.fixture(Bytes.from_hex("6100")),
      Some{bytes.fixture(Bytes.from_hex("32"))}}]) == True{} : Bool}
