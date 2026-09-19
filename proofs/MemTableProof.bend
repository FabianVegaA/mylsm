import Base
import ../laws/MemTable.bend as Laws
import ../src/MemTable.bend as MemTable

def Laws.mt_ryw(t, k, v):
  MemTable.ryw_bridge(t, k, v)

def Laws.mt_del(t, k, v):
  MemTable.del_bridge(t, k, v)
