import { build } from "esbuild";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import "./licenses.mjs";

const source = fileURLToPath(new URL("./src/", import.meta.url));
const destination = fileURLToPath(new URL("../Sources/QuicklookUI/Resources/", import.meta.url));
await mkdir(destination, { recursive: true });
await build({
  entryPoints: [new URL("./src/renderer.js", import.meta.url).pathname],
  outfile: `${destination}/renderer.js`,
  bundle: true,
  minify: true,
  format: "iife",
  target: "safari18",
  legalComments: "eof",
});
await copyFile(`${source}/index.html`, `${destination}/index.html`);
const [stylesheet, light, dark] = await Promise.all([
  readFile(`${source}/styles.css`, "utf8"),
  readFile(new URL("./node_modules/highlight.js/styles/github.css", import.meta.url), "utf8"),
  readFile(new URL("./node_modules/highlight.js/styles/github-dark.css", import.meta.url), "utf8"),
]);
await writeFile(`${destination}/styles.css`, `${light}\n@media (prefers-color-scheme: dark) {\n${dark}\n}\n${stylesheet}`);
console.log(`Built local preview resources in ${destination}`);
