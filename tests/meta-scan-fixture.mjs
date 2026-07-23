#!/usr/bin/env node

import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scanner = resolve(root, "skills/meta-audit/scripts/meta-scan.mjs");

function page({ emptyOg = false } = {}) {
  const ogTitle = emptyOg ? "" : "A complete Open Graph title";
  const ogImage = emptyOg ? "" : "https://example.test/social.png";
  return `<!doctype html>
<html lang=en>
<head>
  <title>A sufficiently descriptive test page title</title>
  <meta name=description content="A sufficiently long metadata description used to verify the local scanner behavior without external network access.">
  <meta name=viewport content=width=device-width>
  <meta property=og:title content="${ogTitle}">
  <meta property=og:description content="A useful social description">
  <meta property=og:image content="${ogImage}">
  <meta property=og:url content=https://example.test/page>
  <meta property=og:type content=website>
  <meta name=twitter:card content=summary_large_image>
  <link rel=canonical href=https://example.test/page>
  <link rel=icon href=/favicon.ico>
  <link rel=apple-touch-icon href=/apple.png>
</head>
<body>Fixture</body>
</html>`;
}

const server = createServer((request, response) => {
  if (request.url === "/robots.txt" || request.url === "/sitemap.xml") {
    response.writeHead(200, { "content-type": "text/plain" });
    response.end("ok");
    return;
  }
  response.writeHead(200, { "content-type": "text/html" });
  response.end(page({ emptyOg: request.url === "/empty-og" }));
});

function run(url) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(process.execPath, [scanner, url], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { output += chunk; });
    child.on("error", rejectRun);
    child.on("close", (code) => resolveRun({ code, output }));
  });
}

try {
  await new Promise((resolveListen, rejectListen) => {
    server.once("error", rejectListen);
    server.listen(0, "127.0.0.1", resolveListen);
  });
  const { port } = server.address();
  const valid = await run(`http://127.0.0.1:${port}/unquoted`);
  if (valid.code !== 0) {
    throw new Error(`valid unquoted attributes failed:\n${valid.output}`);
  }
  const empty = await run(`http://127.0.0.1:${port}/empty-og`);
  if (empty.code !== 1 || !empty.output.includes("og:title") || !empty.output.includes("og:image")) {
    throw new Error(`empty OG fields did not fail honestly:\n${empty.output}`);
  }
  console.log("PASS: metadata scanner accepts valid unquoted attrs and rejects empty OG fields");
} finally {
  await new Promise((resolveClose) => server.close(resolveClose));
}
