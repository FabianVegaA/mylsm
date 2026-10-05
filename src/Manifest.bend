import Base
import ./StorageBytes.bend as StorageBytes
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ./hub_sha/sha256.bend as SHA

# Represent Manifest data used by the binary manifest codec.
type Manifest is Data:
  M{levels: List<&2, List<&2, String>>}

# Represent Error data used by the binary manifest codec.
type Error is Data:
  TooLarge{}
  InvalidName{}

# Represent ParseState data used by the binary manifest codec.
type ParseState is Data:
  ReadNamesCount{levels_left: Nat, levels_acc: List<&2, List<&2, String>>}
  ReadNameLength{levels_left: Nat, levels_acc: List<&2, List<&2, String>>, names_left: Nat, names_acc: List<&2, String>}
  ReadNameBody{levels_left: Nat, levels_acc: List<&2, List<&2, String>>, names_left: Nat, names_acc: List<&2, String>}

# Represent ParseInput data used by the binary manifest codec.
type ParseInput is Type:
  NoInput{cursor: Bytes.Cursor}
  NameInput{value: Bytes.Cursor & Maybe<&2, String>}

# Represent ParseTransition data used by the binary manifest codec.
type ParseTransition is Type:
  Continue{state: ParseState, input: ParseInput}
  Reject{cursor: Bytes.Cursor}
  Finish{cursor: Bytes.Cursor, levels: List<&2, List<&2, String>>}

def magic.result(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Handle magic in the binary manifest codec.
def magic() -> Bytes.Bytes:
  magic.result(Bytes.from_hex("4d594c534d334d00"))

# Handle u32 in the binary manifest codec.
def u32(+value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

def bytes.clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def bytes.clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      bytes.clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

def bytes.clone.first(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (left, _):
      left

def bytes.length(pair: Bytes.Bytes & U32) -> U32:
  match pair:
    case (_, len):
      len

def bytes.slice.second(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, second):
      second

def encode.name.copies(+len: U32, tail: Bytes.Bytes, copies: Array<U32> & Array<U32>) -> Bytes.Bytes:
  match copies:
    case (stored, _unused):
      Bytes.concat([u32(len), Bytes.Bytes{len, stored}, tail])

def encode.name.buffer(+len: U32, tail: Bytes.Bytes, packed: Bytes.Bytes) -> Bytes.Bytes:
  match packed:
    case Bytes.Bytes{_, buf}:
      encode.name.copies(len, tail, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

def encode.name.copy(pair: Bytes.Bytes & U32, tail: Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (packed, +len):
      encode.name.buffer(len, tail, packed)

def encode.name.prefix(result: Result<&1, &1, U32 & String, Bytes.Bytes>, tail: Bytes.Bytes) -> Bytes.Bytes:
  match result:
    case Fail{_}:
      Bytes.concat([u32(0), Bytes.new(0), tail])
    case Done{encoded}:
      encode.name.copy(Bytes.length(encoded), tail)

def name.char.valid(+char: Char) -> Bool:
  +byte = Char.to_u32(char)
  U32.is_le(48, byte) && U32.is_le(byte, 57) ||
    U32.is_le(65, byte) && U32.is_le(byte, 90) ||
    U32.is_le(97, byte) && U32.is_le(byte, 122) ||
    U32.is_eq(byte, 45) || U32.is_eq(byte, 95) || U32.is_eq(byte, 46) || U32.is_lt(127, byte)

def name.text.valid.chars(text: String, valid: Bool) -> Bool:
  match text:
    case SNil{}:
      valid
    case SCon{+char, rest}:
      name.text.valid.chars(rest, valid && name.char.valid(char))

def name.text.valid.edge(text: String, dot_component: Bool) -> Bool:
  match dot_component:
    case True{}:
      False{}
    case False{}:
      name.text.valid.chars(text, True{})

def name.text.valid(+text: String) -> Bool:
  match text:
    case SNil{}:
      False{}
    case SCon{_, _}:
      name.text.valid.edge(text, String.eq(text, ".") || String.eq(text, ".."))

def names.valid.step(rest: List<&2, String>, valid: Bool) -> Bool:
  match rest valid:
    case _ False{}:
      False{}
    case Nil{} True{}:
      True{}
    case Con{name, tail} True{}:
      names.valid.step(tail, name.text.valid(name))

def names.valid(names: List<&2, String>) -> Bool:
  names.valid.step(names, True{})

def levels.valid.step(rest: List<&2, List<&2, String>>, valid: Bool) -> Bool:
  match rest valid:
    case _ False{}:
      False{}
    case Nil{} True{}:
      True{}
    case Con{+names, tail} True{}:
      levels.valid.step(tail, names.valid(names))

def levels.valid(levels: List<&2, List<&2, String>>) -> Bool:
  levels.valid.step(levels, True{})

def encode.names(names: List<&2, String>) -> Bytes.Bytes:
  match names:
    case Nil{}:
      Bytes.new(0)
    case Con{name, rest}:
      encode.name.prefix(StorageBytes.from_string(name), encode.names(rest))

def encode.levels(levels: List<&2, List<&2, String>>) -> Bytes.Bytes:
  match levels:
    case Nil{}:
      Bytes.new(0)
    case Con{+names, rest}:
      Bytes.concat([u32(U32.from_nat(List.length(&2, String, names))), encode.names(names), encode.levels(rest)])

def encode.body(+manifest: Manifest) -> Bytes.Bytes:
  match manifest:
    case M{levels}:
      Bytes.concat([magic(), u32(3), u32(U32.from_nat(List.length(&2, List<&2, String>, levels))), encode.levels(levels)])

def encode.digest.checked(pair: Bytes.Bytes & Bytes.Bytes) -> Result<&1, &1, Error, Bytes.Bytes>:
  match pair:
    case (packed, size_packed):
      Bool.pick(Result<&1, &1, Error, Bytes.Bytes>,
        U32.is_le(bytes.length(Bytes.length(size_packed)), StorageBytes.MAX_MANIFEST_BYTES()),
        Done{packed}, Fail{TooLarge{}})

def encode.body.digest(pair: Bytes.Bytes & Bytes.Bytes) -> Result<&1, &1, Error, Bytes.Bytes>:
      match pair:
        case (body, hash_body):
          encode.digest.checked(bytes.clone.split(Bytes.concat([body, SHA.sha256_packed_bytes(hash_body)])))

def encode.body.checked(manifest: Manifest) -> Result<&1, &1, Error, Bytes.Bytes>:
      body_pair = bytes.clone.split(encode.body(manifest))
      encode.body.digest(body_pair)

def encode.checked(manifest: Manifest, valid: Bool) -> Result<&1, &1, Error, Bytes.Bytes>:
  match valid:
    case False{}:
      Fail{InvalidName{}}
    case True{}:
      encode.body.checked(manifest)

def manifest.valid(manifest: Manifest) -> Bool:
  match manifest:
    case M{levels}:
      levels.valid(levels)

# Handle serialize in the binary manifest codec.
def serialize(+manifest: Manifest) -> Result<&1, &1, Error, Bytes.Bytes>:
  encode.checked(manifest, manifest.valid(manifest))

def token.from.result(result: Result<&1, &1, Error, Bytes.Bytes>) -> String:
  match result:
    case Done{bytes}:
      Bytes.to_hex(bytes)
    case Fail{_}:
      ""

# Handle token in the binary manifest codec.
def token(manifest: Manifest) -> String:
  token.from.result(serialize(manifest))


def cursor.u32(cursor: Bytes.Cursor) -> Bytes.Cursor & Maybe<&2, U32>:
  Bytes.Cursor.u32be(cursor)

def cursor.bytes(cursor: Bytes.Cursor, len: U32) -> Bytes.Cursor & Maybe<&1, Bytes.CursorLimit>:
  Bytes.Cursor.region(cursor, len)

def read.name.text(
  cursor: Bytes.Cursor,
  limit: Bytes.CursorLimit,
  name: String,
  valid: Bool
) -> Bytes.Cursor & Maybe<&2, String>:
  match valid:
    case False{}:
      (Bytes.Cursor.leave(cursor, limit), None{})
    case True{}:
      (Bytes.Cursor.leave(cursor, limit), Some{name})

def read.name.decoded(
  cursor: Bytes.Cursor,
  limit: Bytes.CursorLimit,
  decoded: Result<&1, &1, U32 & String, String>
) -> Bytes.Cursor & Maybe<&2, String>:
  match decoded:
    case Fail{_}:
      (Bytes.Cursor.leave(cursor, limit), None{})
    case Done{+name}:
      read.name.text(cursor, limit, name, name.text.valid(name))

def read.name.checked(
  cursor: Bytes.Cursor,
  limit: Bytes.CursorLimit,
  bytes: Bytes.Bytes
) -> Bytes.Cursor & Maybe<&2, String>:
  read.name.decoded(cursor, limit, StorageBytes.to_string_strict(bytes))

def read.name.buffer.copies(
  limit: Bytes.CursorLimit,
  len: U32,
  +offset: U32,
  start: U32,
  end: U32,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Cursor & Maybe<&2, String>:
  match copies:
    case (cursor_bytes, slice_bytes):
      read.name.checked(Bytes.Cursor{cursor_bytes, offset, start, end}, limit,
        bytes.slice.second(Bytes.slice(slice_bytes, offset, len)))

def read.name.buffer(cursor: Bytes.Cursor, limit: Bytes.CursorLimit, len: U32) -> Bytes.Cursor & Maybe<&2, String>:
  match cursor:
    case Bytes.Cursor{source, +offset, +start, +end}:
      read.name.buffer.copies(limit, len, offset, start, end, bytes.clone.split(source))

def read.name.region.result(
  region: Bytes.Cursor & Maybe<&1, Bytes.CursorLimit>,
  len: U32
) -> Bytes.Cursor & Maybe<&2, String>:
  match region:
    case (next, None{}):
      (next, None{})
    case (next, Some{limit}):
      read.name.buffer(next, limit, len)

def read.name.region(cursor: Bytes.Cursor, +len: U32) -> Bytes.Cursor & Maybe<&2, String>:
  read.name.region.result(cursor.bytes(cursor, len), len)

def read.name(pair: Bytes.Cursor & Maybe<&2, U32>) -> Bytes.Cursor & Maybe<&2, String>:
  match pair:
    case (cursor, None{}):
      (cursor, None{})
    case (cursor, Some{len}):
      read.name.region(cursor, len)

def parse.step.reject.name(value: Bytes.Cursor & Maybe<&2, String>) -> ParseTransition:
  match value:
    case (cursor, _):
      Reject{cursor}

def parse.step.reject(input: ParseInput) -> ParseTransition:
  match input:
    case NoInput{cursor}:
      Reject{cursor}
    case NameInput{value}:
      parse.step.reject.name(value)

def parse.step.count.value(
  levels_left: Nat,
  levels_acc: List<&2, List<&2, String>>,
  value: Bytes.Cursor & Maybe<&2, U32>
) -> ParseTransition:
  match value:
    case (cursor, None{}):
      Reject{cursor}
    case (cursor, Some{count}):
      Continue{ReadNameLength{levels_left, levels_acc, U32.to_nat(count), Nil{}}, NoInput{cursor}}

def parse.step.count(levels_left: Nat, levels_acc: List<&2, List<&2, String>>, input: ParseInput) -> ParseTransition:
  match input:
    case NoInput{cursor}:
      parse.step.count.value(levels_left, levels_acc, cursor.u32(cursor))
    case NameInput{_}:
      parse.step.reject(input)

def parse.step.length.named(
  levels_left: Nat,
  levels_acc: List<&2, List<&2, String>>,
  names_left: Nat,
  names_acc: List<&2, String>,
  value: Bytes.Cursor & Maybe<&2, String>
) -> ParseTransition:
  Continue{ReadNameBody{levels_left, levels_acc, names_left, names_acc}, NameInput{value}}

def parse.step.length.value(
  levels_left: Nat,
  levels_acc: List<&2, List<&2, String>>,
  names_left: Nat,
  names_acc: List<&2, String>,
  value: Bytes.Cursor & Maybe<&2, U32>
) -> ParseTransition:
  match value:
    case (cursor, None{}):
      Reject{cursor}
    case (cursor, Some{len}):
      parse.step.length.named(levels_left, levels_acc, names_left, names_acc, read.name((cursor, Some{len})))

def parse.step.length.input(
  levels_left: Nat,
  levels_acc: List<&2, List<&2, String>>,
  names_left: Nat,
  names_acc: List<&2, String>,
  input: ParseInput
) -> ParseTransition:
  match input:
    case NoInput{cursor}:
      parse.step.length.value(levels_left, levels_acc, names_left, names_acc, cursor.u32(cursor))
    case NameInput{_}:
      parse.step.reject(input)

def parse.step.level.remaining(
  levels_left: Nat,
  levels_acc: List<&2, List<&2, String>>,
  names: List<&2, String>,
  cursor: Bytes.Cursor
) -> ParseTransition:
  match levels_left:
    case 0n:
      Reject{cursor}
    case 1n+rest:
      match rest:
        case 0n:
          Finish{cursor, List.reverse(&2, List<&2, String>, Con{names, levels_acc})}
        case 1n+more:
          Continue{ReadNamesCount{1n+more, Con{names, levels_acc}}, NoInput{cursor}}

def parse.step.level(
  levels_left: Nat,
  levels_acc: List<&2, List<&2, String>>,
  names_acc: List<&2, String>,
  input: ParseInput
) -> ParseTransition:
  match input:
    case NoInput{cursor}:
      parse.step.level.remaining(levels_left, levels_acc, List.reverse(&2, String, names_acc), cursor)
    case NameInput{_}:
      parse.step.reject(input)

def parse.step.name.value(
  levels_left: Nat,
  levels_acc: List<&2, List<&2, String>>,
  names_left: Nat,
  names_acc: List<&2, String>,
  value: Bytes.Cursor & Maybe<&2, String>
) -> ParseTransition:
  match value:
    case (cursor, None{}):
      Reject{cursor}
    case (cursor, Some{name}):
      Continue{ReadNameLength{levels_left, levels_acc, names_left, Con{name, names_acc}}, NoInput{cursor}}

def parse.step.name(
  levels_left: Nat,
  levels_acc: List<&2, List<&2, String>>,
  names_left: Nat,
  names_acc: List<&2, String>,
  input: ParseInput
) -> ParseTransition:
  match input:
    case NameInput{value}:
      parse.step.name.value(levels_left, levels_acc, names_left, names_acc, value)
    case NoInput{_}:
      parse.step.reject(input)

def parse.step.state(state: ParseState, input: ParseInput) -> ParseTransition:
  match state:
    case ReadNamesCount{levels_left, levels_acc}:
      parse.step.count(levels_left, levels_acc, input)
    case ReadNameLength{levels_left, levels_acc, names_left, names_acc}:
      match names_left:
        case 0n:
          parse.step.level(levels_left, levels_acc, names_acc, input)
        case 1n+rest:
          parse.step.length.input(levels_left, levels_acc, rest, names_acc, input)
    case ReadNameBody{levels_left, levels_acc, names_left, names_acc}:
      parse.step.name(levels_left, levels_acc, names_left, names_acc, input)

def parse.loop.exhausted.name(value: Bytes.Cursor & Maybe<&2, String>) -> Bytes.Cursor & Maybe<&2, Manifest>:
  match value:
    case (cursor, _):
      (cursor, None{})

def parse.loop.exhausted(transition: ParseTransition) -> Bytes.Cursor & Maybe<&2, Manifest>:
  match transition:
    case Continue{_, NoInput{cursor}}:
      (cursor, None{})
    case Continue{_, NameInput{value}}:
      parse.loop.exhausted.name(value)
    case Reject{cursor}:
      (cursor, None{})
    case Finish{cursor, _}:
      (cursor, None{})

def parse.loop(fuel: Nat, transition: ParseTransition) -> Bytes.Cursor & Maybe<&2, Manifest>:
  match fuel:
    case 0n:
      parse.loop.exhausted(transition)
    case 1n+rest:
      match transition:
        case Reject{cursor}:
          (cursor, None{})
        case Finish{cursor, levels}:
          (cursor, Some{M{levels}})
        case Continue{state, input}:
          parse.loop(rest, parse.step.state(state, input))

def bytes.eq.result(comparison: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match comparison:
    case (_, _, equal):
      equal

def checksum.valid(bytes: Bytes.Bytes, body_len: U32, digest: Bytes.Bytes) -> Bool:
  bytes.eq.result(Bytes.eq(SHA.sha256_packed_bytes(bytes.slice.second(Bytes.slice(bytes, 0, body_len))), digest))

def parse.body.digest.verified(
  body_len: U32,
  hash_source: Bytes.Bytes,
  levels: List<&2, List<&2, String>>,
  digest: Bytes.Bytes
) -> Maybe<&2, Manifest>:
  Bool.pick(Maybe<&2, Manifest>, checksum.valid(hash_source, body_len, digest), Some{M{levels}}, None{})

def parse.body.digest.footer(
  +body_len: U32,
  hash_source: Bytes.Bytes,
  levels: List<&2, List<&2, String>>,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Maybe<&2, Manifest>:
  match copies:
    case (_, digest_source):
      parse.body.digest.verified(body_len, hash_source, levels, bytes.slice.second(Bytes.slice(digest_source, body_len, 32)))

def parse.body.digest.checked(
  body_len: U32,
  hash_source: Bytes.Bytes,
  footer_source: Bytes.Bytes,
  levels: List<&2, List<&2, String>>,
  within_size: Bool
) -> Maybe<&2, Manifest>:
  match within_size:
    case False{}:
      None{}
    case True{}:
      parse.body.digest.footer(body_len, hash_source, levels, bytes.clone.split(footer_source))

def parse.body.digest.size(
  +body_len: U32,
  hash_source: Bytes.Bytes,
  size_pair: Bytes.Bytes & U32,
  levels: List<&2, List<&2, String>>
) -> Maybe<&2, Manifest>:
  match size_pair:
    case (footer_source, +total):
      parse.body.digest.checked(body_len, hash_source, footer_source, levels, U32.is_eq(total, (body_len + 32 : U32)))

def parse.body.digest.sources(
  body_len: U32,
  levels: List<&2, List<&2, String>>,
  sources: Bytes.Bytes & Bytes.Bytes
) -> Maybe<&2, Manifest>:
  match sources:
    case (hash_source, footer_source):
      parse.body.digest.size(body_len, hash_source, Bytes.length(footer_source), levels)

def parse.body.position(
  cursor: Bytes.Cursor,
  source: Bytes.Bytes,
  levels: List<&2, List<&2, String>>
) -> Maybe<&2, Manifest>:
  match cursor:
    case Bytes.Cursor{_, +body_len, _, _}:
      parse.body.digest.sources(body_len, levels, bytes.clone.split(source))

def parse.body.levels.manifest(cursor: Bytes.Cursor, source: Bytes.Bytes, manifest: Manifest) -> Maybe<&2, Manifest>:
  match manifest:
    case M{levels}:
      parse.body.position(cursor, source, levels)

def parse.body.levels(source: Bytes.Bytes, result: Bytes.Cursor & Maybe<&2, Manifest>) -> Maybe<&2, Manifest>:
  match result:
    case (_, None{}):
      None{}
    case (body_end, Some{manifest}):
      parse.body.levels.manifest(body_end, source, manifest)

def parse.body.start(count: Nat, cursor: Bytes.Cursor, source: Bytes.Bytes) -> Maybe<&2, Manifest>:
  match count:
    case 0n:
      parse.body.levels(source, parse.loop(Nat.add(Nat.mul(3n, U32.to_nat(StorageBytes.MAX_MANIFEST_BYTES())), 16n), Finish{cursor, Nil{}}))
    case 1n+rest:
      parse.body.levels(source, parse.loop(Nat.add(Nat.mul(3n, U32.to_nat(StorageBytes.MAX_MANIFEST_BYTES())), 16n), Continue{ReadNamesCount{1n+rest, Nil{}}, NoInput{cursor}}))

def parse.body(pair: Bytes.Cursor & Maybe<&2, U32>, source: Bytes.Bytes) -> Maybe<&2, Manifest>:
  match pair:
    case (_, None{}):
      None{}
    case (cursor, Some{count}):
      parse.body.start(U32.to_nat(count), cursor, source)

def parse.version(cursor: Bytes.Cursor, source: Bytes.Bytes, valid: Bool) -> Maybe<&2, Manifest>:
  match valid:
    case False{}:
      None{}
    case True{}:
      parse.body(cursor.u32(cursor), source)

def parse.magic(pair: Bytes.Cursor & Maybe<&2, U32>, source: Bytes.Bytes) -> Maybe<&2, Manifest>:
  match pair:
    case (_, None{}):
      None{}
    case (cursor, Some{version}):
      parse.version(cursor, source, U32.is_eq(version, 3))

def parse.input.second.valid(source: Bytes.Bytes, cursor: Bytes.Cursor, valid: Bool) -> Maybe<&2, Manifest>:
  match valid:
    case False{}:
      None{}
    case True{}:
      parse.magic(cursor.u32(cursor), source)

def parse.input.second(source: Bytes.Bytes, pair: Bytes.Cursor & Maybe<&2, U32>) -> Maybe<&2, Manifest>:
  match pair:
    case (_, None{}):
      None{}
    case (cursor, Some{second}):
      parse.input.second.valid(source, cursor, U32.is_eq(second, 1295207680))

def parse.input.first.valid(source: Bytes.Bytes, cursor: Bytes.Cursor, valid: Bool) -> Maybe<&2, Manifest>:
  match valid:
    case False{}:
      None{}
    case True{}:
      parse.input.second(source, cursor.u32(cursor))

def parse.input.first(source: Bytes.Bytes, pair: Bytes.Cursor & Maybe<&2, U32>) -> Maybe<&2, Manifest>:
  match pair:
    case (_, None{}):
      None{}
    case (cursor, Some{first}):
      parse.input.first.valid(source, cursor, U32.is_eq(first, 1297697875))

def parse.input.start(sources: Bytes.Bytes & Bytes.Bytes) -> Maybe<&2, Manifest>:
  match sources:
    case (source, cursor_source):
      parse.input.first(source, Bytes.Cursor.u32be(Bytes.Cursor.new(cursor_source)))

def parse.input.with_magic(source: Bytes.Bytes) -> Maybe<&2, Manifest>:
  parse.input.start(bytes.clone.split(source))

def parse.bounded(source: Bytes.Bytes, within_limit: Bool) -> Maybe<&2, Manifest>:
  match within_limit:
    case False{}:
      None{}
    case True{}:
      parse.input.with_magic(source)

def parse.size(size_pair: Bytes.Bytes & U32) -> Maybe<&2, Manifest>:
  match size_pair:
    case (source, len):
      parse.bounded(source, U32.is_le(len, StorageBytes.MAX_MANIFEST_BYTES()))

# Handle parse in the binary manifest codec.
def parse(source: Bytes.Bytes) -> Maybe<&2, Manifest>:
  parse.size(Bytes.length(source))

# Check whether decided holds for the binary manifest codec.
def is_decided(_result: Maybe<&2, Manifest>) -> Bool:
  True{}
