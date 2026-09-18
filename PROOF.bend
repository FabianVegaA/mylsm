import Base
import ./LAWS.bend as Laws
import ./src/MemTable.bend as MemTable

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
