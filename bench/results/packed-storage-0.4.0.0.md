# Packed storage candidate benchmark report

comparison_valid=true
validated_samples=20
repeats=5
raw_samples=/Users/fvega/dev/mylsm/.mylsm/build/bench/packed-storage-release-repeat3/samples.tsv
raw_logs=/Users/fvega/dev/mylsm/.mylsm/build/bench/packed-storage-release-repeat3/raw
git_commit=83c44730f2518c4ee6d8dd4ffb847a79aab113ab
git_dirty=true
bend_version=bend 2.0.35
os=Darwin
architecture=arm64
logical_cpus=12
disk_device=/dev/disk3s5
disk_free_percent=31

| Workload | Metric | Median | Spread | Unit |
| --- | --- | ---: | ---: | --- |
| writes_4097 | elapsed_ms | 547 | 145 | elapsed_ms |
| writes_4097 | recovery_ms | 56 | 13 | recovery_ms |
| writes_4097 | max_rss_bytes | 4472832 | 32768 | max_rss_bytes |
| writes_4097 | database_bytes | 272287 | 0 | database_bytes |
| writes_4097 | median_throughput_ops_s | 7489 |  | ops/s |
| writes_20485 | elapsed_ms | 2246 | 247 | elapsed_ms |
| writes_20485 | recovery_ms | 81 | 7 | recovery_ms |
| writes_20485 | max_rss_bytes | 23183360 | 1376256 | max_rss_bytes |
| writes_20485 | database_bytes | 736089 | 0 | database_bytes |
| writes_20485 | median_throughput_ops_s | 9120 |  | ops/s |
| writes_1000000 | elapsed_ms | 156931 | 8919 | elapsed_ms |
| writes_1000000 | recovery_ms | 3072 | 392 | recovery_ms |
| writes_1000000 | max_rss_bytes | 942784512 | 85426176 | max_rss_bytes |
| writes_1000000 | database_bytes | 30797466 | 0 | database_bytes |
| writes_1000000 | median_throughput_ops_s | 6372 |  | ops/s |
| compaction_5x4097 | elapsed_ms | 29 | 2 | elapsed_ms |
| compaction_5x4097 | max_rss_bytes | 22888448 | 2752512 | max_rss_bytes |
| compaction_5x4097 | database_bytes | 142385 | 0 | database_bytes |
