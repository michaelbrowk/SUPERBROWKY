#!/usr/bin/env node
// SUPERBROWKY v4.1: a deterministic, guidance-only Impeccable derivative.
// Called only on a validated staging directory, before hashing or live writes.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const IMPECCABLE_REF = 'd41d9860b0094dcb68030657da63461212835aaa';
export const CRAFT_REFERENCES = [
  'adapt.md', 'adapt.native.md', 'android.md', 'bolder.md', 'clarify.md',
  'colorize.md', 'craft-floor.md', 'critique-rubric.md', 'delight.md',
  'distill.md', 'extract.md', 'harden.md', 'ios.md', 'mode-operate.md',
  'mode-persuade.md', 'mode-read.md', 'onboard.md', 'operate.md',
  'optimize.md', 'overdrive.md', 'quieter.md', 'shape.md',
];
const OMITTED_PLAYBOOKS = new Set([
  'animate.md', 'critique.md', 'init.md', 'live.md', 'new-work.md',
]);
const provenanceNames = new Set(['LICENSE', 'LICENSE.md', 'NOTICE', 'NOTICE.md']);
const portableNotice = '> SUPERBROWKY adaptation v2: use this craft reference within the\n'
  + '> [portable workflow](../PORTABLE.md). The user\'s brief, existing system,\n'
  + '> authorization and available tools outrank upstream stylistic defaults.\n\n';

function inspectTree(dir) {
  if (!fs.lstatSync(dir).isDirectory() || fs.lstatSync(dir).isSymbolicLink()) {
    throw new Error('staging directory must be a real directory');
  }
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`prohibited symlink: ${entry.name}`);
    if (entry.isDirectory()) inspectTree(file);
    else if (!entry.isFile()) throw new Error(`unsupported file type: ${entry.name}`);
  }
}

export function adaptImpeccable(stageDirectory, ref, kitRoot) {
  if (ref !== IMPECCABLE_REF) throw new Error('Impeccable pin changed; review the portable adaptation first');
  const stage = path.resolve(stageDirectory);
  inspectTree(stage);
  const original = fs.readFileSync(path.join(stage, 'SKILL.md'), 'utf8').replace(/\r\n?/g, '\n');
  if (!original.startsWith('---\n') || !/^name: impeccable$/m.test(original)
      || !/^(?:  )?version: 4\.9\.2$/m.test(original) || !original.includes('## Setup')) {
    throw new Error('unexpected upstream Impeccable 4.9.2 entrypoint');
  }
  const overlay = fs.readFileSync(path.join(kitRoot, 'overlays/impeccable-portable.md'), 'utf8');
  const workflow = fs.readFileSync(path.join(kitRoot, 'overlays/impeccable-workflow.md'), 'utf8');
  if (!overlay.startsWith('## SUPERBROWKY portable contract\n') || !workflow.includes(IMPECCABLE_REF)) {
    throw new Error('portable guidance is missing or references another source');
  }
  const references = new Map();
  for (const name of CRAFT_REFERENCES) {
    let content = fs.readFileSync(path.join(stage, 'reference', name), 'utf8').replace(/\r\n?/g, '\n');
    // Keep craft, but remove the context-engine framing and engine handoffs.
    content = content.replace(/^`impeccable concept-seed[^\n]*?MODE RULES block\. /gm, '');
    content = content.replace(/(?:\$|\/)impeccable polish\b/g, 'the portable final verification pass');
    content = content.replace(/`impeccable init`/g, 'the project context authoring flow');
    content = content.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (match, label, destination) => {
      if (/^(?:https?:|mailto:|#)/.test(destination)) return match;
      const file = destination.split('#')[0];
      if (CRAFT_REFERENCES.includes(file)) return match;
      if (OMITTED_PLAYBOOKS.has(file)) return `[${label} — portable workflow](../PORTABLE.md)`;
      throw new Error(`unreviewed local link in ${name}: ${destination}`);
    });
    if (/(?:scripts\/|\.agents\/skills|\.claude\/skills|npx impeccable|impeccable context|impeccable concept-seed|impeccable_)/.test(content)) {
      throw new Error(`engine-dependent content remains in ${name}`);
    }
    references.set(name, portableNotice + content);
  }
  // Validate the full transform before pruning anything, even in staging.
  for (const entry of fs.readdirSync(stage)) {
    if (!provenanceNames.has(entry)) fs.rmSync(path.join(stage, entry), { recursive: true, force: true });
  }
  fs.mkdirSync(path.join(stage, 'reference'));
  for (const [name, content] of references) fs.writeFileSync(path.join(stage, 'reference', name), content);
  fs.writeFileSync(path.join(stage, 'PORTABLE.md'), workflow);
  fs.writeFileSync(path.join(stage, 'SKILL.md'), [
    '---', 'name: impeccable',
    'description: "Primary frontend design guidance for product UI, landing pages, dashboards, components and native screens: hierarchy, interaction, accessibility, responsive behavior, typography, UX copy and design systems. Use the existing brief and design system. This portable package has no engine, live mode, hooks or automatic setup."',
    'metadata:', '  version: 4.9.2', '  superbrowky-adaptation: "2.0.0"',
    `  upstream-commit: ${IMPECCABLE_REF}`, '---', '', overlay.trimEnd(), '',
  ].join('\n'));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length !== 4) throw new Error('usage: adapt-impeccable.mjs <staged-skill-directory> <pinned-ref>');
    adaptImpeccable(process.argv[2], process.argv[3], path.dirname(path.dirname(fileURLToPath(import.meta.url))));
    console.log('ok: Impeccable 4.9.2 portable guidance (22 craft references; no engine or hooks)');
  } catch (error) {
    console.error(`BLOCKED: ${error.message}`);
    process.exitCode = 1;
  }
}
