#!/usr/bin/env node

import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = mkdtempSync(join(tmpdir(), "superbrowky-image-fixture-"));
const script = fileURLToPath(
  new URL("../skills/psi-optimize/scripts/compress-images.mjs", import.meta.url),
);

function fail(message, result) {
  const detail = result
    ? `\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`
    : "";
  throw new Error(`${message}${detail}`);
}

function write(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, value);
}

function run(...args) {
  return spawnSync(process.execPath, [script, ...args], {
    cwd: root,
    encoding: "utf8",
  });
}

try {
  write(
    join(root, "node_modules/sharp/index.js"),
    `module.exports = function () {
      const pipeline = {
        metadata: async () => ({ width: 100, height: 100 }),
        resize: () => pipeline,
        avif: () => pipeline,
        webp: () => pipeline,
        png: () => pipeline,
        jpeg: () => pipeline,
        toBuffer: async () => Buffer.from("tiny")
      };
      return pipeline;
    };\n`,
  );

  const source = join(root, "assets/hero.png");
  const sibling = join(root, "assets/hero.webp");
  write(source, Buffer.alloc(100, 1));
  write(sibling, "HAND_AUTHORED");

  const conflictSource = join(root, "assets/conflict.png");
  const conflictSibling = join(root, "assets/conflict.webp");
  write(conflictSource, Buffer.alloc(100, 4));
  for (const conflictArgs of [
    ["--dry", "--apply"],
    ["--apply", "--dry"],
  ]) {
    const conflict = run(
      ...conflictArgs,
      "--emit-webp",
      "--min-bytes",
      "0",
      conflictSource,
    );
    if (conflict.status !== 2) fail("conflicting write-mode flags were accepted", conflict);
    if (existsSync(conflictSibling)) {
      fail("conflicting write-mode flags created a sibling", conflict);
    }
  }

  const preserve = run("--apply", "--emit-webp", "--min-bytes", "0", source);
  if (preserve.status !== 0) fail("default sibling-preservation run failed", preserve);
  if (readFileSync(sibling, "utf8") !== "HAND_AUTHORED") {
    fail("existing sibling was overwritten without explicit authority", preserve);
  }
  if (!preserve.stdout.includes("skip (sibling exists)")) {
    fail("existing-sibling refusal was not reported", preserve);
  }

  const overwrite = run(
    "--apply",
    "--emit-webp",
    "--overwrite-existing",
    "--min-bytes",
    "0",
    source,
  );
  if (overwrite.status !== 0) fail("explicit sibling-overwrite run failed", overwrite);
  if (readFileSync(sibling, "utf8") !== "tiny") {
    fail("explicit smaller sibling was not committed", overwrite);
  }

  const selected = join(root, "selected");
  const outside = join(root, "outside");
  write(join(selected, "inside.png"), Buffer.alloc(100, 2));
  write(join(outside, "outside.png"), Buffer.alloc(100, 3));
  symlinkSync(outside, join(selected, "linked-outside"), "dir");

  const bounded = run("--apply", "--emit-webp", "--min-bytes", "0", selected);
  if (bounded.status !== 0) fail("bounded directory run failed", bounded);
  try {
    readFileSync(join(outside, "outside.webp"));
    fail("walker followed a symlink outside the selected root", bounded);
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
  if (!bounded.stderr.includes("SKIP (symbolic link)")) {
    fail("symlink skip was not reported", bounded);
  }

  console.log("PASS: image helper preserves siblings and selected-root boundaries");
} finally {
  rmSync(root, { recursive: true, force: true });
}
