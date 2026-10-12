const fs = require("node:fs");

const marker = process.argv[2];
const descriptor = Number(process.argv[3]);
let state = "closed";
try {
  fs.fstatSync(descriptor);
  state = "inherited";
} catch {}
fs.writeFileSync(marker, state);
