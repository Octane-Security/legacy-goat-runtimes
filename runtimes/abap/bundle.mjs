// Bundle the transpiled open-abap output (./output/*.mjs) into one loadable module,
// ./bundle-core.mjs, that sets globalThis.abap and registers every class.
//
// Why this is needed: the abaplint transpiler emits one .mjs per object with NO
// import/export. Each declares `class NAME [extends SUPER] {...}` at column 0 and
// references other objects' classes by BARE name, then self-registers with
// `abap.Classes['NAME'] = NAME`. So the class names must be GLOBAL, while file-local
// `const pool` (in *.type.mjs) must stay isolated. And the generated _init.mjs lists
// imports ALPHABETICALLY, not by inheritance, so a subclass would be evaluated before
// its superclass exists.
//
// Fix: (1) wrap each file body in an async IIFE (isolates const/let, allows the
// top-level await some files use) and promote every top-level class to a global:
// `class NAME` -> `var NAME = globalThis.NAME = class NAME`. (2) TOPOLOGICALLY SORT
// files so a file defining a superclass is emitted before any file that `extends` it.
// Supers not defined by any file (runtime-provided) impose no ordering.
import { readFileSync, writeFileSync, readdirSync } from "node:fs";

const OUT = "output";
const files = readdirSync(OUT).filter(f => f.endsWith(".mjs") && !f.startsWith("_") && f !== "init.mjs");

const info = new Map();      // file -> { defines:Set, supers:Set, src }
const definedBy = new Map(); // className -> file
for (const f of files) {
  const src = readFileSync(`${OUT}/${f}`, "utf8");
  const defines = new Set([...src.matchAll(/^class (\w+)/gm)].map(m => m[1]));
  const supers = new Set([...src.matchAll(/^class \w+ extends (\w+)/gm)].map(m => m[1]));
  for (const c of defines) definedBy.set(c, f);
  info.set(f, { defines, supers, src });
}

const deps = new Map();
for (const [f, { supers }] of info) {
  const d = new Set();
  for (const s of supers) {
    const owner = definedBy.get(s);
    if (owner && owner !== f) d.add(owner);
  }
  deps.set(f, d);
}

// Kahn topological sort; alphabetical among ready nodes for stable output.
const order = [];
const remaining = new Set(files);
const emitted = new Set();
while (remaining.size) {
  const ready = [...remaining].filter(f => [...deps.get(f)].every(d => emitted.has(d))).sort();
  if (ready.length === 0) { order.push(...[...remaining].sort()); break; } // cycle guard
  for (const f of ready) { order.push(f); emitted.add(f); remaining.delete(f); }
}

const parts = [
  'import runtime from "@abaplint/runtime";',
  "globalThis.abap = new runtime.ABAP();",
  "",
];
for (const f of order) {
  let src = info.get(f).src.replace(/^\s*import\b.*$/gm, "").replace(/^\s*export\b.*$/gm, "");
  src = src.replace(/^class (\w+)/gm, "var $1 = globalThis.$1 = class $1");
  parts.push(`// ---- ${f} ----`, "await (async function () {", src.trimEnd(), "})();", "");
}
writeFileSync("bundle-core.mjs", parts.join("\n"));
console.log(`[abap] bundled ${order.length} modules -> bundle-core.mjs`);
