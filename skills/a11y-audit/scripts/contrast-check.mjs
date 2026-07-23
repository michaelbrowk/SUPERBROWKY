#!/usr/bin/env node
// contrast-check.mjs — WCAG 2.1 contrast-ratio checker. Pure Node, zero deps.
//
// The fastest a11y win is almost always text contrast: low-contrast body copy,
// placeholder-grey labels, white-on-pastel buttons. This computes the real
// ratio and the AA/AAA verdict so you stop eyeballing it.
//
// Usage:
//   # one or more foreground/background pairs ("fg:bg")
//   node contrast-check.mjs "#6b7280:#ffffff" "rgb(17,24,39):#fff"
//
//   # scan a CSS/Tailwind-config file: extracts color custom properties and
//   # checks every foreground-ish token against every background-ish token
//   # (named by heuristic: fg/text/ink/foreground vs bg/surface/background/paper)
//   node contrast-check.mjs --css app/globals.css
//
// Flags:
//   --large            judge against large-text thresholds (3:1 AA / 4.5:1 AAA)
//   --threshold <n>    custom AA pass line (default 4.5, or 3 with --large)
//   --json             machine-readable output
//
// Exit code is non-zero if any pair fails the AA threshold — wire it into CI.

import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const opt = { large: false, threshold: null, json: false, css: null, pairs: [] };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--large") opt.large = true;
  else if (a === "--json") opt.json = true;
  else if (a === "--threshold") {
    const raw = args[++i];
    if (raw === undefined) fail("--threshold needs a number");
    opt.threshold = Number(raw);
  } else if (a === "--css") {
    const raw = args[++i];
    if (raw === undefined) fail("--css needs a file");
    opt.css = raw;
  }
  else if (a.startsWith("--")) fail(`unknown flag: ${a}`);
  else opt.pairs.push(a);
}
if (opt.threshold !== null && (!Number.isFinite(opt.threshold) || opt.threshold <= 0 || opt.threshold > 21)) {
  fail("--threshold must be a finite number greater than 0 and at most 21");
}
if (opt.css && opt.pairs.length) {
  fail("use either --css or explicit fg:bg pairs, not both");
}
if (!opt.css && opt.pairs.length === 0) {
  fail("provide at least one fg:bg pair or --css <file>");
}
const AA = opt.threshold ?? (opt.large ? 3 : 4.5);
const AAA = opt.large ? 4.5 : 7;

function fail(msg) {
  console.error(`contrast-check: ${msg}`);
  process.exit(2);
}

// --- color parsing → [r,g,b] 0..255 ---
// Alpha colors need a known backdrop before their contrast can be computed.
// Reject them instead of silently treating translucent pixels as opaque.
function parseColor(raw) {
  const s = raw.trim().toLowerCase();
  let m;
  if (/^#[0-9a-f]{4}$|^#[0-9a-f]{8}$/.test(s) || /^rgba\(/.test(s)) {
    fail(`alpha color "${raw}" needs compositing against its real backdrop first`);
  }
  if ((m = s.match(/^#([0-9a-f]{3})$/))) {
    const h = m[1];
    return [h[0], h[1], h[2]].map((c) => parseInt(c + c, 16));
  }
  if ((m = s.match(/^#([0-9a-f]{6})$/))) {
    const h = m[1];
    return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
  }
  if ((m = s.match(/^rgb\(([^)]+)\)$/))) {
    if (m[1].includes("/")) {
      fail(`alpha color "${raw}" needs compositing against its real backdrop first`);
    }
    const parts = m[1].trim().split(/[ ,]+/).filter(Boolean);
    if (parts.length !== 3) return null;
    const channels = parts.map((part) => {
      if (/^(?:\d+(?:\.\d+)?|\.\d+)%$/.test(part)) {
        const percent = Number.parseFloat(part);
        return percent >= 0 && percent <= 100
          ? Math.round((percent / 100) * 255)
          : null;
      }
      if (!/^(?:\d+(?:\.\d+)?|\.\d+)$/.test(part)) return null;
      const value = Number.parseFloat(part);
      return value >= 0 && value <= 255 ? Math.round(value) : null;
    });
    return channels.every((channel) => channel !== null) ? channels : null;
  }
  return null;
}

// WCAG relative luminance + contrast ratio
function luminance([r, g, b]) {
  const lin = [r, g, b].map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
}
function ratio(fg, bg) {
  const a = luminance(fg) + 0.05;
  const b = luminance(bg) + 0.05;
  return (Math.max(a, b) / Math.min(a, b));
}

function buildPairs() {
  if (opt.css) return pairsFromCss(opt.css);
  return opt.pairs.map((tok) => {
    const parts = tok.split(":");
    if (parts.length !== 2 || !parts[0] || !parts[1]) {
      fail(`bad pair "${tok}" — expected exactly fg:bg`);
    }
    const [fg, bg] = parts;
    return { label: tok, fg: must(fg), bg: must(bg) };
  });
}
function must(raw) {
  const c = parseColor(raw);
  if (!c) fail(`can't parse color "${raw}"`);
  return c;
}

// Extract `--name: <color>;` declarations, then pair foreground-ish names with
// background-ish names. Heuristic, but catches the common token-system mistakes.
function pairsFromCss(file) {
  const css = readFileSync(file, "utf8");
  const vars = {};
  const re = /--([\w-]+)\s*:\s*([^;]+);/g;
  let m;
  while ((m = re.exec(css))) {
    const val = m[2].trim();
    const c = parseColor(val);
    if (c) vars[m[1]] = c;
  }
  const names = Object.keys(vars);
  const isFg = (n) => /(^|-)(fg|text|ink|foreground|content|label)(-|$)/.test(n);
  const isBg = (n) => /(^|-)(bg|surface|background|paper|card|base)(-|$)/.test(n);
  const fgs = names.filter(isFg);
  const bgs = names.filter(isBg);
  if (!fgs.length || !bgs.length) {
    fail(
      `found ${names.length} color tokens but couldn't classify fg/bg by name ` +
        `(need tokens like --text-*/--fg-* and --bg-*/--surface-*). ` +
        `Check explicit pairs instead.`,
    );
  }
  const out = [];
  for (const f of fgs) for (const b of bgs) out.push({ label: `--${f} on --${b}`, fg: vars[f], bg: vars[b] });
  return out;
}

const results = buildPairs().map((p) => {
  const r = ratio(p.fg, p.bg);
  return {
    label: p.label,
    ratio: Math.round(r * 100) / 100,
    aa: r >= AA,
    aaa: r >= AAA,
  };
});

if (opt.json) {
  console.log(JSON.stringify({ aa: AA, aaa: AAA, large: opt.large, results }, null, 2));
} else {
  const tier = opt.large ? "large text" : "normal text";
  console.log(`WCAG contrast (${tier}) — AA ≥ ${AA}:1, AAA ≥ ${AAA}:1\n`);
  for (const r of results) {
    const mark = r.aa ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m";
    const tags = [r.aaa ? "AAA" : r.aa ? "AA" : "FAIL"].join("");
    console.log(`  ${mark} ${String(r.ratio).padStart(6)}:1  ${tags.padEnd(4)}  ${r.label}`);
  }
  const failed = results.filter((r) => !r.aa).length;
  console.log(
    `\n${results.length - failed}/${results.length} pass AA` +
      (failed ? ` — \x1b[31m${failed} fail\x1b[0m` : ""),
  );
}

process.exit(results.some((r) => !r.aa) ? 1 : 0);
