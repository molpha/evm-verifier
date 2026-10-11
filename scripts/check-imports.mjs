#!/usr/bin/env node
// Verifies the staged npm package resolves the way both channels need it to.
//
// Three invariants:
//   1. Every import in every packaged file resolves — relative ones to a real file, and
//      `@molpha/evm-verifier/...` ones to a path under the package root.
//   2. Nothing carries a `src/` prefix, and no `src/` directory survives staging: the published
//      layout puts the CONTENTS of src/ at the package root so one import string works on both
//      Foundry and npm.
//   3. The CONSUMER SURFACE has zero external dependencies, checked over its transitive closure.
//      `Verifier.sol` and the crypto libs do import solady, but a consumer never compiles them —
//      only `MolphaTestSigner` pulls them in, and it is Foundry-only by design.
import { readdirSync, statSync, readFileSync, existsSync } from "node:fs";
import { join, dirname, resolve, relative } from "node:path";

const root = resolve(process.argv[2] ?? "npm-dist");
const PKG = "@molpha/evm-verifier/";
const IMPORT_RE = /^\s*import\s+(?:[^"']*?\s+from\s+)?["']([^"']+)["']/gm;

// Everything a consumer is expected to import directly. Their closure must be dependency-free.
const CONSUMER_SURFACE = [
  "consumer/MolphaLib.sol",
  "consumer/MolphaAddresses.sol",
  "interfaces/IVerifier.sol",
  "libs/VerifyCodes.sol",
  "test-utils/MockVerifier.sol",
];
// Permitted only outside the consumer closure (the MolphaTestSigner subtree).
const ALLOWED_EXTERNAL = ["solady/"];

const walk = (d) =>
  readdirSync(d).flatMap((e) => {
    const p = join(d, e);
    return statSync(p).isDirectory() ? walk(p) : p.endsWith(".sol") ? [p] : [];
  });

const importsOf = (file) => {
  const body = readFileSync(file, "utf8");
  return [...body.matchAll(IMPORT_RE)].map(([, spec]) => spec);
};

const resolveSpec = (file, spec) => {
  if (spec.startsWith(".")) return resolve(dirname(file), spec);
  if (spec.startsWith(PKG)) return resolve(root, spec.slice(PKG.length));
  return null; // external
};

const files = walk(root);
const errors = [];
if (files.length === 0) errors.push(`no .sol files under ${root} — did pack-npm.sh run?`);

// (1) + (2)
for (const file of files) {
  const rel = relative(root, file);
  for (const spec of importsOf(file)) {
    const target = resolveSpec(file, spec);
    if (target === null) {
      if (!ALLOWED_EXTERNAL.some((a) => spec.startsWith(a))) {
        errors.push(`${rel}: unexpected external dependency "${spec}"`);
      }
      continue;
    }
    if (!existsSync(target)) errors.push(`${rel}: unresolved import "${spec}" -> ${relative(root, target)}`);
  }
  if (/["']@molpha\/evm-verifier\/src\//.test(readFileSync(file, "utf8"))) {
    errors.push(`${rel}: import carries a src/ prefix; src/ contents must sit at the package root`);
  }
}
if (existsSync(join(root, "src"))) {
  errors.push("npm-dist/src exists — the staged package must have src/ CONTENTS at its root");
}

// (3) transitive closure of the consumer surface must be free of external imports
const seen = new Set();
const queue = [];
for (const entry of CONSUMER_SURFACE) {
  const p = join(root, entry);
  if (!existsSync(p)) errors.push(`consumer surface file missing from package: ${entry}`);
  else queue.push(p);
}
while (queue.length) {
  const file = queue.pop();
  if (seen.has(file)) continue;
  seen.add(file);
  for (const spec of importsOf(file)) {
    const target = resolveSpec(file, spec);
    if (target === null) {
      errors.push(`consumer surface must compile with zero external deps: ${relative(root, file)} imports "${spec}"`);
      continue;
    }
    if (existsSync(target)) queue.push(target);
  }
}

if (errors.length) {
  console.error("import check FAILED:");
  for (const e of errors) console.error("  " + e);
  process.exit(1);
}
console.log(`import check OK`);
console.log(`  ${files.length} packaged files, all imports resolve inside the package`);
console.log(`  consumer surface closure (${seen.size} files) has zero external dependencies`);
