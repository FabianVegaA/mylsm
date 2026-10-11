import Base
import ../laws/LegacyWal.bend as Laws
import ../src/transfer/LegacyWal.bend as LegacyWal
import ../src/Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def Laws.empty_legacy_wal_is_valid():
  {==}

def Laws.one_complete_frame_is_valid():
  {==}

def Laws.multiple_complete_frames_are_valid():
  {==}

def Laws.truncated_frame_is_rejected():
  {==}

def Laws.corrupt_frame_checksum_is_rejected():
  {==}

def Laws.unsupported_header_is_rejected():
  {==}
