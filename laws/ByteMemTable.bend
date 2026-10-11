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
