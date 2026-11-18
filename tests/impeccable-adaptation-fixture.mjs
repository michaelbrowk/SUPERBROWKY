#!/usr/bin/env node
// Offline behavior checks for the shared staging transform, not an upstream
// installation test. The lifecycle suite also transforms the actual pinned tar.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { adaptImpeccable, CRAFT_REFERENCES, IMPECCABLE_REF } from '../scripts/adapt-impeccable.mjs';

const kitRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'superbrowky-adaptation-'));
function fixture(name, topLevelVersion = false) {
  const stage = path.join(testRoot, name);
  fs.mkdirSync(path.join(stage, 'reference'), { recursive: true });
  fs.mkdirSync(path.join(stage, 'scripts'));
  fs.mkdirSync(path.join(stage, 'agents'));
  fs.writeFileSync(path.join(stage, 'SKILL.md'), '---\nname: impeccable\n'
    + (topLevelVersion ? 'version: 4.9.2\n' : 'metadata:\n  version: 4.9.2\n')
    + 'allowed-tools: Bash(unsafe-command)\n---\n## Setup\nRun the upstream engine.\n');
  for (const ref of CRAFT_REFERENCES) fs.writeFileSync(path.join(stage, 'reference', ref), `# ${ref}\n\nKeep the craft.\n`);
  fs.writeFileSync(path.join(stage, 'reference', 'shape.md'), '# Shape\n\n[new work](new-work.md)\n');
  fs.writeFileSync(path.join(stage, 'reference', 'bolder.md'), (topLevelVersion
    ? '# Claude-specific craft wording\n\nWhen done, hand off to `/impeccable polish`.\n'
    : '# Codex-specific craft wording\n\nWhen done, hand off to `$impeccable polish`.\n'));
  fs.writeFileSync(path.join(stage, 'reference', 'mode-read.md'), '`impeccable concept-seed --mode read` prints the MODE RULES block. On a Read surface, preserve the document.\n');
  fs.writeFileSync(path.join(stage, 'scripts', 'impeccable'), '#!/bin/sh\nexit 99\n');
  fs.writeFileSync(path.join(stage, 'agents', 'unrequested.toml'), 'name = "unrequested"\n');
  fs.writeFileSync(path.join(stage, 'LICENSE'), 'fixture license bytes\n');
  fs.writeFileSync(path.join(stage, 'NOTICE.md'), 'fixture attribution bytes\n');
  return stage;
}
function tree(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))
    .flatMap(e => e.isDirectory() ? tree(path.join(dir, e.name)).map(x => [e.name + '/' + x[0], x[1]])
      : [[e.name, fs.readFileSync(path.join(dir, e.name), 'utf8')]]);
}
try {
  const codex = fixture('codex');
  const claude = fixture('claude', true);
  adaptImpeccable(codex, IMPECCABLE_REF, kitRoot);
  adaptImpeccable(claude, IMPECCABLE_REF, kitRoot);
  assert.deepEqual(tree(codex).map(([name]) => name), tree(claude).map(([name]) => name),
    'platform adapters retain the same allowed file set, not identical upstream prose');
  assert.match(fs.readFileSync(path.join(codex, 'reference/bolder.md'), 'utf8'), /Codex-specific craft wording/);
  assert.match(fs.readFileSync(path.join(claude, 'reference/bolder.md'), 'utf8'), /Claude-specific craft wording/);
  for (const stage of [codex, claude]) {
    assert.match(fs.readFileSync(path.join(stage, 'reference/bolder.md'), 'utf8'), /portable final verification pass/);
    for (const [, text] of tree(stage)) assert.doesNotMatch(text, /(?:\$|\/)impeccable polish\b/);
  }
  assert.equal(fs.existsSync(path.join(codex, 'scripts')), false);
  assert.equal(fs.existsSync(path.join(codex, 'agents')), false);
  assert.equal(fs.readFileSync(path.join(codex, 'LICENSE'), 'utf8'), 'fixture license bytes\n');
  assert.equal(fs.readFileSync(path.join(codex, 'NOTICE.md'), 'utf8'), 'fixture attribution bytes\n');
  assert.equal(fs.readdirSync(path.join(codex, 'reference')).length, CRAFT_REFERENCES.length);
  assert.match(fs.readFileSync(path.join(codex, 'reference/shape.md'), 'utf8'), /\.\.\/PORTABLE\.md/);
  assert.doesNotMatch(fs.readFileSync(path.join(codex, 'SKILL.md'), 'utf8'), /allowed-tools|^hooks:/m);
  assert.match(fs.readFileSync(path.join(codex, 'SKILL.md'), 'utf8'), /\*\*not included\*\*/);

  const wrongPin = fixture('wrong-pin');
  const beforePin = tree(wrongPin);
  assert.throws(() => adaptImpeccable(wrongPin, '0'.repeat(40), kitRoot), /pin changed/);
  assert.deepEqual(tree(wrongPin), beforePin, 'wrong pin must fail before pruning');

  const newLink = fixture('new-link');
  fs.appendFileSync(path.join(newLink, 'reference/shape.md'), '[new runtime](unreviewed.md)\n');
  const beforeLink = tree(newLink);
  assert.throws(() => adaptImpeccable(newLink, IMPECCABLE_REF, kitRoot), /unreviewed local link/);
  assert.deepEqual(tree(newLink), beforeLink, 'upstream dependency change must fail before pruning');

  const newCommand = fixture('new-command');
  fs.appendFileSync(path.join(newCommand, 'reference/shape.md'), 'Run scripts/impeccable context\n');
  const beforeCommand = tree(newCommand);
  assert.throws(() => adaptImpeccable(newCommand, IMPECCABLE_REF, kitRoot), /engine-dependent/);
  assert.deepEqual(tree(newCommand), beforeCommand, 'new engine instructions must not be installed');

  const linked = fixture('linked');
  const outside = path.join(testRoot, 'outside');
  fs.mkdirSync(outside);
  fs.writeFileSync(path.join(outside, 'marker'), 'preserve me');
  fs.symlinkSync(outside, path.join(linked, 'unexpected-link'), process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => adaptImpeccable(linked, IMPECCABLE_REF, kitRoot), /symlink/);
  assert.equal(fs.readFileSync(path.join(outside, 'marker'), 'utf8'), 'preserve me');
  assert.ok(fs.existsSync(path.join(linked, 'scripts/impeccable')), 'symlink rejection happens before pruning');
  console.log('PASS: both adapter syntaxes, preserved platform wording, no runtime/hooks/agents, provenance, link closure, fail-before-write and symlink safety');
} finally {
  fs.rmSync(testRoot, { recursive: true, force: true });
}
