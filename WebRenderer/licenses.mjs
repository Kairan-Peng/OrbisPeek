import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const directory = dirname(fileURLToPath(import.meta.url));
const lock = JSON.parse(await readFile(join(directory, "package-lock.json"), "utf8"));
const sections = ["OrbisPeek — third-party software notices", "\nFreeLook task-list token adaptation\nSource commit: d3f002589917f51279b49ea8b12b3bb343dd82dc\nhttps://github.com/neolee/freelook\n\n" + await readFile(join(directory, "licenses/FreeLook-MIT.txt"), "utf8")];
const packages = [];
for (const [path, metadata] of Object.entries(lock.packages)) {
  if (!path.startsWith("node_modules/") || metadata.dev) continue;
  const packageDirectory = join(directory, path);
  const info = JSON.parse(await readFile(join(packageDirectory, "package.json"), "utf8"));
  const licenseFiles = (await readdir(packageDirectory)).filter((name) => /^(licen[cs]e|copying|notice)([.-].*)?$/i.test(name));
  if (!licenseFiles.length) throw new Error(`No license file found for ${info.name}`);
  const license = typeof info.license === "string" ? info.license : info.license?.type || "See license text";
  packages.push({ name: info.name, version: info.version, license });
  const contents = await Promise.all(licenseFiles.map(async (name) => `${name}\n\n${await readFile(join(packageDirectory, name), "utf8")}`));
  sections.push(`${info.name} ${info.version}\nhttps://www.npmjs.com/package/${info.name}\nLicense: ${license}\n\n${contents.join("\n\n")}`);
}
const destination = resolve(directory, "../Sources/QuicklookUI/Resources");
await mkdir(destination, { recursive: true });
await writeFile(join(destination, "THIRD_PARTY_NOTICES.txt"), sections.join("\n\n" + "=".repeat(72) + "\n\n") + "\n");
await writeFile(join(directory, "THIRD_PARTY.md"), `# Renderer third-party components\n\nGenerated from the locked runtime dependency graph by \`node licenses.mjs\`. Full license texts are bundled in \`Sources/QuicklookUI/Resources/THIRD_PARTY_NOTICES.txt\`.\n\nThe task-list token adaptation in \`src/markdown.js\` derives from [FreeLook](https://github.com/neolee/freelook/tree/d3f002589917f51279b49ea8b12b3bb343dd82dc), Copyright © 2026 Neo Lee, MIT. Its original license is retained in \`licenses/FreeLook-MIT.txt\`. The Shiki renderer and its runtime have not been copied.\n\n| Component | Version | License |\n|---|---|---|\n${packages.map((item) => `| ${item.name} | ${item.version} | ${item.license} |`).join("\n")}\n\nThe GitHub light/dark syntax themes are the styles shipped with highlight.js. Their original theme comments are preserved in the bundled CSS. Build and test tools remain development dependencies and are not shipped in the application.\n`);
