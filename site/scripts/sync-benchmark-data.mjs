#!/usr/bin/env node
/**
 * Copy benchmarks/locomo → site/docs/public/benchmark-data
 * and emit site/docs/benchmark/data.json for MDX/SSG import.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const siteRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(siteRoot, '..');
const srcRoot = path.join(repoRoot, 'benchmarks', 'locomo');
const publicRoot = path.join(siteRoot, 'docs', 'public', 'benchmark-data');
const outJson = path.join(siteRoot, 'docs', 'benchmark', 'data.json');

function rmrf(p) {
  fs.rmSync(p, { recursive: true, force: true });
}

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const ent of fs.readdirSync(src, { withFileTypes: true })) {
    const from = path.join(src, ent.name);
    const to = path.join(dest, ent.name);
    if (ent.isDirectory()) {
      copyDir(from, to);
    } else {
      fs.copyFileSync(from, to);
    }
  }
}

if (!fs.existsSync(srcRoot)) {
  console.error(`missing ${srcRoot}`);
  process.exit(1);
}

rmrf(publicRoot);
copyDir(srcRoot, publicRoot);

const latest = JSON.parse(
  fs.readFileSync(path.join(srcRoot, 'latest.json'), 'utf8'),
);
const resultsDir = path.join(srcRoot, 'results');
const results = [];
for (const name of fs.readdirSync(resultsDir).sort()) {
  if (!name.endsWith('.json')) continue;
  const doc = JSON.parse(fs.readFileSync(path.join(resultsDir, name), 'utf8'));
  results.push(doc);
}
// newest first by semver-ish string (version field)
results.sort((a, b) => String(b.version).localeCompare(String(a.version), undefined, { numeric: true }));

const payload = {
  latestVersion: latest.version,
  results,
};

fs.mkdirSync(path.dirname(outJson), { recursive: true });
fs.writeFileSync(outJson, JSON.stringify(payload, null, 2) + '\n');
console.log(
  `synced ${results.length} result(s); latest=${latest.version} → public/benchmark-data + docs/benchmark/data.json`,
);
