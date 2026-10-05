# Packed storage baseline benchmark report

comparison_valid=true
validated_samples=20
repeats=5
raw_samples=/Users/fvega/dev/mylsm/.mylsm/build/bench/packed-storage-pre-0.4.0.0-run3/samples.tsv
raw_logs=/Users/fvega/dev/mylsm/.mylsm/build/bench/packed-storage-pre-0.4.0.0-run3/raw
git_commit=9b9c82f1a299721b966714696bdeabad2589ca87
git_dirty=true
bend_version=bend 2.0.35
os=Darwin
architecture=arm64
logical_cpus=12
disk_device=/dev/disk3s5
disk_free_percent=32

| Workload | Metric | Median | Spread | Unit |
| --- | --- | ---: | ---: | --- |
| writes_4097 | elapsed_ms | 738 | 251 | elapsed_ms |
| writes_4097 | recovery_ms | 9732 | 208 | recovery_ms |
| writes_4097 | max_rss_bytes | 25608192 | 16384 | max_rss_bytes |
| writes_4097 | database_bytes | 363976 | 0 | database_bytes |
| writes_4097 | median_throughput_ops_s | 5551 |  | ops/s |
| writes_20485 | elapsed_ms | 2329 | 244 | elapsed_ms |
| writes_20485 | recovery_ms | 13340 | 1724 | recovery_ms |
| writes_20485 | max_rss_bytes | 53051392 | 3817472 | max_rss_bytes |
| writes_20485 | database_bytes | 825208 | 0 | database_bytes |
| writes_20485 | median_throughput_ops_s | 8795 |  | ops/s |
| writes_1000000 | elapsed_ms | 252254 | 7761 | elapsed_ms |
| writes_1000000 | recovery_ms | 17023 | 630 | recovery_ms |
| writes_1000000 | max_rss_bytes | 2502393856 | 104284160 | max_rss_bytes |
| writes_1000000 | database_bytes | 29712018 | 0 | database_bytes |
| writes_1000000 | median_throughput_ops_s | 3964 |  | ops/s |
| compaction_5x4097 | elapsed_ms | 31 | 5 | elapsed_ms |
| compaction_5x4097 | max_rss_bytes | 24428544 | 3817472 | max_rss_bytes |
| compaction_5x4097 | database_bytes | 138253 | 0 | database_bytes |
