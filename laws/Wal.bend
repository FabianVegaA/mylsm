import Base
import ../src/Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def expected.finish(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Check whether whether expected holds for the WAL codec laws.
def empty_expected() -> Bytes.Bytes:
  expected.finish(Bytes.from_hex("0000002400000000b10689a773611ef6afdd983542da2b82a13d6133370d6abecbc1476b224b09ea"))

# Handle put delete expected in the WAL codec laws.
def put_delete_expected() -> Bytes.Bytes:
  expected.finish(Bytes.from_hex("000000350000000200000000016b000000017601000000017895d505a518f16f1c1036ea0541e9b9dc1e5c8123eea75d6eb074b0069150abb4"))

# Handle log header expected in the WAL codec laws.
def log_header_expected() -> Bytes.Bytes:
  expected.finish(Bytes.from_hex("4d594c534d335700"))

def bytes.eq.result(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, valid):
      valid

# State the wal v3 log header vector property for the WAL codec laws.
law wal_v3_log_header_vector:
  {bytes.eq.result(Bytes.eq(Wal.log_header(), log_header_expected())) == True{} : Bool}

# State the wal v3 log header decodes property for the WAL codec laws.
law wal_v3_log_header_decodes:
  {Wal.decode_header(log_header_expected()) == Done{Unit{}} : Result<&1, &1, Wal.Error, Unit>}

# State the wal v3 rejects text log header property for the WAL codec laws.
law wal_v3_rejects_text_log_header:
  {Wal.decode_header(expected.finish(Bytes.from_hex("2d"))) == Fail{Wal.Malformed{}} : Result<&1, &1, Wal.Error, Unit>}

# State the wal v3 empty frame vector property for the WAL codec laws.
law wal_v3_empty_frame_vector:
  {Wal.encode_frame(Wal.Batch{Nil{}}) == Done{empty_expected()} : Result<&1, &1, Wal.Error, Bytes.Bytes>}

# State the wal v3 put delete frame vector property for the WAL codec laws.
law wal_v3_put_delete_frame_vector:
  {Wal.encode_frame(Wal.Batch{Con{Wal.Put{"k", "v"}, Con{Wal.Del{"x"}, Nil{}}}}) == Done{put_delete_expected()} : Result<&1, &1, Wal.Error, Bytes.Bytes>}

# State the wal v3 empty frame decodes property for the WAL codec laws.
law wal_v3_empty_frame_decodes:
  {Wal.decode_frame(empty_expected()) == Done{Wal.Batch{Nil{}}} : Result<&1, &1, Wal.Error, Wal.Batch>}

# State the wal v3 put delete frame decodes property for the WAL codec laws.
law wal_v3_put_delete_frame_decodes:
  {Wal.decode_frame(put_delete_expected()) == Done{Wal.Batch{Con{Wal.Put{"k", "v"}, Con{Wal.Del{"x"}, Nil{}}}}} : Result<&1, &1, Wal.Error, Wal.Batch>}

# State the wal v3 frame rejects trailing byte property for the WAL codec laws.
law wal_v3_frame_rejects_trailing_byte:
  {Wal.decode_frame(Bytes.concat([empty_expected(), Bytes.new(1)])) == Fail{Wal.Malformed{}} : Result<&1, &1, Wal.Error, Wal.Batch>}

# State the wal v3 frame rejects bad digest property for the WAL codec laws.
law wal_v3_frame_rejects_bad_digest:
  {Wal.decode_frame(Bytes.set(put_delete_expected(), 56, 0)) == Fail{Wal.ChecksumMismatch{}} : Result<&1, &1, Wal.Error, Wal.Batch>}

# States the multi mutation frame limit rejects over block property.
law multi_mutation_frame_limit_rejects_over_block:
  {Wal.frame_length_allowed(2, 1048577) == False{} : Bool}

# States the delete record rejects key over codec cap property.
law delete_record_rejects_key_over_codec_cap:
  {Wal.record.delete((Bytes.Bytes{0, Bytes.alloc(0)}, 1073741820)) == Fail{Wal.TooLarge{}} : Result<&1, &1, Wal.Error, Bytes.Bytes>}

# States the put record rejects value over combined codec cap property.
law put_record_rejects_value_over_combined_codec_cap:
  {Wal.record.put((Bytes.Bytes{0, Bytes.alloc(0)}, 0),
    (Bytes.Bytes{0, Bytes.alloc(0)}, 1073741816)) == Fail{Wal.TooLarge{}} : Result<&1, &1, Wal.Error, Bytes.Bytes>}
