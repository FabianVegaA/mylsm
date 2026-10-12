# Examples

These Bend programs use the public `mylsm.bend` API. Run them from the repository root with Bend 2.0.36. Each program creates a new database at `MYLSM_DB_PATH`, so give it a path that does not exist yet.

```sh
db=$(mktemp -d)
rmdir "$db"
MYLSM_DB_PATH="$db" bend examples/utf8_basic.bend
```

The database remains at `$db` after the program ends. Use a fresh path for each run.

| Example | Level | What it shows |
| --- | --- | --- |
| [utf8_basic.bend](utf8_basic.bend) | Basic | Create a database, write and read UTF-8 text, close the handle. |
| [bytes_basic.bend](bytes_basic.bend) | Intermediate | Store and compare a binary key and value containing bytes outside UTF-8. |
| [snapshot_scan.bend](snapshot_scan.bend) | Advanced | Update a key after taking a snapshot, scan the stable old value, close cursor and snapshot, then read the new live value. |

To run another example, repeat the three shell lines above with its filename. `bytes_basic.bend` prints `BYTES_EXAMPLE_OK`; `snapshot_scan.bend` prints `snapshot: old`, `current: new`, and `SNAPSHOT_EXAMPLE_OK`.

The examples fail with a nonzero exit status if an operation does not produce the expected result. They use only the public `mylsm.bend` database facade. The byte example also imports `bend-kit-bytes` to construct raw byte buffers.

For error meanings and resource limits, see the [durable API guide](../docs/DURABLE_API.md). The [0.6 acceptance report](../bench/results/mylsm-0.6.0.0-acceptance.md) records the current validation limits.
