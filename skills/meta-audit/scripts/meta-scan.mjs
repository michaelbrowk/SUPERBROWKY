#!/usr/bin/env node
// meta-scan.mjs — pre-ship public-page metadata audit. Pure Node, zero deps
// (uses built-in fetch — needs Node 18+).
//
// Fetches a URL, parses <head>, and reports what's missing or out-of-spec for
// search + social sharing: title, description, canonical, Open Graph, Twitter
// cards, favicons, viewport, lang, robots — plus robots.txt / sitemap.xml at
// the origin. Catches the whole "we shipped and the link preview was blank"
// class of bug before launch.
//
// Usage:
//   node meta-scan.mjs https://example.com/page
//   node meta-scan.mjs --json https://example.com/page
//
// Exit code is non-zero if any ERROR-level check fails — wire it into CI.

function usage(output = console.error) {
  output("usage: node meta-scan.mjs [--json] <http(s)://url>");
}

let json = false;
let url = "";
for (const arg of process.argv.slice(2)) {
  if (arg === "--json") json = true;
  else if (arg === "-h" || arg === "--help") {
    usage(console.log);
    process.exit(0);
  } else if (arg.startsWith("--")) {
    console.error(`meta-scan: unknown flag: ${arg}`);
    usage();
    process.exit(2);
  } else if (url) {
    console.error("meta-scan: pass exactly one URL");
    usage();
    process.exit(2);
  } else {
    url = arg;
  }
}
if (!url) {
  usage();
  process.exit(2);
}
try {
  const parsed = new URL(url);
  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new Error("only http:// and https:// URLs are supported");
  }
  if (parsed.username || parsed.password) {
    throw new Error("URLs containing credentials are not accepted");
  }
} catch (error) {
  console.error(`meta-scan: invalid URL — ${error.message}`);
  process.exit(2);
}

const findings = []; // {level: error|warn|ok, key, msg}
const add = (level, key, msg) => findings.push({ level, key, msg });

function attr(tag, name) {
  const m = tag.match(
    new RegExp(
      `(?:^|\\s)${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>]+))`,
      "i",
    ),
  );
  return m ? (m[1] ?? m[2] ?? m[3] ?? "") : null;
}
// collect <meta>, <link>, <title>, <html ...> from raw HTML
function tags(html, el) {
  return [...html.matchAll(new RegExp(`<${el}\\b[^>]*>`, "gi"))].map((m) => m[0]);
}

function metaContent(metas, key, kind = "name") {
  for (const t of metas) {
    if ((attr(t, kind) || "").toLowerCase() === key.toLowerCase()) return attr(t, "content") ?? "";
  }
  return null;
}

async function head(origin, path) {
  try {
    const r = await fetch(new URL(path, origin), { method: "GET", redirect: "follow" });
    return r.ok;
  } catch {
    return false;
  }
}

const main = async () => {
  let html, finalUrl;
  try {
    const res = await fetch(url, { redirect: "follow", headers: { "user-agent": "meta-scan" } });
    finalUrl = res.url || url;
    if (!res.ok) add("error", "http", `HTTP ${res.status} for ${url}`);
    html = await res.text();
  } catch (e) {
    console.error(`meta-scan: couldn't fetch ${url} — ${e.message}`);
    process.exit(2);
  }
  const headHtml = (html.match(/<head[\s\S]*?<\/head>/i) || [html])[0];
  const metas = tags(headHtml, "meta");
  const links = tags(headHtml, "link");
  const origin = new URL(finalUrl).origin;

  // --- title ---
  const title = (headHtml.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1]?.trim();
  if (!title) add("error", "title", "no <title>");
  else if (title.length < 10) add("warn", "title", `<title> very short (${title.length} chars): "${title}"`);
  else if (title.length > 60) add("warn", "title", `<title> ${title.length} chars — may truncate in SERPs (~60)`);
  else add("ok", "title", `"${title}" (${title.length})`);

  // --- description ---
  const desc = metaContent(metas, "description");
  if (desc === null || !desc.trim()) add("error", "description", "no non-empty meta description");
  else if (desc.length < 50) add("warn", "description", `description short (${desc.length}, aim 50–160)`);
  else if (desc.length > 160) add("warn", "description", `description ${desc.length} chars — truncates (~160)`);
  else add("ok", "description", `${desc.length} chars`);

  // --- canonical ---
  const canonical = links.find((l) => (attr(l, "rel") || "").toLowerCase() === "canonical");
  if (!canonical || !(attr(canonical, "href") || "").trim()) {
    add("warn", "canonical", "no non-empty <link rel=canonical>");
  }
  else add("ok", "canonical", attr(canonical, "href"));

  // --- viewport ---
  if (!metaContent(metas, "viewport")) add("error", "viewport", "no responsive <meta viewport> — mobile layout will break");
  else add("ok", "viewport", "present");

  // --- lang ---
  const htmlTag = tags(html, "html")[0] || "";
  const lang = attr(htmlTag, "lang");
  if (!lang) add("error", "lang", "<html> has no lang attribute");
  else add("ok", "lang", lang);

  // --- robots ---
  const robots = (metaContent(metas, "robots") || "").toLowerCase();
  if (robots.includes("noindex")) add("warn", "robots", `meta robots = "${robots}" — page is excluded from search (intended?)`);
  else add("ok", "robots", robots || "(default index,follow)");

  // --- Open Graph ---
  for (const k of ["og:title", "og:description", "og:image", "og:url", "og:type"]) {
    const v = metaContent(metas, k, "property") ?? metaContent(metas, k);
    if (v === null || !v.trim()) add(k === "og:image" || k === "og:title" ? "error" : "warn", k, `missing or empty ${k}`);
    else add("ok", k, k === "og:image" ? v : `present`);
  }

  // --- Twitter card (falls back to OG, so warn not error) ---
  const tw = metaContent(metas, "twitter:card") ?? metaContent(metas, "twitter:card", "property");
  if (!tw) add("warn", "twitter:card", "no twitter:card (will fall back to OG, but explicit is safer)");
  else add("ok", "twitter:card", tw);

  // --- favicons ---
  const hasIcon = links.some(
    (l) => /\bicon\b/i.test(attr(l, "rel") || "") && (attr(l, "href") || "").trim(),
  );
  const hasApple = links.some(
    (l) => /apple-touch-icon/i.test(attr(l, "rel") || "") && (attr(l, "href") || "").trim(),
  );
  if (!hasIcon) add("error", "favicon", "no <link rel=icon>");
  else add("ok", "favicon", "present");
  if (!hasApple) add("warn", "apple-touch-icon", "no apple-touch-icon (blank icon when saved to iOS home screen)");
  else add("ok", "apple-touch-icon", "present");

  // --- origin files ---
  add((await head(origin, "/robots.txt")) ? "ok" : "warn", "robots.txt", `${origin}/robots.txt`);
  const sm = (await head(origin, "/sitemap.xml")) || (await head(origin, "/sitemap_index.xml"));
  add(sm ? "ok" : "warn", "sitemap.xml", `${origin}/sitemap.xml`);

  // --- output ---
  const errs = findings.filter((f) => f.level === "error").length;
  const warns = findings.filter((f) => f.level === "warn").length;
  if (json) {
    console.log(JSON.stringify({ url: finalUrl, errors: errs, warnings: warns, findings }, null, 2));
  } else {
    const sym = { error: "\x1b[31m✗\x1b[0m", warn: "\x1b[33m⚠\x1b[0m", ok: "\x1b[32m✓\x1b[0m" };
    console.log(`meta-audit · ${finalUrl}\n`);
    for (const f of findings) console.log(`  ${sym[f.level]} ${f.key.padEnd(18)} ${f.msg}`);
    console.log(`\n${errs} error(s), ${warns} warning(s)`);
  }
  process.exit(errs > 0 ? 1 : 0);
};

main();
