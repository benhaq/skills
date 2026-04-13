#!/usr/bin/env bash
set -euo pipefail

# Install @effect/language-service
bun add --dev @effect/language-service

# Add plugin to tsconfig.json if not present
bun -e "
const fs = require('fs');
const tc = JSON.parse(fs.readFileSync('tsconfig.json','utf8'));
tc.compilerOptions = tc.compilerOptions || {};
tc.compilerOptions.plugins = tc.compilerOptions.plugins || [];
if (!tc.compilerOptions.plugins.some(p => p.name === '@effect/language-service')) {
  tc.compilerOptions.plugins.push({ name: '@effect/language-service' });
  fs.writeFileSync('tsconfig.json', JSON.stringify(tc, null, 2) + '\n');
  console.log('Added @effect/language-service plugin to tsconfig.json');
} else {
  console.log('Plugin already configured in tsconfig.json');
}
"

# Patch tsc for build-time Effect diagnostics
bunx @effect/language-service patch
echo "Patched tsc for build-time Effect diagnostics"

# Add prepare script to package.json if not present
bun -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json','utf8'));
pkg.scripts = pkg.scripts || {};
if (!pkg.scripts.prepare || !pkg.scripts.prepare.includes('effect-language-service')) {
  pkg.scripts.prepare = pkg.scripts.prepare
    ? pkg.scripts.prepare + ' && bunx @effect/language-service patch'
    : 'bunx @effect/language-service patch';
  fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
  console.log('Added effect-language-service patch to prepare script');
} else {
  console.log('prepare script already includes patch');
}
"

echo "Setup complete. Restart your editor to activate the language service."
