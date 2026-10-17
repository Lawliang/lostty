// Builds lostty.org from website/custom.html (the page published as the
// Claude artifact) into website/dist, for Cloudflare Pages:
//   build command: node website/build.mjs   output directory: website/dist
//
// custom.html is a fragment (the artifact host adds the document skeleton),
// so this wraps it in a real document, retitles it and drops the
// artifact-only meta. It also writes a favicon from the page's axolotl.
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "dist");
let page = readFileSync(join(here, "custom.html"), "utf8");

function swap(from, to) {
  if (!page.includes(from)) throw new Error(`build: not found in custom.html: ${from}`);
  page = page.replace(from, to);
}
swap("<title>Lostty Custom</title>", "<title>Lostty</title>");
swap('<meta name="claude:viewport-fit-sides" content="cover">\n', "");

const head = [
  "<!doctype html>",
  '<html lang="en">',
  "<head>",
  '<meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">',
  '<link rel="icon" href="/favicon.svg" type="image/svg+xml">',
  '<link rel="canonical" href="https://lostty.org/">',
  "",
].join("\n");

// the nav logo's axolotl (<g id="axo">), cropped to its head like the logo
// and centred in a square
const axo = page.match(/<g id="axo">[\s\S]*?<\/g>/);
if (!axo) throw new Error('build: <g id="axo"> not found in custom.html');
const favicon =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' +
  '<svg y="21" width="100" height="58" viewBox="0 12 100 58">' + axo[0] + "</svg></svg>\n";

mkdirSync(out, { recursive: true });
writeFileSync(join(out, "index.html"), head + page);
writeFileSync(join(out, "favicon.svg"), favicon);
// the Endorse popup's Stripe Checkout route (Pages runs _worker.js in front of the files)
copyFileSync(join(here, "worker.js"), join(out, "_worker.js"));
console.log(`built ${join(out, "index.html")} (${(head + page).length} bytes), favicon.svg and _worker.js`);
