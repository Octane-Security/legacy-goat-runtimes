#!/bin/sh
# Transpiles the mounted ABAP module (open-abap), bundles the output, and serves the
# ICF shim on :8080. Runs entirely in /opt/abap so ESM bare imports (@abaplint/runtime)
# resolve against the image's node_modules (ESM ignores NODE_PATH).
set -e
cd /opt/abap

SRC=/app-src/abap
echo "[abap] staging source from $SRC"
rm -rf src output bundle-core.mjs
mkdir -p src
cp "$SRC"/*.clas.abap src/
cp "$SRC"/*.clas.xml  src/ 2>/dev/null || true

# abaplint config: the transpiler wants strict JSON. Strip block + line comments from
# the app's .jsonc (the [^:] guard leaves URLs like https:// intact).
if [ -f "$SRC/abaplint.jsonc" ]; then
  node -e "const fs=require('fs');let s=fs.readFileSync('$SRC/abaplint.jsonc','utf8');s=s.replace(/\/\*[\s\S]*?\*\//g,'').replace(/(^|[^:])\/\/.*\$/gm,'\$1');fs.writeFileSync('src/abaplint.json',s)"
elif [ -f "$SRC/abaplint.json" ]; then
  cp "$SRC/abaplint.json" src/abaplint.json
else
  echo "[abap] ERROR: no abaplint.json(c) in $SRC" >&2; exit 1
fi

echo "[abap] transpiling ABAP -> JS (open-abap, offline lib /opt/open-abap-core)"
node_modules/.bin/abap_transpile abap_transpile.json

echo "[abap] bundling transpiled output"
node bundle.mjs

echo "[abap] starting ICF shim on :8080"
exec node server.mjs
