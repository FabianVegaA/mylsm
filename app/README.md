# MyLSM demonstration app

The entry point is `app/mylsm_demo.bend`. The filename intentionally avoids
`demo.bend` because macOS filesystems are commonly case-insensitive and Bend
module names are case-sensitive.

Run the portable demo:

```sh
bend app/mylsm_demo.bend
```

Or use the adaptive launcher:

```sh
bin/mylsm doctor
bin/mylsm demo
```

The app opens `.mylsm-demo-data`, performs durable puts, reads both values,
deletes `hello`, verifies the tombstone, and executes a small pure compute
worker. Storage remains CPU/IO work; the worker is marked with Bend's `!` GPU
call syntax and falls back to CPU when no GPU runtime is available.

## Interactive REPL

```sh
bin/mylsm repl --dir ./my-data
```

Commands:

```text
put <key> <value>   get <key>        del <key>
scan <lo> <hi>      stats            flush
compact             maintain         runtime
timing on|off|once  time <command>   mode cpu|gpu|auto
compute <fuel>      threads <n>      help / exit
```

The session is bounded to 256 commands to preserve Bend termination and can be
restarted against the same directory. In native mode, `threads <n>` performs a
controlled restart against the same durable directory. The REPL supports quoted
keys/values with `\\`, `\"`, `\n`, and `\t` escapes, plus checksummed
`import <path>` and `export <path>` commands.
