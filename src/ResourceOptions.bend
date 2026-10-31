import Base

# Carries the state for TransportLimits.
type TransportLimits is Data:
  TransportLimits{connections: U32, frame_bytes: U32,
    receive_bytes: U32, response_bytes: U32,
    frame_timeout_ms: U32, response_timeout_ms: U32}

# Carries the state for QueueLimits.
type QueueLimits is Data:
  QueueLimits{requests: U32, bytes: U32, timeout_ms: U32}

# Carries the state for ReaderLimits.
type ReaderLimits is Data:
  ReaderLimits{snapshots: U32, cursors: U32,
    cursors_per_snapshot: U32, retained_root_bytes: U32,
    retired_files: U32, index_page_bytes: U32,
    index_buffer_bytes: U32, restore_bytes: U32}

# Carries the state for Options.
type Options is Data:
  Options{transport: TransportLimits, queue: QueueLimits,
    readers: ReaderLimits}

# Carries the state for Decision.
type Decision is Data:
  Accepted{options: Options}
  InvalidTransport{}
  InvalidQueue{}
  InvalidReaders{}

# Handles defaults.
def defaults() -> Options:
  Options{
    TransportLimits{64, 16777216, 16777216, 16777216,
      30000, 30000},
    QueueLimits{64, 16777216, 30000},
    ReaderLimits{64, 4096, 64, 67108864, 64,
      16384, 65536, 67108864}}

def fields.transport(
  transport: TransportLimits,
  tail: List<&2, U32>
) -> List<&2, U32>:
  match transport:
    case TransportLimits{connections, frame_bytes, receive_bytes,
      response_bytes, frame_timeout_ms, response_timeout_ms}:
      Con{connections, Con{frame_bytes, Con{receive_bytes,
        Con{response_bytes, Con{frame_timeout_ms,
          Con{response_timeout_ms, tail}}}}}}

def fields.queue(
  queue: QueueLimits,
  tail: List<&2, U32>
) -> List<&2, U32>:
  match queue:
    case QueueLimits{requests, bytes, timeout_ms}:
      Con{requests, Con{bytes, Con{timeout_ms, tail}}}

def fields.readers(
  readers: ReaderLimits,
  tail: List<&2, U32>
) -> List<&2, U32>:
  match readers:
    case ReaderLimits{snapshots, cursors, cursors_per_snapshot,
      retained_root_bytes, retired_files, index_page_bytes,
      index_buffer_bytes, restore_bytes}:
      Con{snapshots, Con{cursors, Con{cursors_per_snapshot,
        Con{retained_root_bytes, Con{retired_files,
          Con{index_page_bytes, Con{index_buffer_bytes,
            Con{restore_bytes, tail}}}}}}}}

def fields.value(options: Options) -> List<&2, U32>:
  match options:
    case Options{transport, queue, readers}:
      fields.transport(transport, fields.queue(queue,
        fields.readers(readers, Nil{})))

# Handles fields.
def fields(+options: Options) -> List<&2, U32>:
  fields.value(options)

def fields.same(
  left: List<&2, U32>,
  right: List<&2, U32>
) -> Bool:
  match left right:
    case Con{l1, Con{l2, Con{l3, Con{l4, Con{l5, Con{l6,
      Con{l7, Con{l8, Con{l9, Con{l10, Con{l11, Con{l12,
        Con{l13, Con{l14, Con{l15, Con{l16, Con{l17, Nil{}}}}}}}}}}}}}}}}}}
      Con{r1, Con{r2, Con{r3, Con{r4, Con{r5, Con{r6,
        Con{r7, Con{r8, Con{r9, Con{r10, Con{r11, Con{r12,
          Con{r13, Con{r14, Con{r15, Con{r16, Con{r17, Nil{}}}}}}}}}}}}}}}}}}:
      Bool.and(U32.is_eq(l1, r1), Bool.and(U32.is_eq(l2, r2),
        Bool.and(U32.is_eq(l3, r3), Bool.and(U32.is_eq(l4, r4),
          Bool.and(U32.is_eq(l5, r5), Bool.and(U32.is_eq(l6, r6),
            Bool.and(U32.is_eq(l7, r7), Bool.and(U32.is_eq(l8, r8),
              Bool.and(U32.is_eq(l9, r9), Bool.and(U32.is_eq(l10, r10),
                Bool.and(U32.is_eq(l11, r11), Bool.and(U32.is_eq(l12, r12),
                  Bool.and(U32.is_eq(l13, r13),
                    Bool.and(U32.is_eq(l14, r14),
                      Bool.and(U32.is_eq(l15, r15),
                        Bool.and(U32.is_eq(l16, r16),
                          U32.is_eq(l17, r17)))))))))))))))))
    case _ _: False{}

# Handles same.
def same(+left: Options, +right: Options) -> Bool:
  fields.same(fields(left), fields(right))

def snapshot.limits(options: Options) -> U32 & U32:
  match options:
    case Options{_, _, ReaderLimits{snapshots, _, _, retained_root_bytes, _, _, _, _}}:
      (snapshots, retained_root_bytes)

def snapshot.retained.bytes(options: Options) -> U32:
  match options:
    case Options{_, _, ReaderLimits{_, _, _, retained_root_bytes, _, _, _, _}}:
      retained_root_bytes

def snapshot.count(options: Options) -> U32:
  match options:
    case Options{_, _, ReaderLimits{snapshots, _, _, _, _, _, _, _}}:
      snapshots

def cursor.per.snapshot(options: Options) -> U32:
  match options:
    case Options{_, _, ReaderLimits{_, _, cursors_per_snapshot, _, _, _, _, _}}:
      cursors_per_snapshot

def cursor.count(options: Options) -> U32:
  match options:
    case Options{_, _, ReaderLimits{_, cursors, _, _, _, _, _, _}}:
      cursors

def transport.frame.bytes(options: Options) -> U32:
  match options:
    case Options{TransportLimits{_, frame_bytes, _, _, _, _}, _, _}:
      frame_bytes

def transport.receive.bytes(options: Options) -> U32:
  match options:
    case Options{TransportLimits{_, _, receive_bytes, _, _, _}, _, _}:
      receive_bytes

def transport.connections(options: Options) -> U32:
  match options:
    case Options{TransportLimits{connections, _, _, _, _, _}, _, _}:
      connections

def transport.frame.timeout(options: Options) -> U32:
  match options:
    case Options{TransportLimits{_, _, _, _, frame_timeout_ms, _}, _, _}:
      frame_timeout_ms

def transport.response.timeout(options: Options) -> U32:
  match options:
    case Options{TransportLimits{_, _, _, _, _, response_timeout_ms}, _, _}:
      response_timeout_ms

def queue.timeout(options: Options) -> U32:
  match options:
    case Options{_, QueueLimits{_, _, timeout_ms}, _}:
      timeout_ms

def queue.requests(options: Options) -> U32:
  match options:
    case Options{_, QueueLimits{requests, _, _}, _}:
      requests

def queue.bytes(options: Options) -> U32:
  match options:
    case Options{_, QueueLimits{_, bytes, _}, _}:
      bytes

def transport.response.bytes(options: Options) -> U32:
  match options:
    case Options{TransportLimits{_, _, _, response_bytes, _, _}, _, _}:
      response_bytes

def response.admitted(length: U32, max_bytes: U32) -> Bool:
  U32.is_le(length, max_bytes)

# Handles positive.
def positive(value: U32) -> Bool:
  U32.is_lt(0, value)

# Handles bounded.
def bounded(+value: U32, maximum: U32) -> Bool:
  positive(value) && U32.is_le(value, maximum)

def frame.valid(+frame_bytes: U32, +receive_bytes: U32,
  +response_bytes: U32) -> Bool:
  bounded(frame_bytes, 1073741824) &&
    U32.is_le(frame_bytes, receive_bytes) &&
    U32.is_le(frame_bytes, response_bytes) &&
    bounded(receive_bytes, 1073741824) &&
    bounded(response_bytes, 1073741824)

def transport.valid(limits: TransportLimits) -> Bool:
  match limits:
    case TransportLimits{connections, frame_bytes, receive_bytes,
      response_bytes, frame_timeout_ms, response_timeout_ms}:
      bounded(connections, 4294967295) &&
        frame.valid(frame_bytes, receive_bytes, response_bytes) &&
        bounded(frame_timeout_ms, 4294967295) &&
        bounded(response_timeout_ms, 4294967295)

def queue.bytes.valid(+bytes: U32) -> Bool:
  bounded(bytes, 1073741824)

def queue.valid(limits: QueueLimits) -> Bool:
  match limits:
    case QueueLimits{requests, bytes, timeout_ms}:
      bounded(requests, 4294967295) &&
        queue.bytes.valid(bytes) &&
        bounded(timeout_ms, 4294967295)

def cursor.limits.valid(+cursors: U32,
  +cursors_per_snapshot: U32) -> Bool:
  bounded(cursors, 4096) &&
    bounded(cursors_per_snapshot, 64) &&
    U32.is_le(cursors_per_snapshot, cursors)

def retained.limits.valid(+snapshots: U32,
  +retained_root_bytes: U32, +retired_files: U32) -> Bool:
  bounded(snapshots, 64) &&
    bounded(retained_root_bytes, 67108864) &&
    bounded(retired_files, 64)

def index.limits.valid(+index_page_bytes: U32,
  +index_buffer_bytes: U32) -> Bool:
  bounded(index_page_bytes, 16384) &&
    bounded(index_buffer_bytes, 65536) &&
    U32.is_le(index_page_bytes, index_buffer_bytes)

def readers.valid(limits: ReaderLimits) -> Bool:
  match limits:
    case ReaderLimits{snapshots, cursors, cursors_per_snapshot,
      retained_root_bytes, retired_files, index_page_bytes,
      index_buffer_bytes, restore_bytes}:
      cursor.limits.valid(cursors, cursors_per_snapshot) &&
        retained.limits.valid(snapshots, retained_root_bytes, retired_files) &&
        index.limits.valid(index_page_bytes, index_buffer_bytes) &&
        bounded(restore_bytes, 67108864)

def validate.readers(options: Options, readers_ok: Bool) -> Decision:
  match readers_ok:
    case True{}: Accepted{options}
    case False{}: InvalidReaders{}

def validate.queue(options: Options, queue_ok: Bool,
  readers_ok: Bool) -> Decision:
  match queue_ok:
    case True{}: validate.readers(options, readers_ok)
    case False{}: InvalidQueue{}

def validate.transport(options: Options, transport_ok: Bool,
  queue_ok: Bool, readers_ok: Bool) -> Decision:
  match transport_ok:
    case True{}: validate.queue(options, queue_ok, readers_ok)
    case False{}: InvalidTransport{}

# Handles validate.
def validate(+options: Options) -> Decision:
  match options:
    case Options{transport, queue, readers}:
      validate.transport(options, transport.valid(transport),
        queue.valid(queue), readers.valid(readers))

def reader.retired.files(options: Options) -> U32:
  match options:
    case Options{_, _, ReaderLimits{_, _, _, _, retired_files, _, _, _}}:
      retired_files
