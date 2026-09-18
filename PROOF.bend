import Base
import ./LAWS.bend as Laws
import ./src/MemTable.bend as MemTable
import ./src/Sstable.bend as Sstable
import ./src/Manifest.bend as Manifest
import ./src/MergeIter.bend as MergeIter

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
