# MyLSM CLI Reference

MyLSM provides a developer CLI at `bin/mylsm`. The project remains an
experimental prototype: this interface is intended for demonstrations, local
experiments, and validation, not production operations.

## Command status

| Command or control | Status | Scope |
| --- | --- | --- |
| `demo` | Available | Durable demonstration and pure compute worker |
| `repl` | Available | Persistent interactive session, limited to 256 commands |
| `doctor` | Available | Host capability report |
| `check` | Available | Bend proof gate |
| `fuzz` | Available | Deterministic decoder smoke corpus |
| `bench` | Available | Minimal durable-put timing |
| `build`, `run` | Available | Native demo build and execution |
| `timing`, `time` | Available in REPL | Per-command millisecond timing |
| `mode`, `runtime`, `compute` | Available in REPL | Compute runtime controls |
| `threads` | Available in native REPL | Controlled durable process restart |
| `scan`, `stats`, `flush`, `compact`, `maintain` | Available in REPL | Local administration |
| Quoted strings, `import`, `export` | Available in REPL | Checksummed data interchange |

## Launcher usage

Run commands from the repository root:

```sh
bin/mylsm [command]
```

With no command, the launcher runs `demo`.

```sh
bin/mylsm --help
bin/mylsm doctor
bin/mylsm demo
bin/mylsm repl --dir ./my-data
bin/mylsm check
bin/mylsm fuzz
bin/mylsm bench
bin/mylsm build
bin/mylsm run
```

## Environment configuration

| Variable | Values | Default | Effect |
| --- | --- | --- | --- |
| `MYLSM_DEVICE` | `auto`, `cpu`, `gpu` | `auto` | Selects the execution policy |
| `MYLSM_THREADS` | Integer `1..256` | Detected logical CPUs | Passed to native Bend as `--threads N` |
| `MYLSM_GPU_MEMORY` | Bend memory size such as `4GB` | `4GB` | Passed as `--gpu SIZE` when GPU is selected |
| `MYLSM_DIR` | Filesystem path | `.mylsm-repl-data` | REPL database directory |

Examples:

```sh
MYLSM_DEVICE=cpu MYLSM_THREADS=4 bin/mylsm demo
MYLSM_DEVICE=gpu MYLSM_GPU_MEMORY=4GB bin/mylsm demo
MYLSM_DEVICE=auto bin/mylsm repl --dir ./data
```

## Runtime selection

- `cpu` attempts a native CPU build using the configured thread count and falls
  back to the portable Bend backend if native compilation is unavailable.
- `gpu` requires a detected Metal/CUDA device, a successful native build, and a
  generated `.gpu` artifact. It fails rather than making a false GPU claim.
- `auto` prefers a verified GPU artifact, then native CPU, then the portable CPU
  backend.

Storage operations always remain CPU/IO work. WAL append, `fsync`, Manifest,
SSTable access, flush, compaction, and recovery are never moved to the GPU. Only
pure workers called with Bend's `!` notation are GPU eligible.

## `doctor`

```sh
bin/mylsm doctor
```

Reports:

- Bend version;
- operating system and architecture;
- effective CPU thread count;
- Metal/CUDA probe result;
- native compiler availability;
- requested device policy.

A positive host probe is advisory. GPU execution is confirmed only when Bend
builds the `.gpu` artifact and the native runtime executes successfully.

## `demo`

```sh
bin/mylsm demo
```

The demo:

1. opens or recovers `.mylsm-demo-data` with `Recover.open_db`;
2. durably writes `hello=world` and `answer=42`;
3. reads both values;
4. deletes `hello` and observes `<missing>`;
5. executes a pure compute worker;
6. prints `MYLSM DEMO OK`.

Acknowledged mutations pass through WAL append, `fsync`, and the MemTable update.

## Interactive REPL

```sh
bin/mylsm repl
bin/mylsm repl --dir ./my-data
```

The REPL opens the selected directory through `Recover.open_db` and threads one
`Db.Db` state through the session. The loop is bounded to 256 commands to satisfy
Bend termination without `@unsafe`. Start a new session to continue after the
limit; acknowledged data is recovered from disk.

The grammar supports unquoted tokens and double-quoted values. Quoted tokens
support `\\`, `\"`, `\n`, and `\t` escapes, including empty strings.

### Core commands

```text
put <key> <value>
get <key>
del <key>
scan <lo> <hi>
help
exit
```

- `put` and `del` use `Recover.write`, including durable WAL behavior and normal
  maintenance.
- `get` prints the value or `<missing>`.
- `scan` prints live entries as `key=value` for the requested range.

### Administrative commands

```text
stats
flush
compact
maintain
```

- `stats` reports the current MemTable entry count and loaded level count.
- `flush` calls `Flush.flush`.
- `compact` calls `Compact.compact`.
- `maintain` calls `Recover.maintain`.

Failures propagate through `IO.try`; a failed operation does not print a success
marker.

### Timing

```text
timing on
timing off
timing once
time <command>
```

- `timing on` measures following commands.
- `timing off` disables global timing.
- `timing once` measures the next command and then returns to off.
- `time <command>` measures only its nested command.

Timing uses `IO.now` and prints `time_ms=N`. A durable write measurement includes
WAL append, `fsync`, MemTable update, and maintenance. Millisecond timing must not
be interpreted as microsecond precision.

### Compute runtime

```text
runtime
mode auto
mode cpu
mode gpu
compute <fuel>
threads <n>
```

- `runtime` prints compute mode, GPU-enabled state, configured threads, and
  `storage=cpu/io`.
- `mode` changes pure-worker dispatch during the session.
- `compute` executes the pure worker using the selected dispatch.
- `threads` validates `1..256` and, in native mode, requests a supervised
  restart against the same durable directory. Portable mode rejects the command
  because Bend runtime thread count is process-global.

A session can switch to `mode gpu` only when the process was started with GPU
support. CPU and GPU worker agreement is covered by closed laws in `LAWS.bend`.

## Validation commands

```sh
bend PROOF.bend
printf 'hello\n' | MYLSM_TEST_ENV=world bend bench/console_smoke.bend
bench/cli_smoke.sh
```

The smoke script covers capability reporting, the proof gate, console effects,
demo execution, durable REPL commands, timing, scan, and recovery after restart.

## Import and export

```text
export <path>
import <path>
```

Export writes a sorted, deduplicated live view using a versioned, length-framed
WAL payload and a Manifest-style checksum. It writes `<path>.tmp` and renames it
into place. Import validates version, framing, payload, and checksum before
applying one durable batch. Quoted paths are accepted.

## Current limitations

- The REPL accepts at most 256 commands per process.
- Fuzzing currently uses a small deterministic corpus, not a million-input
  randomized campaign.
- The benchmark remains a smoke measurement, not evidence of competitiveness.
- Formal proofs cover selected pure laws and closed vectors, not the host OS or
  all open inputs.
