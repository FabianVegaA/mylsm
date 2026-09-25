# Bloom Parallel Construction — Design Spec

**Date:** 2026-09-25
**Status:** Approved, implementing
**Scope:** Spike intra-key parallelism first, then few-large-chunks; keep
exactly one variant by measurement, sequential on tie.
**Related:** Phase 3 spec §6/C1, commit b14d9b8 (dropped 64-chunk attempt:
7-9ms vs 2-3ms seq, union overhead dominated).

## 1. Spike 2 — intra-key parallel hashes (baseline)

In `Sstable.bloom_add`, compute both indices in one parallel-let:
```bend
def bloom_add(bloom: Bloom, +key: String) -> Bloom:
  match bloom:
    case Blm{bits, +size}:
      h1 h2 = bhash_n(key, 17, size) bhash_n(key, 257, size)
      Blm{bit_set(h1, bit_set(h2, bits)), size}
```
Zero semantic change (same sets, same order); existing witnesses cover it.
Measures `bloom_construction` in `compaction_bench` before/after. Expected:
likely overhead-dominated; calibrates parallel-let cost on this machine.

## 2. Spike 1 — two large chunks plus one union

Only if spike 2 does not win outright (or as comparison). Split entries
into 2 halves (NOT 64 blocks), build one full-size Bloom per half in
parallel-let, single `bloom_union` at the end; size gate (`count < 2048`
stays sequential). Reintroduce `union_bits`, `bloom_of_chunk`, union and
2-partition agreement laws with witnesses (as dropped, reshaped).
Prior failure mode (64 full-tree unions) is structurally avoided: exactly
one union per build.

## 3. Decision rule and gates

Keep exactly one variant: best `bloom_construction` number with clear
margin (>10%, outside the measured ±1.5% noise). Tie → sequential (YAGNI).
Gates per spike: `bend --check-only`, targeted `bend proofs/*Proof.bend`,
`./proofs/run.sh` 31/31, bolt clean (S001 parked, S002 filtered, S003 over
200 chars), commit with the number matrix. No retrocompat concerns (pure
build path, format unchanged).
