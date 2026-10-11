import Base
import ./ByteWal.bend as ByteWal
import ./StorageBytes.bend as StorageBytes
import ./Wal.bend as Wal
import ./coordinator/QueuePolicy.bend as QueuePolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries the owned input and accumulated exact batch size through the fold.
type ByteBatchMeasureState is Type:
  MeasureNeed{mutations: List<&1, ByteWal.Mutation>,
    reversed: List<&1, ByteWal.Mutation>, count: Nat, record_bytes: Nat}

# Returns a measured list or rejects input exceeding the mutation-count bound.
type ByteBatchMeasurement is Type:
  BatchMeasured{mutations: List<&1, ByteWal.Mutation>, count: Nat,
    encoded_bytes: Nat}
  BatchTooMany{}

# Returns the count-limit decision for a mutation batch.
type Validation is Data:
  ValidBatch{}
  EmptyBatch{}
  BatchCountExceeded{}
  BatchBytesExceeded{}

# Returns the maximum number of mutations in a batch.
def max_batch_count() -> Nat:
  256n

# Caps an encoded multi-mutation WAL frame at the normal block size.
def max_batch_bytes() -> Nat:
  U32.to_nat(StorageBytes.MAX_BLOCK_BYTES())

# Retains the codec's one-record exception to the normal frame limit.
def max_single_batch_bytes() -> Nat:
  Nat.add(U32.to_nat(StorageBytes.MAX_RECORD_BYTES()), 36n)

# Selects the encoded-frame ceiling for a single record or mutation batch.
def frame_byte_limit(
  count: Nat,
  batch_limit: Nat,
  single_limit: Nat
) -> Nat:
  Bool.pick(Nat, Nat.is_eq(count, 1n), single_limit, batch_limit)

# Counts one encoded Put record's tag, length fields, key, and value.
def put_record_bytes(key_bytes: Nat, value_bytes: Nat) -> Nat:
  Nat.add(9n, Nat.add(key_bytes, value_bytes))

# Counts one encoded Delete record's tag, length field, and key.
def delete_record_bytes(key_bytes: Nat) -> Nat:
  Nat.add(5n, key_bytes)

# Decides whether one encoded frame is within its selected byte ceiling.
def validate_frame_bytes(
  count: Nat,
  encoded_bytes: Nat,
  batch_limit: Nat,
  single_limit: Nat
) -> Validation:
  Bool.pick(Validation,
    Nat.is_le(encoded_bytes, frame_byte_limit(count, batch_limit, single_limit)),
    ValidBatch{}, BatchBytesExceeded{})

# Counts the exact encoded size of one UTF-8 WAL mutation record.
def utf8_mutation_bytes(mutation: Wal.Mut) -> Nat:
  match mutation:
    case Wal.Put{key, value}:
      put_record_bytes(StorageBytes.string_size(key),
        StorageBytes.string_size(value))
    case Wal.Del{key}:
      delete_record_bytes(StorageBytes.string_size(key))

# Sums encoded UTF-8 record lengths without constructing a WAL frame.
def utf8_records_bytes(mutations: List<&2, Wal.Mut>) -> Nat:
  match mutations:
    case Nil{}: 0n
    case Con{mutation, tail}:
      Nat.add(utf8_mutation_bytes(mutation), utf8_records_bytes(tail))

# Adds the fixed generation-four WAL frame header and checksum size.
def frame_bytes(record_bytes: Nat) -> Nat:
  Nat.add(36n, record_bytes)

# Advances a bounded no-copy byte-batch size pass.
def byte_batch.measure.loop(
  fuel: Nat,
  state: ByteBatchMeasureState
) -> ByteBatchMeasurement:
  match fuel:
    case 0n:
      match state:
        case MeasureNeed{Nil{}, reversed, count, record_bytes}:
          BatchMeasured{List.reverse(&1, ByteWal.Mutation, reversed), count,
            frame_bytes(record_bytes)}
        case MeasureNeed{Con{_, _}, _, _, _}: BatchTooMany{}
    case 1n+rest:
      match state:
        case MeasureNeed{Nil{}, reversed, count, record_bytes}:
          BatchMeasured{List.reverse(&1, ByteWal.Mutation, reversed), count,
            frame_bytes(record_bytes)}
        case MeasureNeed{Con{ByteWal.Delete{key}, tail}, reversed, count,
            record_bytes}:
          match key:
            case Bytes.Bytes{+key_len, key_buffer}:
              byte_batch.measure.loop(rest, MeasureNeed{tail,
                Con{ByteWal.Delete{Bytes.Bytes{key_len, key_buffer}}, reversed},
                Nat.add(count, 1n),
                Nat.add(record_bytes,
                  delete_record_bytes(U32.to_nat(key_len)))})
        case MeasureNeed{Con{ByteWal.Put{key, value}, tail}, reversed, count,
            record_bytes}:
          match key:
            case Bytes.Bytes{+key_len, key_buffer}:
              match value:
                case Bytes.Bytes{+value_len, value_buffer}:
                  byte_batch.measure.loop(rest, MeasureNeed{tail,
                    Con{ByteWal.Put{Bytes.Bytes{key_len, key_buffer},
                      Bytes.Bytes{value_len, value_buffer}}, reversed},
                    Nat.add(count, 1n), Nat.add(record_bytes,
                      put_record_bytes(U32.to_nat(key_len),
                        U32.to_nat(value_len)))})

# Measures a byte batch without copying buffers or building its WAL frame.
def byte_batch.measure(
  mutations: List<&1, ByteWal.Mutation>
) -> ByteBatchMeasurement:
  byte_batch.measure.loop(max_batch_count(),
    MeasureNeed{mutations, Nil{}, 0n, 0n})

# Counts a UTF-8 batch's exact serialized frame size before allocation.
def utf8_batch_bytes(mutations: List<&2, Wal.Mut>) -> Nat:
  frame_bytes(utf8_records_bytes(mutations))

# Checks whether a batch count is within the allowed range.
def within_batch_count(count: Nat) -> Bool:
  Nat.is_le(count, max_batch_count())

# Rejects empty and oversized batches before writing.
def validate_count(count: Nat) -> Validation:
  match count:
    case 0n:
      EmptyBatch{}
    case count:
      Bool.pick(Validation, within_batch_count(count), ValidBatch{}, BatchCountExceeded{})

# Applies the byte limit only after the mutation count is accepted.
def validate_batch.counted(
  count: Nat,
  encoded_bytes: Nat,
  count_validation: Validation
) -> Validation:
  match count_validation:
    case ValidBatch{}:
      validate_frame_bytes(count, encoded_bytes, max_batch_bytes(),
        max_single_batch_bytes())
    case EmptyBatch{}: EmptyBatch{}
    case BatchCountExceeded{}: BatchCountExceeded{}
    case BatchBytesExceeded{}: BatchBytesExceeded{}

# Rejects a batch before storage access if its count or frame bytes exceed limits.
def validate_batch.copies(
  counts: Nat & Nat,
  encoded_bytes: Nat
) -> Validation:
  match counts:
    case (for_frame_limit, for_count_validation):
      validate_batch.counted(for_frame_limit, encoded_bytes,
        validate_count(for_count_validation))

# Rejects a batch before storage access if its count or frame bytes exceed limits.
def validate_batch(count: Nat, encoded_bytes: Nat) -> Validation:
  validate_batch.copies(QueuePolicy.nat.clone.pair(count), encoded_bytes)
