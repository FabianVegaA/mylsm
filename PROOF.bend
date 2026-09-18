import Base
import ./LAWS.bend as Laws
import ./src/MemTable.bend as MemTable
import ./src/Sstable.bend as Sstable
import ./src/Manifest.bend as Manifest
import ./src/MergeIter.bend as MergeIter
import ./src/SstFile.bend as SstFile
import ./src/Flush.bend as Flush
import ./src/Compact.bend as Compact
import ./src/Recover.bend as Recover

def Laws.cmp_refl_a():
  {==}

def Laws.cmp_order_ab():
  {==}

def Laws.mt_ryw(t, k, v):
  MemTable.ryw_bridge(t, k, v)

def Laws.mt_del(t, k, v):
  MemTable.del_bridge(t, k, v)

def Laws.wal_rt_empty():
  {==}

def Laws.wal_rt_put1():
  {==}

def Laws.wal_rt_del1():
  {==}

def Laws.wal_rt_multi():
  {==}

def Laws.sst_sorted():
  {==}

def Laws.sst_newest():
  {==}

def Laws.bloom_safe():
  {==}

def Laws.bloom_schedule(e, l, n):
  {==}

def Laws.manifest_empty():
  {==}

def Laws.manifest_two():
  {==}

def Laws.scan_newest():
  {==}

def Laws.scan_range():
  {==}

def Laws.scan_drops_dels():
  {==}

def Laws.scan_agree():
  {==}

def Laws.db_ryw():
  {==}

def Laws.db_del():
  {==}

def Laws.db_batch_atomic():
  {==}

def Laws.db_recover():
  {==}

def Laws.sstfile_rt():
  {==}

def Laws.sstfile_reject():
  {==}

def Laws.flush_hit_pre():
  {==}

def Laws.flush_hit_post():
  {==}

def Laws.flush_preserve():
  {==}

def Laws.flush_miss():
  {==}

def Laws.compact_live():
  {==}

def Laws.compact_disjoint():
  {==}

def Laws.compact_absorbed():
  {==}

def Laws.compact_hit():
  {==}

def Laws.compact_preserve():
  {==}

def Laws.compact_miss():
  {==}

def Laws.compact_noop():
  {==}

def Laws.frame_len_ok():
  {==}

def Laws.replay_single():
  {==}

def Laws.replay_torn():
  {==}

def Laws.needs_flush_hi():
  {==}

def Laws.needs_flush_lo():
  {==}

def Laws.count_gen_one():
  {==}

def Laws.recover_equiv():
  {==}

def Laws.wal_fail_closed(s):
  {==}

def Laws.manifest_fail_closed(s):
  {==}

def Laws.sstfile_fail_closed(s):
  {==}
