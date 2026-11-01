# MyLSM

## Purpose

Build the fastest and safest possible LSM key-value database. The goal is to deliver
leading performance and confidence in data integrity for demanding production
applications.

Bend and formal verification are central tools for that ambition: expressing precise
contracts, proving critical engine properties, and using hardware effectively through
efficient algorithms. Competitiveness must rest on explicit guarantees, reproducible
measurements, and reliable behavior under failure.

## Users and needs

MyLSM is intended for developers and teams that need an ordered storage engine for
applications, services, and infrastructure with demanding latency, throughput, and
durability requirements.

Users need to preserve acknowledged data, query consistent views, recover service
after a failure, and keep memory, CPU, and disk costs predictable. They must be able
to integrate and operate the engine with a clear understanding of its guarantees,
limits, and failure modes.

## What success means

- **Sustained competitive performance.** Pursue the lowest latency and highest throughput
  possible for reads, writes, batches, and scans, including recovery, flush, and
  compaction costs. Evaluate latency percentiles and sustained mixed workloads with
  datasets larger than available memory.
- **Data safety.** Preserve acknowledged writes, batch atomicity, and read ordering and
  consistency. Detect corruption, reject invalid inputs, and maintain a defined
  recovery path after process or storage failures.
- **Verifiable correctness.** Specify and prove critical invariants. Formal proofs,
  integration checks, and fault injection must provide complementary evidence about
  the engine's actual behavior.
- **Resource efficiency.** Reduce read and write amplification, memory use, copying,
  and maintenance work. Maintain limits and admission mechanisms that make behavior
  under load predictable.
- **Reliable operation.** Provide actionable errors, observability, and safe procedures
  for backup, restore, migration, and format upgrades.

## Design criteria

Measure speed under the durability and consistency guarantees the consumer receives.
A competitive comparison must use equivalent guarantees, the same workload, and
comparable hardware and storage conditions. Retain samples, configuration, revision,
and methodology so results can be reproduced.

Optimize the complete operation path: data structures, codecs, IO, concurrency, and
maintenance. Use the native capabilities of Bend and the hardware when they reduce
total cost and improve relevant workloads. Every optimization must preserve engine
invariants and demonstrate its benefit.

Ownership and lifetimes of handles, readers, buffers, and files must be explicit.
The cost of retained snapshots and cursors is part of the system's resource budget.
Saturation must have a defined, observable response.

When a commit outcome is uncertain, communicate that uncertainty and allow it to be
resolved before repeating a mutation. File and format publication must preserve
recoverability and prevent a failed operation from destroying valid data.

Formal guarantees must state their assumptions and trust boundary. Dependencies,
the runtime, compiler, filesystem, and host effects each need evidence appropriate
to their role in the system.

## Engine capabilities

The product's core is durable, ordered storage of binary keys and values, with a
strict UTF-8 interface, point operations, atomic batches, range and prefix scans,
snapshots, and storage maintenance.

Coordination between local processes, consistent backups, validated restoration,
and explicit format evolution are part of the reliability the product must offer.
Interfaces and their contracts are documented in [docs/features](docs/features/).

## Current maturity

Version 0.6.0.0 is accepted for release on Apple Silicon macOS. Linux x86-64 is
partially verified, with outstanding validation tracked for 0.6.0.1. This release
does not promise production stability or future format compatibility. Maturity is
established through fulfilled contracts, passing gates, and reproducible comparisons
with reference engines.

Current limits and outstanding work are documented by feature. The
[README](README.md) explains how to use the checkout, and the
[acceptance report](bench/results/mylsm-0.6.0.0-acceptance.md) defines the scope of
the evidence recorded so far, including the known write-performance regression.
This document sets the direction for evaluating development decisions and priorities.
