// Builds lostty.org from website/custom.html (the page published as the
// Claude artifact) into website/dist, for Cloudflare Pages:
//   build command: node website/build.mjs   output directory: website/dist
//
// custom.html is a fragment (the artifact host adds the document skeleton),
// so this wraps it in a real document, retitles it and drops the
// artifact-only meta. It also copies in the tab and home-screen icons.
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
  '<link rel="apple-touch-icon" href="/apple-touch-icon.png">',
  '<link rel="canonical" href="https://lostty.org/">',
  "",
].join("\n");

mkdirSync(out, { recursive: true });
writeFileSync(join(out, "index.html"), head + page);
// the tab icon (the "Prompt" mark from concepts/tab-icons.html) and its
// full-bleed 180px PNG for iPhone home screens
copyFileSync(join(here, "favicon.svg"), join(out, "favicon.svg"));
copyFileSync(join(here, "apple-touch-icon.png"), join(out, "apple-touch-icon.png"));
// the Endorse popup's Stripe Checkout route (Pages runs _worker.js in front of the files)
copyFileSync(join(here, "worker.js"), join(out, "_worker.js"));
console.log(`built ${join(out, "index.html")} (${(head + page).length} bytes), the icons and _worker.js`);
