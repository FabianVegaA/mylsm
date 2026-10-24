When working with Bend:

- Always use the latest Bend release (`bend update`); record it in `tools/toolchain.json` and revalidate gates on every toolchain bump.
- Run `bend guide` to learn or refresh Bend syntax and proof conventions.
- Keep formal laws in `laws/*.bend`, grouped by domain.
- Keep witnesses in the matching `proofs/*Proof.bend` module. Each proof module must import its law module as `Laws` and only the dependencies its witnesses require.
- Prioritize formal verification over test-driven development: state the pure contract, add laws and witnesses for it, then implement it. Use runtime tests for host effects, integration behavior, and properties outside Bend's proof boundary; they complement formal evidence rather than organize the work.
- Do not bypass or weaken automated checks to make a change pass. Suppress a finding only for a false positive and with the user's approval.
- Never use `@unsafe` in laws, witnesses, or code justified by them.
- Keep Bash/C/JS effects to the smallest irreducible host operation. Put policy, environment interpretation, branching, validation, and data transformation in Bend, and add laws plus witnesses for pure decisions when practical.
- Prefer pure functions, isolated effects, and data structures suited to their access patterns. Minimize work, memory use, unnecessary copying, and shared mutable state; allow encapsulated local mutation when simpler or more efficient. Parallelize independent code and proof checks whenever possible and semantically sound. Introduce runtime parallelism only when representative benchmarks justify its overhead.
- Distinguish quantified theorems over open inputs from closed regression fixtures. Closed fixtures are executable evidence for concrete cases, not general proofs.
- Preserve trust-root comments and explicit formal limitations; do not imply that Bend Base primitives, host IO, or empirically fuzzed behavior have been proved when they have not.
- Generate Superpowers design documents and implementation plans locally in `docs/superpowers/`; do not add them to Git.
