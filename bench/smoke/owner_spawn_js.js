const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const { spawn } = require("node:child_process");

const effects = new Map();
const context = {
  Bun: {
    spawn(options) {
      assert.equal(options.cmd[0], "/usr/bin/true");
      assert.deepEqual(Array.from(options.cmd.slice(1)),
        ["argument with spaces", "; no shell"]);
      assert.equal(options.stdin, "ignore");
      assert.equal(options.stdout, "ignore");
      assert.equal(options.stderr, "ignore");
      return spawn(options.cmd[0], options.cmd.slice(1), {
        shell: false,
        stdio: "ignore",
      });
    },
  },
  CID: (name) => name,
  Con: "Con",
  io_eff: (_name, operation) => effects.set("operation", operation),
  io_done: (value) => ({ value }),
  io_fail: (code) => ({ error: code }),
};
vm.runInNewContext(fs.readFileSync(process.argv[2], "utf8"), context);

const argv = {
  $: "Con",
  head: "/usr/bin/true",
  tail: {
    $: "Con",
    head: "argument with spaces",
    tail: { $: "Con", head: "; no shell", tail: { $: "Nil" } },
  },
};
const result = effects.get("operation")(argv);
assert.equal(typeof result.value, "number");
assert.ok(result.value > 0);
process.stdout.write("OWNER_SPAWN_JS_BOUNDARY_PASSED\n");
