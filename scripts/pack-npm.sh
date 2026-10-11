#!/usr/bin/env bash
# Stage the npm package. `files` cannot rewrite paths, and the published layout must place the
# CONTENTS of src/ at the package root so that
#   @molpha/evm-verifier/consumer/MolphaLib.sol
# resolves identically under Hardhat (node_modules/...) and Foundry (lib/evm-verifier/src/...).
# That works because every intra-package import is relative and this copy preserves the tree.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist="$root/npm-dist"

rm -rf "$dist"
mkdir -p "$dist"
cp -R "$root/src/." "$dist/"
cp "$root/LICENSE" "$root/README.md" "$dist/" 2>/dev/null || cp "$root/README.md" "$dist/"
cp "$root/deployments.json" "$dist/"

node -e '
  const fs = require("fs");
  const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  delete p.scripts;
  delete p.devDependencies;
  delete p.private;
  p.files = ["**/*.sol", "deployments.json", "LICENSE", "README.md"];
  fs.writeFileSync(process.argv[2], JSON.stringify(p, null, 2) + "\n");
' "$root/package.json" "$dist/package.json"

echo "staged $dist"
find "$dist" -name '*.sol' | sed "s|$dist/|  |" | sort
