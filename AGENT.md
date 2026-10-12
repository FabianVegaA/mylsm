When working with Bend:

- Always use the latest Bend release (`bend update`); record it in `tools/toolchain.json` and revalidate gates on every toolchain bump.
- Run `bend guide` to learn or refresh Bend syntax and proof conventions.
- Keep formal laws in `laws/*.bend`, grouped by domain.
- Keep witnesses in the matching `proofs/*Proof.bend` module. Each proof module must import its law module as `Laws` and only the dependencies its witnesses require.
- Prioritize formal verification over test-driven development: state the pure contract, add laws and witnesses for it, then implement it. Use runtime tests for host effects, integration behavior, and properties outside Bend's proof boundary; they complement formal evidence rather than organize the work.
- Prefer targeted checks such as `bend proofs/KeysProof.bend` while developing.
- Run `./proofs/run.sh` before committing. A timeout or any failed module is never a green proof result.
- Lint with `../bolt/bin/bolt.bin` (from the repo root: `bolt` over the tree, or named files while developing). Zero errors and zero warnings is the gate, with two width exceptions (house limit is 200, not bolt's 120): filter `S002` lines, and enforce `S003` only on headers longer than 200 chars. Gate commands:
  `../bolt/bin/bolt.bin 2>&1 | grep -v " S002: " | grep -E "error:|warning:"` must print nothing, and recursive app Bend files plus the existing top-level source groups must stay within 200 characters: `awk 'length > 200 {print FILENAME":"FNR}' src/*.bend bench/*.bend laws/*.bend proofs/*.bend mylsm.bend` and `rg --files -0 app -g '*.bend' | xargs -0 awk 'length > 200 {print FILENAME":"FNR}'` must print nothing.
  Fix every remaining finding. Silence a finding with an exact `# noqa: CODE` only when the rule misfires, and only after the user explicitly approves the explanatory comment. Never weaken a rule in `bolt.bend` to make the count drop.
- Never use `@unsafe` in laws, witnesses, or code justified by them.
- Keep Bash/C/JS effects to the smallest irreducible host operation. Put policy, environment interpretation, branching, validation, and data transformation in Bend, and add laws plus witnesses for pure decisions when practical.
- Parallelize code and proof checks whenever possible and semantically sound.
- Distinguish quantified theorems over open inputs from closed regression fixtures. Closed fixtures are executable evidence for concrete cases, not general proofs.
- Preserve trust-root comments and explicit formal limitations; do not imply that Bend Base primitives, host IO, or empirically fuzzed behavior have been proved when they have not.
- Prefer pure functions, isolated effects, and algorithms that expose independent work, such as balanced divide-and-conquer, independent maps, and associative reductions. Choose data structures by access pattern: contiguous arrays for scans, balanced trees for ordered access, and structural sharing for immutable versions. Avoid unnecessary copying and shared mutable state; allow encapsulated local mutation when simpler or more efficient. Keep total work and memory costs low; add parallel execution only when workload and runtime justify its overhead, and verify gains with representative benchmarks.
