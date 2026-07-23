#!/usr/bin/env node
// Reusable image compression walker. Part of the psi-optimize skill.
// Resizes and re-encodes raster images with sharp. Skips files already
// well-compressed and refuses to make anything bigger.
//
// Usage:
//   node compress-images.mjs [options] <path> [<path> ...]
//
// Options:
//   --dry                Audit only — report savings, write nothing (default)
//   --apply              Write the accepted changes
//   --quality N          Quality for lossy encoders (JPEG/WebP). Default 85.
//   --max-width N        Resize if image width > N. Default 2048.
//   --max-height N       Resize if image height > N. Default 2048.
//   --min-bytes N        Skip files smaller than this. Default 20480 (20KB).
//   --emit-webp          Emit `.webp` siblings instead of replacing originals.
//   --emit-avif          Emit `.avif` siblings (~20% smaller than WebP; slower
//                        encode/decode). Good for below-the-fold photos; for the
//                        LCP hero, WebP is the safer bet. Wins over --emit-webp.
//   --overwrite-existing Permit replacing an existing emitted sibling, but only
//                        when the new file is smaller. Off by default.
//   --png-only           Only process PNGs.
//   --jpg-only           Only process JPG/JPEGs.
//   --webp-only          Only process WebPs (re-encode).
//   --palette            Allow palette quantisation for PNGs (lossy but much smaller).
//                        Default OFF — PNGs reencode strictly lossless. Enable only if
//                        you've confirmed the PNGs are flat/UI-style (not photo gradients).
//   --verbose            Print every file examined, even skipped ones.
//
// Requires: `sharp` installed in the target project (pnpm/npm/yarn add -D sharp).

import {
  chmodSync,
  linkSync,
  lstatSync,
  readdirSync,
  realpathSync,
  renameSync,
  unlinkSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { basename, extname, isAbsolute, join, relative, resolve } from "node:path";

const args = process.argv.slice(2);
const paths = [];
let sawDry = false;
let sawApply = false;
const opt = {
  dry: true,
  quality: 85,
  maxWidth: 2048,
  maxHeight: 2048,
  minBytes: 20 * 1024,
  emitWebp: false,
  emitAvif: false,
  overwriteExisting: false,
  pngOnly: false,
  jpgOnly: false,
  webpOnly: false,
  palette: false,
  verbose: false
};

for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--dry") { sawDry = true; opt.dry = true; }
  else if (a === "--apply") { sawApply = true; opt.dry = false; }
  else if (a === "--quality") opt.quality = Number(args[++i]);
  else if (a === "--max-width") opt.maxWidth = Number(args[++i]);
  else if (a === "--max-height") opt.maxHeight = Number(args[++i]);
  else if (a === "--min-bytes") opt.minBytes = Number(args[++i]);
  else if (a === "--emit-webp") opt.emitWebp = true;
  else if (a === "--emit-avif") opt.emitAvif = true;
  else if (a === "--overwrite-existing") opt.overwriteExisting = true;
  else if (a === "--png-only") opt.pngOnly = true;
  else if (a === "--jpg-only") opt.jpgOnly = true;
  else if (a === "--webp-only") opt.webpOnly = true;
  else if (a === "--palette") opt.palette = true;
  else if (a === "--verbose") opt.verbose = true;
  else if (a === "-h" || a === "--help") { printUsageAndExit(0); }
  else if (a.startsWith("--")) { console.error(`Unknown flag: ${a}`); printUsageAndExit(2); }
  else paths.push(a);
}

if (paths.length === 0) {
  console.error("Error: no paths given.");
  printUsageAndExit(2);
}
if (sawDry && sawApply) {
  console.error("Error: --dry and --apply cannot be used together.");
  process.exit(2);
}
for (const [flag, value, minimum, maximum] of [
  ["--quality", opt.quality, 1, 100],
  ["--max-width", opt.maxWidth, 1, Number.MAX_SAFE_INTEGER],
  ["--max-height", opt.maxHeight, 1, Number.MAX_SAFE_INTEGER],
  ["--min-bytes", opt.minBytes, 0, Number.MAX_SAFE_INTEGER],
]) {
  if (!Number.isFinite(value) || value < minimum || value > maximum) {
    console.error(`Error: ${flag} must be a number from ${minimum} to ${maximum}.`);
    process.exit(2);
  }
}
if ([opt.pngOnly, opt.jpgOnly, opt.webpOnly].filter(Boolean).length > 1) {
  console.error("Error: use at most one of --png-only, --jpg-only, or --webp-only.");
  process.exit(2);
}

// Resolve `sharp` from the current working directory's node_modules —
// the script lives in a harness-managed skill directory but must load the
// project's own sharp dependency.
let sharp;
try {
  const { createRequire } = await import("node:module");
  const { pathToFileURL } = await import("node:url");
  const requireFromCwd = createRequire(pathToFileURL(process.cwd() + "/").href);
  sharp = requireFromCwd("sharp");
} catch (e) {
  console.error("Error: `sharp` is not installed in this project.");
  console.error("Install it first:  pnpm add -D sharp   (or npm/yarn equivalent)");
  console.error("Then re-run from that project's root (or a workspace package that has sharp).");
  process.exit(1);
}

const RASTER_EXTS = new Set([".png", ".jpg", ".jpeg", ".webp", ".avif"]);

// Sibling format to emit, if any (--emit-avif wins over --emit-webp).
const EMIT_EXT = opt.emitAvif ? ".avif" : opt.emitWebp ? ".webp" : null;

function shouldConsider(ext) {
  const e = ext.toLowerCase();
  if (!RASTER_EXTS.has(e)) return false;
  if (EMIT_EXT && e === EMIT_EXT) return false;
  if (opt.pngOnly && e !== ".png") return false;
  if (opt.jpgOnly && e !== ".jpg" && e !== ".jpeg") return false;
  if (opt.webpOnly && e !== ".webp") return false;
  return true;
}

const visitedDirectories = new Set();
function inspectPath(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    throw error;
  }
}
function isWithin(root, child) {
  const rel = relative(root, child);
  return rel === "" || (!rel.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) &&
    rel !== ".." && !isAbsolute(rel));
}
function walk(root, boundary, acc) {
  const st = inspectPath(root);
  if (!st) {
    console.warn(`SKIP (missing path): ${rel(root)}`);
    return acc;
  }
  if (st.isSymbolicLink()) {
    console.warn(`SKIP (symbolic link): ${rel(root)}`);
    return acc;
  }
  const real = realpathSync(root);
  if (!isWithin(boundary, real)) {
    console.warn(`SKIP (outside selected root): ${rel(root)}`);
    return acc;
  }
  if (st.isFile()) {
    if (shouldConsider(extname(root))) acc.push(root);
    return acc;
  }
  if (!st.isDirectory()) return acc;
  if (visitedDirectories.has(real)) return acc;
  visitedDirectories.add(real);
  for (const name of readdirSync(root)) {
    if (name.startsWith(".")) continue;
    if (name === "node_modules") continue;
    walk(join(root, name), boundary, acc);
  }
  return acc;
}

const files = [];
for (const p of paths) {
  const selected = resolve(p);
  const selectedStat = inspectPath(selected);
  if (!selectedStat) {
    console.warn(`SKIP (missing path): ${rel(selected)}`);
    continue;
  }
  if (selectedStat.isSymbolicLink()) {
    console.warn(`SKIP (symbolic-link input): ${rel(selected)}`);
    continue;
  }
  walk(selected, realpathSync(selected), files);
}

if (files.length === 0) {
  console.log("No raster images found in the given paths.");
  process.exit(0);
}

const results = [];

for (const file of files) {
  const ext = extname(file).toLowerCase();
  const stBefore = lstatSync(file);
  if (stBefore.size < opt.minBytes) {
    if (opt.verbose) console.log(`SKIP (too small ${kb(stBefore.size)})  ${rel(file)}`);
    continue;
  }

  let input;
  try { input = sharp(file, { failOn: "none" }); }
  catch (e) { console.warn(`SKIP (sharp read failed): ${rel(file)} — ${e.message}`); continue; }

  const meta = await input.metadata().catch(() => null);
  if (!meta || !meta.width) { console.warn(`SKIP (no metadata): ${rel(file)}`); continue; }

  const needsResize = meta.width > opt.maxWidth || meta.height > opt.maxHeight;
  const resizeArgs = needsResize
    ? { width: Math.min(meta.width, opt.maxWidth), height: Math.min(meta.height, opt.maxHeight), fit: "inside", withoutEnlargement: true }
    : null;

  // Build the candidate buffer in-memory; only commit to disk if smaller.
  let pipeline = resizeArgs ? input.resize(resizeArgs) : input;
  let outExt, outBuf;

  if (EMIT_EXT === ".avif" || ext === ".avif") {
    outExt = ".avif";
    outBuf = await pipeline.avif({ quality: opt.quality, effort: 4 }).toBuffer();
  } else if (EMIT_EXT === ".webp" || ext === ".webp") {
    outExt = ".webp";
    outBuf = await pipeline.webp({ quality: opt.quality, effort: 6 }).toBuffer();
  } else if (ext === ".png") {
    // Default: strictly lossless PNG re-encode (zlib effort-10).
    // Palette quantisation is opt-in via --palette (much smaller, but lossy
    // for photo-realistic gradient PNGs — use only for flat UI/icon-like PNGs).
    outExt = ".png";
    outBuf = await pipeline
      .png({ compressionLevel: 9, effort: 10, palette: opt.palette })
      .toBuffer();
  } else {
    // JPG / JPEG — mozjpeg at opt.quality
    outExt = ".jpg";
    outBuf = await pipeline.jpeg({ quality: opt.quality, mozjpeg: true, progressive: true }).toBuffer();
  }

  const after = outBuf.byteLength;

  const emitSibling = EMIT_EXT && ext !== EMIT_EXT;
  const targetPath = emitSibling
    ? file.replace(new RegExp(`${ext}$`), EMIT_EXT)
    : file;
  const existingTarget = inspectPath(targetPath);
  let comparisonStat = stBefore;
  let unsafeTargetReason = null;
  if (emitSibling && existingTarget) {
    if (existingTarget.isSymbolicLink() || !existingTarget.isFile()) {
      unsafeTargetReason = "unsafe sibling exists";
    } else if (!opt.overwriteExisting) {
      unsafeTargetReason = "sibling exists";
    } else {
      comparisonStat = existingTarget;
    }
  }
  const before = comparisonStat.size;
  const pct = 100 * (1 - after / before);

  const action =
    unsafeTargetReason ? `skip (${unsafeTargetReason})`
    : after >= before ? "skip (would be larger)"
    : opt.dry && emitSibling && existingTarget ? `dry-run (would overwrite ${basename(targetPath)})`
    : opt.dry ? "dry-run (would write)"
    : emitSibling && existingTarget ? `overwrite sibling ${basename(targetPath)}`
    : emitSibling ? `write sibling ${basename(targetPath)}`
    : "replace";

  const savings = after < before ? before - after : 0;
  results.push({ file, action, before, after, savings, pct });

  if (action === "replace" || action.startsWith("write sibling") ||
      action.startsWith("overwrite sibling")) {
    // Use a unique exclusive temp. A new sibling is committed with a hard link
    // so an existing user file can never be overwritten by a last-moment race.
    const tmp = `${targetPath}.superbrowky-tmp-${process.pid}-${Math.random().toString(16).slice(2)}`;
    writeFileSync(tmp, outBuf, { flag: "wx" });
    try {
      chmodSync(tmp, comparisonStat.mode);
      utimesSync(tmp, comparisonStat.atime, comparisonStat.mtime);
    } catch {}
    try {
      if (emitSibling && !existingTarget) {
        linkSync(tmp, targetPath);
        unlinkSync(tmp);
      } else {
        const current = inspectPath(targetPath);
        if (!current || current.isSymbolicLink() || !current.isFile() ||
            current.dev !== comparisonStat.dev || current.ino !== comparisonStat.ino ||
            current.size !== comparisonStat.size || current.mtimeMs !== comparisonStat.mtimeMs) {
          throw new Error(`target changed while processing: ${rel(targetPath)}`);
        }
        renameSync(tmp, targetPath);
      }
    } catch (error) {
      try { unlinkSync(tmp); } catch {}
      console.error(`Error: refused to commit ${rel(targetPath)} — ${error.message}`);
      process.exit(1);
    }
  }

  console.log(
    `${padAction(action)}  ${rel(file)}  ${kb(before)} → ${kb(after)}${after < before ? `  (−${pct.toFixed(0)}%)` : ""}` +
      (emitSibling && existingTarget ? "  (compared with existing sibling)" : "")
  );
}

const totalBefore = results.reduce((s, r) => s + r.before, 0);
const totalAfter = results.reduce((s, r) => s + r.after, 0);
const totalSavings = results.reduce((s, r) => s + r.savings, 0);

console.log("");
console.log("────────────────────────────────────────");
console.log(`${results.length} file(s) examined`);
if (totalSavings > 0) {
  console.log(`Total: ${kb(totalBefore)} → ${kb(totalAfter)}  saved ${kb(totalSavings)} (${(100 * totalSavings / totalBefore).toFixed(1)}%)`);
}
if (opt.dry) console.log("(dry-run — no files were written)");

// ---- helpers --------------------------------------------------------------
function kb(bytes) { return (bytes / 1024).toFixed(1) + "K"; }
function rel(p) { return p.startsWith(process.cwd()) ? p.slice(process.cwd().length + 1) : p; }
function padAction(a) { return a.padEnd(28, " "); }
function printUsageAndExit(code) {
  console.error([
    "usage: compress-images.mjs [options] <path> [<path> ...]",
    "",
    "  --dry              audit only, no writes (default)",
    "  --apply            write changes",
    "  --quality N        lossy quality (JPEG/WebP). default 85",
    "  --max-width N      resize if wider. default 2048",
    "  --max-height N     resize if taller. default 2048",
    "  --min-bytes N      skip smaller files. default 20480",
    "  --emit-webp        write .webp sibling (keep original)",
    "  --emit-avif        write .avif sibling (smaller, slower; wins over --emit-webp)",
    "  --overwrite-existing  allow replacing a smaller emitted sibling; explicit-only",
    "  --png-only         restrict to .png",
    "  --jpg-only         restrict to .jpg/.jpeg",
    "  --webp-only        restrict to .webp",
    "  --verbose          print skipped files too"
  ].join("\n"));
  process.exit(code);
}
