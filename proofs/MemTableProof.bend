import Base
import ../laws/MemTable.bend as Laws
import ../src/MemTable.bend as MemTable

def Laws.mt_ryw(t, k, v):
  MemTable.ryw_bridge(t, k, v)

def Laws.mt_del(t, k, v):
  MemTable.del_bridge(t, k, v)

def Laws.mt_hit_ryw(t, k, v):
  MemTable.hit_ryw_bridge(t, k, v)

def Laws.mt_hit_del(t, k, v):
  MemTable.hit_del_bridge(t, k, v)

def Laws.mt_hit_miss(_k):
  {==}
