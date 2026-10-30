# MyLSM 0.6 Linux and macOS environment baseline

Captured 2026-10-25 from baseline revision `b7ae44db1e7497340933b54ac75b8a4e3f915d84`. The remote checkout is isolated under `~/dev/mylsm-validation/` and uses the same locked inputs as the local worktree.

Lock hashes:

| File | SHA-256 |
| --- | --- |
| `flake.lock` | `b81a68e5924dabb105799bfb14e28ca1a50d82bb865a3396e35d9b1e095ff7c7` |
| `ez.lock.toml` | `dd7c7e38623ea72f295508c234c4d7b902609cdaad0d7c2f2ae608a67ba7a676` |

Toolchain in both Nix development environments: Bend 2.0.39, Lean 4.34.0, Bolt 1.18.0. `lean-toolchain` pins Lean 4.34.0 for the BendTT verdict kernel.

## Lenovo

Lenovo runs NixOS x86_64, kernel 6.18.56, on an AMD Ryzen 5 2500U with 8 logical CPUs and 6.8 GiB RAM. The validation checkout is on ext4 with 126 GiB free. Nix is 2.34.9.

The unchanged baseline proof suite passed `83/83`, with no failures or timeouts, using `nix develop path:.` and `proofs/run.sh`.
The durable session smoke passed on the isolated Linux candidate checkout.
The Linux-native `nix flake check --print-build-logs` passed, including package build, formatting, and installed CLI checks. Nix reported only the expected incompatible systems `aarch64-darwin` and `aarch64-linux` as omitted.

On the isolated candidate checkout, the four new proof modules for resource options, queue admission/FIFO, deadlines, and resource accounting also passed `--verdict` under the same Linux devShell.

Public cursor memory smoke, one thread:

| Entries | Open RSS | Scan RSS | SST |
| ---: | ---: | ---: | ---: |
| 16,000 | 14,184,448 B | 14,397,440 B | 464,172 B |
| 64,000 | 32,133,120 B | 32,264,192 B | 1,856,272 B |

The 64,000-entry case stays below the 33,554,432 B cap, and scanning 64 entries adds 131,072 B, below the 4,194,304 B increment limit.

The two-thread repeat also passed:

| Entries | Open RSS | Scan RSS | SST |
| ---: | ---: | ---: | ---: |
| 16,000 | 14,397,440 B | 14,368,768 B | 464,172 B |
| 64,000 | 32,002,048 B | 32,002,048 B | 1,856,272 B |

All four Linux measurements remain under the RSS cap; the largest scan increment is 212,992 B, below the 4,194,304 B limit.

## macOS

The local host runs macOS 26.6.2 / Darwin 25.6.0 arm64, with 12 logical CPUs and 24 GiB RAM. The data volume has 92 GiB free. `nix flake check --print-build-logs` and the explicit `aarch64-darwin.installation` check passed.

The refactored worktree proof suite passed `87/87`, with no failures or timeouts. The durable session smoke passed.

Public cursor memory smoke, one thread:

| Entries | Open RSS | Scan RSS | SST |
| ---: | ---: | ---: | ---: |
| 16,000 | 11,845,632 B | 12,042,240 B | 464,172 B |
| 64,000 | 30,900,224 B | 31,064,064 B | 1,856,272 B |

## 0.6 implementation checkpoint

After the baseline runs, the candidate adds validated resource defaults, applies retained-root/snapshot/global and per-snapshot cursor limits in the owner, rejects remote payload declarations above the configured 16 MiB before payload reads, bounds oversized responses before encoding, and waits for listener readiness through `poll` before nonblocking `accept`. C returns raw POSIX readiness flags; Bend classifies them. Request reading and dispatch remain synchronous and serial, so this is not the completed reactor or queue integration.

The current candidate classifies `EINTR`, Linux `EAGAIN`, and Darwin `EWOULDBLOCK` as transient socket outcomes; the owner returns to listener polling after transient `accept` or `poll` failures. Its laws cover the platform errno values and connection-capacity boundaries.

Before the errno-preserving `Transient{code}` extension, the full formal suite passed on macOS and Lenovo with `87/87`, `FAIL=0`, and `TIMEOUT=0`. On the current source, macOS passed the focused `UnixSocketPolicyProof`, both the real-owner frame-limit and coordinator socket integration smokes, and `nix flake check --print-build-logs`. Lenovo passed the focused current `UnixSocketPolicyProof`, both owner socket smokes, and Linux-native `nix flake check --print-build-logs`. The earlier durable session smoke also passed on Lenovo. The full formal suite should be rerun on Lenovo after the errno payload change before final acceptance.

This is a partial implementation record, not the final 0.6 acceptance report and not evidence that cross-platform release readiness is complete.
