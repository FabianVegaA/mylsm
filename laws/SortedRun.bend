import Base
import ../src/MemTable.bend as MemTable
import ../src/SortedRun.bend as SortedRun

# --- Stable sorted-run merge: closed anti-vacuity fixtures.
def run_newer() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"new"}}, Con{MemTable.Entry{"c", None{}}, Nil{}}}

# Run older for the sorted-run laws.
def run_older() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"old"}}, Con{MemTable.Entry{"b", Some{"bee"}}, Con{MemTable.Entry{"c", Some{"old-c"}}, Nil{}}}}

# Run merged for the sorted-run laws.
def run_merged() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"new"}}, Con{MemTable.Entry{"b", Some{"bee"}}, Con{MemTable.Entry{"c", None{}}, Nil{}}}}

# State the run merge newer wins property for the sorted-run laws.
law run_merge_newer_wins:
  {SortedRun.merge_newer(run_newer(), run_older()) == run_merged() : List<&2, MemTable.Entry>}

# State the run merge resolve closed property for the sorted-run laws.
law run_merge_resolve_closed:
  {SortedRun.resolve(SortedRun.merge_newer(run_newer(), run_older()), "c") == SortedRun.resolve_newest(Con{run_newer(), Con{run_older(), Nil{}}}, "c") : Maybe<&2, Maybe<&2, String>>}

# State the run merge strict closed property for the sorted-run laws.
law run_merge_strict_closed:
  {SortedRun.is_strict(SortedRun.merge_newer(run_newer(), run_older())) == True{} : Bool}

# State the run merge unique closed property for the sorted-run laws.
law run_merge_unique_closed:
  {SortedRun.is_unique(SortedRun.merge_newer(run_newer(), run_older())) == True{} : Bool}

# Run partitioned for the sorted-run laws.
def run_partitioned() -> List<&2, List<&2, MemTable.Entry>>:
  Con{Con{MemTable.Entry{"a", Some{"new"}}, Con{MemTable.Entry{"b", Some{"bee"}}, Nil{}}}, Con{Con{MemTable.Entry{"c", None{}}, Nil{}}, Nil{}}}

# State the run partition exact property for the sorted-run laws.
law run_partition_exact:
  {SortedRun.partition(2n, run_merged()) == run_partitioned() : List<&2, List<&2, MemTable.Entry>>}

# State the run partition concat property for the sorted-run laws.
law run_partition_concat:
  {SortedRun.concat_chunks(SortedRun.partition(2n, run_merged())) == run_merged() : List<&2, MemTable.Entry>}

# State the run partition bounded property for the sorted-run laws.
law run_partition_bounded:
  {SortedRun.chunks_bounded(2n, SortedRun.partition(2n, run_merged())) == True{} : Bool}

# State the run partition well formed property for the sorted-run laws.
law run_partition_well_formed:
  {(SortedRun.chunks_strict_unique(SortedRun.partition(2n, run_merged())), SortedRun.chunks_pairwise_disjoint(SortedRun.partition(2n, run_merged()))) == (True{}, True{}) : Bool & Bool}

# State the run partition zero target property for the sorted-run laws.
law run_partition_zero_target:
  {SortedRun.concat_chunks(SortedRun.partition(0n, run_merged())) == run_merged() : List<&2, MemTable.Entry>}
