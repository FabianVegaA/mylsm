import Base
import ./Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Affine byte key and value pair stored newest-first.
type Entry is Type:
  Entry{key: Bytes.Bytes, val: Maybe<&1, Bytes.Bytes>}

# Owns the complete newest-first mutation log.
type Table is Type:
  Table{entries: List<&1, Entry>}

# Carries rebuilt table ownership alongside an optional cloned value.
type Lookup is Type:
  Lookup{entries: List<&1, Entry>, value: Maybe<&1, Bytes.Bytes>, found: Bool}

# Distinguishes no delta mutation, a tombstone, and a live delta value.
type Probe is Type:
  Absent{}
  Deleted{}
  Present{value: Bytes.Bytes}

# Carries affine search state across lexicographic comparisons.
type Search is Type:
  Search{query: Bytes.Bytes, entries: List<&1, Entry>, prefix: List<&1, Entry>, order: Cmp}

# Carries the pending entry through a unique-key insertion into sorted entries.
type OrderedSearch is Type:
  OrderedSearch{pending: Entry, entries: List<&1, Entry>, prefix: List<&1, Entry>, order: Cmp}

# Creates a byte table with no mutations.
def empty() -> Table:
  Table{Nil{}}

# Prepends a byte value mutation without decoding either buffer.
def put(table: Table, key: Bytes.Bytes, value: Bytes.Bytes) -> Table:
  match table:
    case Table{entries}:
      Table{Con{Entry{key, Some{value}}, entries}}

# Prepends a tombstone for an arbitrary byte key.
def del(table: Table, key: Bytes.Bytes) -> Table:
  match table:
    case Table{entries}:
      Table{Con{Entry{key, None{}}, entries}}

# Counts each owned mutation in a byte table.
def count.go(entries: List<&1, Entry>, total: Nat) -> Nat:
  match entries:
    case Nil{}:
      total
    case Con{_, tail}:
      count.go(tail, Nat.add(total, 1n))

# Returns the number of mutations, including tombstones.
def count(table: Table) -> Nat:
  match table:
    case Table{entries}:
      count.go(entries, 0n)

# Counts entries while preserving the list for a subsequent lookup.
def count.keep.go(
  entries: List<&1, Entry>,
  reversed: List<&1, Entry>,
  total: Nat
) -> List<&1, Entry> & Nat:
  match entries:
    case Nil{}:
      (List.reverse(&1, Entry, reversed), total)
    case Con{entry, tail}:
      count.keep.go(tail, Con{entry, reversed}, Nat.add(total, 1n))

# Returns both the original entry order and its size.
def count.keep(entries: List<&1, Entry>) -> List<&1, Entry> & Nat:
  count.keep.go(entries, Nil{}, 0n)

# Reifies the two independently owned buffers returned by the copy effect.
def bytes.clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

# Duplicates a byte buffer only when ownership must be retained by the table.
def bytes.clone(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      bytes.clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

# Wraps the original and copied buffers as independent optional values.
def value.clone.pair(pair: Bytes.Bytes & Bytes.Bytes) -> Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>:
  match pair:
    case (original, copy):
      (Some{original}, Some{copy})

# Clones only a present value while preserving absence.
def value.clone(value: Maybe<&1, Bytes.Bytes>) -> Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>:
  match value:
    case None{}:
      (None{}, None{})
    case Some{bytes}:
      value.clone.pair(bytes.clone(bytes))

# Rebuilds two independently owned entries from cloned fields.
def entry.clone.fields(
  keys: Bytes.Bytes & Bytes.Bytes,
  values: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>
) -> Entry & Entry:
  match keys:
    case (left_key, right_key):
      match values:
        case (left_value, right_value):
          (Entry{left_key, left_value}, Entry{right_key, right_value})

# Clones both buffers and the optional value in one entry.
def entry.clone(entry: Entry) -> Entry & Entry:
  match entry:
    case Entry{key, val}:
      entry.clone.fields(bytes.clone(key), value.clone(val))

# Prepends cloned heads to the corresponding entry lists.
def entries.clone.push(
  head: Entry & Entry,
  tail: List<&1, Entry> & List<&1, Entry>
) -> List<&1, Entry> & List<&1, Entry>:
  match head:
    case (left, right):
      match tail:
        case (left_tail, right_tail):
          (Con{left, left_tail}, Con{right, right_tail})

# Clones an affine entry list while preserving its order.
def entries.clone(entries: List<&1, Entry>) -> List<&1, Entry> & List<&1, Entry>:
  match entries:
    case Nil{}: (Nil{}, Nil{})
    case Con{entry, tail}:
      entries.clone.push(entry.clone(entry), entries.clone(tail))

# Appends the remaining search suffix after the reversed visited prefix.
def append(left: List<&1, Entry>, right: List<&1, Entry>) -> List<&1, Entry>:
  match left:
    case Nil{}:
      right
    case Con{head, tail}:
      Con{head, append(tail, right)}

# Rebuilds table order and returns the optional visible value.
def lookup.result(
  prefix: List<&1, Entry>,
  remaining: List<&1, Entry>,
  value: Maybe<&1, Bytes.Bytes>,
  found: Bool
) -> Lookup:
  Lookup{append(List.reverse(&1, Entry, prefix), remaining), value, found}

# Restores a found entry and preserves its value for the caller.
def lookup.hit(
  prefix: List<&1, Entry>,
  key: Bytes.Bytes,
  tail: List<&1, Entry>,
  copies: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>
) -> Lookup:
  match copies:
    case (original, visible):
      lookup.result(prefix, Con{Entry{key, original}, tail}, visible, True{})

# Clones a found value so the table remains readable after the lookup.
def lookup.hit.value(
  value: Maybe<&1, Bytes.Bytes>,
  prefix: List<&1, Entry>,
  key: Bytes.Bytes,
  tail: List<&1, Entry>
) -> Lookup:
  match value:
    case None{}:
      lookup.result(prefix, Con{Entry{key, None{}}, tail}, None{}, True{})
    case Some{bytes}:
      lookup.hit(prefix, key, tail, value.clone(Some{bytes}))

# Associates comparison output with the entry that produced it.
def lookup.state(
  prefix: List<&1, Entry>,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, Entry>,
  comparison: Bytes.Bytes & Bytes.Bytes & Cmp
) -> Search:
  match comparison:
    case (key, query, order):
      Search{query, Con{Entry{key, value}, tail}, prefix, order}

# Advances the affine scan while retaining the prior entry in its prefix.
def lookup.advance.state(
  query: Bytes.Bytes,
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, Entry>,
  prefix: List<&1, Entry>
) -> Search:
  match tail:
    case Nil{}:
      Search{query, Nil{}, Con{Entry{key, value}, prefix}, EQ{}}
    case Con{Entry{next_key, next_value}, rest}:
      lookup.state(Con{Entry{key, value}, prefix}, next_value, rest,
        Keys.Bytes.cmp.with_inputs(next_key, query))

# Searches newest-first entries under a structural recursion bound.
def lookup.go(fuel: Nat, state: Search) -> Lookup:
  match fuel:
    case 0n:
      match state:
        case Search{_, entries, prefix, _}:
          lookup.result(prefix, entries, None{}, False{})
    case 1n+rest:
      match state:
        case Search{query, entries, prefix, order}:
          match entries:
            case Nil{}:
              lookup.result(prefix, Nil{}, None{}, False{})
            case Con{Entry{key, val}, tail}:
              match order:
                case EQ{}:
                  lookup.hit.value(val, prefix, key, tail)
                case LT{}:
                  lookup.go(rest, lookup.advance.state(query, key, val, tail, prefix))
                case GT{}:
                  lookup.go(rest, lookup.advance.state(query, key, val, tail, prefix))

# Restores the table and surfaces the optional lookup value.
def lookup.start.table(result: Lookup) -> Table & Maybe<&1, Bytes.Bytes>:
  match result:
    case Lookup{entries, value, _}:
      (Table{entries}, value)

def lookup.start.probe.value(table: Table, value: Maybe<&1, Bytes.Bytes>, found: Bool) -> Table & Probe:
  match value:
    case None{}:
      match found:
        case False{}: (table, Absent{})
        case True{}: (table, Deleted{})
    case Some{bytes}:
      match found:
        case False{}: (table, Absent{})
        case True{}: (table, Present{bytes})

def lookup.start.probe(result: Lookup) -> Table & Probe:
  match result:
    case Lookup{entries, value, found}:
      lookup.start.probe.value(Table{entries}, value, found)

def lookup.start.counted.lookup(
  query: Bytes.Bytes,
  entries: List<&1, Entry>,
  count: Nat
) -> Lookup:
  match entries:
    case Nil{}: Lookup{Nil{}, None{}, False{}}
    case Con{Entry{key, val}, tail}:
      lookup.go(Nat.add(count, 1n),
        lookup.state(Nil{}, val, tail, Keys.Bytes.cmp.with_inputs(key, query)))

# Starts a lookup with a bound computed from the list length.
def lookup.start.counted(
  query: Bytes.Bytes,
  entries: List<&1, Entry>,
  count: Nat
) -> Table & Maybe<&1, Bytes.Bytes>:
  lookup.start.table(lookup.start.counted.lookup(query, entries, count))

def lookup.start.counted.probe(
  query: Bytes.Bytes,
  entries: List<&1, Entry>,
  count: Nat
) -> Table & Probe:
  lookup.start.probe(lookup.start.counted.lookup(query, entries, count))

# Unpacks the preserved list and count before scanning.
def lookup.start.counted.pair(query: Bytes.Bytes, counted: List<&1, Entry> & Nat) -> Table & Maybe<&1, Bytes.Bytes>:
  match counted:
    case (entries, count):
      lookup.start.counted(query, entries, count)

# Counts and scans a table while preserving its ownership.
def lookup.start(query: Bytes.Bytes, entries: List<&1, Entry>) -> Table & Maybe<&1, Bytes.Bytes>:
  lookup.start.counted.pair(query, count.keep(entries))

def lookup.start.probe.pair(
  query: Bytes.Bytes,
  counted: List<&1, Entry> & Nat
) -> Table & Probe:
  match counted:
    case (entries, count): lookup.start.counted.probe(query, entries, count)

# Looks up a key while preserving whether the newest delta mutation exists.
def probe(table: Table, query: Bytes.Bytes) -> Table & Probe:
  match table:
    case Table{entries}:
      lookup.start.probe.pair(query, count.keep(entries))

# Reads a byte key and returns the still-owned table with the result.
def get(table: Table, query: Bytes.Bytes) -> Table & Maybe<&1, Bytes.Bytes>:
  match table:
    case Table{entries}:
      lookup.start(query, entries)

# Measures a value by its exact encoded byte length.
def payload.value(value: Maybe<&1, Bytes.Bytes>) -> Nat:
  match value:
    case None{}:
      0n
    case Some{Bytes.Bytes{+len, _}}:
      U32.to_nat(len)

# Sums key and present-value byte lengths over the mutation log.
def payload.go(entries: List<&1, Entry>, total: Nat) -> Nat:
  match entries:
    case Nil{}:
      total
    case Con{Entry{Bytes.Bytes{+len, _}, val}, tail}:
      payload.go(tail, Nat.add(Nat.add(total, U32.to_nat(len)), payload.value(val)))

# Returns exact key/value payload bytes, excluding structural overhead.
def payload_bytes(table: Table) -> Nat:
  match table:
    case Table{entries}:
      payload.go(entries, 0n)

# Adds a fixed per-entry estimate to encoded payload bytes for retention limits.
def retained.go(entries: List<&1, Entry>, total: Nat) -> Nat:
  match entries:
    case Nil{}: total
    case Con{Entry{Bytes.Bytes{+len, _}, val}, tail}:
      retained.go(tail,
        Nat.add(Nat.add(Nat.add(total, 32n), U32.to_nat(len)), payload.value(val)))

# Estimates packed payload and entry metadata retained by a snapshot copy.
def retained_bytes(table: Table) -> Nat:
  match table:
    case Table{entries}:
      retained.go(entries, 0n)

def retained.value(value: Maybe<&1, Bytes.Bytes>) -> Maybe<&1, Bytes.Bytes> & Nat:
  match value:
    case None{}: (None{}, 0n)
    case Some{Bytes.Bytes{+len, buffer}}:
      (Some{Bytes.Bytes{len, buffer}}, U32.to_nat(len))

def retained_bytes.keep.go(
  entries: List<&1, Entry>,
  reversed: List<&1, Entry>,
  total: Nat
) -> List<&1, Entry> & Nat:
  match entries:
    case Nil{}:
      (List.reverse(&1, Entry, reversed), total)
    case Con{Entry{key, value}, tail}:
      match key:
        case Bytes.Bytes{+key_len, key_buffer}:
          match value:
            case None{}:
              retained_bytes.keep.go(tail,
                Con{Entry{Bytes.Bytes{key_len, key_buffer}, None{}}, reversed},
                Nat.add(total, Nat.add(32n, U32.to_nat(key_len))))
            case Some{Bytes.Bytes{+value_len, value_buffer}}:
              retained_bytes.keep.go(tail,
                Con{Entry{Bytes.Bytes{key_len, key_buffer},
                  Some{Bytes.Bytes{value_len, value_buffer}}}, reversed},
                Nat.add(total, Nat.add(Nat.add(32n, U32.to_nat(key_len)),
                  U32.to_nat(value_len))))

def retained_bytes.keep.finish(pair: List<&1, Entry> & Nat) -> Table & Nat:
  match pair:
    case (entries, bytes): (Table{entries}, bytes)

def retained_bytes.keep(table: Table) -> Table & Nat:
  match table:
    case Table{entries}:
      retained_bytes.keep.finish(retained_bytes.keep.go(entries, Nil{}, 0n))

# Restores a sorted list after reaching the end or insertion point.
def ordered.finish(
  prefix: List<&1, Entry>,
  entries: List<&1, Entry>,
  pending: Maybe<&1, Entry>
) -> List<&1, Entry>:
  match pending:
    case None{}:
      append(List.reverse(&1, Entry, prefix), entries)
    case Some{entry}:
      append(List.reverse(&1, Entry, prefix), Con{entry, entries})

# Rebuilds the search state with comparator-owned keys restored to entries.
def ordered.state(
  pending_value: Maybe<&1, Bytes.Bytes>,
  head_value: Maybe<&1, Bytes.Bytes>,
  tail: List<&1, Entry>,
  prefix: List<&1, Entry>,
  comparison: Bytes.Bytes & Bytes.Bytes & Cmp
) -> OrderedSearch:
  match comparison:
    case (head_key, query_key, order):
      OrderedSearch{Entry{query_key, pending_value},
        Con{Entry{head_key, head_value}, tail}, prefix, order}

# Compares the current sorted key with the pending key without losing buffers.
def ordered.compare(
  pending: Entry,
  head: Entry,
  tail: List<&1, Entry>,
  prefix: List<&1, Entry>
) -> OrderedSearch:
  match pending head:
    case Entry{query_key, pending_value} Entry{head_key, head_value}:
      ordered.state(pending_value, head_value, tail, prefix,
        Keys.Bytes.cmp.with_inputs(head_key, query_key))

# Begins comparison at the next sorted key after a smaller one was visited.
def ordered.first(
  pending: Entry,
  entries: List<&1, Entry>,
  prefix: List<&1, Entry>
) -> OrderedSearch:
  match entries:
    case Nil{}:
      OrderedSearch{pending, Nil{}, prefix, EQ{}}
    case Con{head, tail}:
      ordered.compare(pending, head, tail, prefix)

# Inserts one entry into a sorted unique list; an existing key wins.
def ordered.insert.go(fuel: Nat, state: OrderedSearch) -> List<&1, Entry>:
  match fuel:
    case 0n:
      match state:
        case OrderedSearch{pending, entries, prefix, _}:
          ordered.finish(prefix, entries, Some{pending})
    case 1n+rest:
      match state:
        case OrderedSearch{pending, entries, prefix, order}:
          match entries:
            case Nil{}:
              ordered.finish(prefix, Nil{}, Some{pending})
            case Con{head, tail}:
              match order:
                case LT{}:
                  ordered.insert.go(rest, ordered.first(pending, tail, Con{head, prefix}))
                case EQ{}:
                  ordered.finish(prefix, Con{head, tail}, None{})
                case GT{}:
                  ordered.finish(prefix, Con{head, tail}, Some{pending})

# Starts a bounded insertion using the sorted list length as fuel.
def ordered.insert.counted(
  pending: Entry,
  entries: List<&1, Entry>,
  count: Nat
) -> List<&1, Entry>:
  match entries:
    case Nil{}:
      Con{pending, Nil{}}
    case Con{head, tail}:
      ordered.insert.go(Nat.add(count, 1n), ordered.compare(pending, head, tail, Nil{}))

# Unpacks the sorted list and its preserved length before insertion.
def ordered.insert.measured(
  pending: Entry,
  measured: List<&1, Entry> & Nat
) -> List<&1, Entry>:
  match measured:
    case (entries, count):
      ordered.insert.counted(pending, entries, count)

# Inserts an entry while preserving the list needed by the length bound.
def ordered.insert(pending: Entry, entries: List<&1, Entry>) -> List<&1, Entry>:
  ordered.insert.measured(pending, count.keep(entries))

# Collapses newest-first mutations into sorted unique keys, retaining tombstones.
def ordered.fold.go(
  fuel: Nat,
  mutations: List<&1, Entry>,
  entries: List<&1, Entry>
) -> List<&1, Entry>:
  match fuel:
    case 0n:
      entries
    case 1n+rest:
      match mutations:
        case Nil{}:
          entries
        case Con{mutation, tail}:
          ordered.fold.go(rest, tail, ordered.insert(mutation, entries))

# Unpacks the mutation log and its bounded fold count.
def ordered.fold.measured(
  mutations: List<&1, Entry> & Nat
) -> List<&1, Entry>:
  match mutations:
    case (entries, count):
      ordered.fold.go(Nat.add(count, 1n), entries, Nil{})

# Produces strict byte-ordered unique entries with newest mutations winning.
def ordered_entries(table: Table) -> List<&1, Entry>:
  match table:
    case Table{entries}:
      ordered.fold.measured(count.keep(entries))

# Drops tombstones after all older byte runs have been folded into one table.
def compact.live(entries: List<&1, Entry>) -> List<&1, Entry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Entry{_, None{}}, tail}:
      compact.live(tail)
    case Con{Entry{key, Some{value}}, tail}:
      Con{Entry{key, Some{value}}, compact.live(tail)}

# Accepts only a strict ascending comparison for neighboring ordered keys.
def ordered.strict.order(comparison: Bytes.Bytes & Bytes.Bytes & Cmp) -> Bool:
  match comparison:
    case (_, _, LT{}):
      True{}
    case _:
      False{}

# Checks strict key order with fuel derived from the number of entries.
def ordered.strict.go(fuel: Nat, entries: List<&1, Entry>) -> Bool:
  match fuel:
    case 0n:
      True{}
    case 1n+rest:
      match entries:
        case Nil{}:
          True{}
        case Con{_, Nil{}}:
          True{}
        case Con{Entry{first, _}, Con{Entry{second, _}, tail}}:
          +tail_valid = ordered.strict.go(rest, tail)
          Bool.and(ordered.strict.order(Keys.Bytes.cmp.with_inputs(first, second)), tail_valid)

# Unpacks an ordered list and its preserved recursion bound.
def ordered.strict.counted(measured: List<&1, Entry> & Nat) -> Bool:
  match measured:
    case (entries, count):
      ordered.strict.go(Nat.add(count, 1n), entries)

# Checks that a sorted entry list is strictly increasing by byte key.
def ordered.strict(entries: List<&1, Entry>) -> Bool:
  ordered.strict.counted(count.keep(entries))
