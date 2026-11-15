import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { JSDOM } from "jsdom";
import { renderMarkdown } from "../src/markdown.js";
import { createRenderer } from "../src/renderer.js";

const token = "D74B9B4A-7C26-4A98-8A67-30E256E963DE";

function rendered(t, source) {
  const result = renderMarkdown(source, token);
  const dom = new JSDOM(result.html);
  t.after(() => dom.window.close());
  return { ...result, document: dom.window.document };
}

test("README HTML image renders through the current local capability at its authored width", async (t) => {
  const source = (await readFile(new URL("../../README.zh-CN.md", import.meta.url), "utf8")).split("\n")[0];
  assert.equal(source, '<img src="docs/brand/orbispeek-icon.png" width="96" alt="OrbisPeek 应用图标">');
  const result = renderMarkdown(source, token);
  const dom = new JSDOM(result.html);
  t.after(() => dom.window.close());
  const image = dom.window.document.querySelector("img");
  assert.ok(image, "the README tag must produce an image rather than escaped source");
  assert.equal(image.getAttribute("src"), `quicklook-resource://local/${token}/docs/brand/orbispeek-icon.png`);
  assert.equal(image.getAttribute("width"), "96");
  assert.equal(image.getAttribute("alt"), "OrbisPeek 应用图标");
  assert.equal(result.localImages, 1);
  assert.equal(result.blockedImages, 0);
});

test("HTML images support inline, multiline, case-insensitive and self-closing tags", (t) => {
  for (const source of [
    '<img src="images/chart.png">',
    "before <IMG SRC='images/chart.png' ALT='中文' WIDTH='96'/> after",
    '<img\nsrc="images/chart.png"\nwidth="96"\n>',
    '<img src=images/chart.png width=96 />',
    '<img ignored src="images/chart.png">',
  ]) {
    const result = rendered(t, source);
    assert.equal(result.document.images.length, 1, source);
    assert.equal(result.localImages, 1, source);
    assert.equal(result.document.images[0].getAttribute("src"), `quicklook-resource://local/${token}/images/chart.png`);
  }
});

test("HTML image attributes are reconstructed from a small allowlist and decoded once", (t) => {
  const result = rendered(t, '<img src="images/a&amp;b.png" alt="A &quot;quoted&quot; &gt; &#x4e2d;文 &lt;img src=x.png&gt;" width="&#57;6" height="48" onerror="alert(1)" style="width:9999px" srcset="https://bad/2.png 2x" class="toolbar" id="source-toggle" loading="eager">');
  const image = result.document.images[0];
  assert.equal(image.getAttribute("src"), `quicklook-resource://local/${token}/images/a%26b.png`);
  assert.equal(image.getAttribute("alt"), 'A "quoted" > 中文 <img src=x.png>');
  assert.equal(image.getAttribute("width"), "96");
  assert.equal(image.getAttribute("height"), "48");
  assert.deepEqual(image.getAttributeNames().sort(), ["alt", "decoding", "height", "loading", "src", "width"]);
  assert.equal(result.document.images.length, 1);
  assert.equal(result.document.querySelectorAll("script").length, 0);
});

test("duplicate image attributes consistently use the first occurrence", (t) => {
  const result = rendered(t, '<img src="images/first.png" SRC="https://bad/x.png" width="96" WIDTH="128" alt="first" ALT="second">');
  const image = result.document.images[0];
  assert.equal(image.getAttribute("src"), `quicklook-resource://local/${token}/images/first.png`);
  assert.equal(image.getAttribute("width"), "96");
  assert.equal(image.getAttribute("alt"), "first");
  const blocked = rendered(t, '<img src="https://bad/x.png" src="images/allowed.png">');
  assert.equal(blocked.document.images.length, 0);
  assert.equal(blocked.blockedImages, 1);
});

test("image dimensions accept only bounded positive integer pixels", (t) => {
  for (const value of ["1", "96", "1600"]) {
    const image = rendered(t, `<img src="x.png" width="${value}" height="${value}">`).document.images[0];
    assert.equal(image.getAttribute("width"), value);
    assert.equal(image.getAttribute("height"), value);
  }
  for (const value of ["", "0", "-1", "+96", "096", "96px", "96%", "9.6", "1e2", " 96 ", "1601", "99999999999999999999", "&#x22; onload=alert(1)"]) {
    const image = rendered(t, `<img src="x.png" width="${value}" height="${value}">`).document.images[0];
    assert.equal(image.hasAttribute("width"), false, value);
    assert.equal(image.hasAttribute("height"), false, value);
  }
});

test("HTML images preserve the native local raster and request capability boundaries", (t) => {
  for (const source of [
    "https://bad/x.png", "//bad/x.png", "data:image/png;base64,AAAA", "file:///tmp/x.png", "/tmp/x.png",
    "../x.png", "images/%2e%2e/x.png", "images/&#46;&#46;/x.png", "images/..&#x2f;x.png", "x.svg", "x.SVG",
    "images/x\\y.png", "bad%zz.png", "images/x%00.png", "javascript:alert(1)", "", "images/no-extension",
  ]) {
    const result = rendered(t, `<img src="${source}" alt="blocked">`);
    assert.equal(result.document.images.length, 0, source);
    assert.equal(result.blockedImages, 1, source);
    assert.equal(result.localImages, 0, source);
  }
  for (const resourceToken of ["../other", "bad", ""]) {
    const result = renderMarkdown('<img src="images/x.png">', resourceToken);
    assert.equal(result.localImages, 0);
    assert.equal(result.blockedImages, 1);
  }
});

test("code, escaped tags and entity text never activate HTML images", (t) => {
  const tag = '<img src="images/chart.png" width="96">';
  for (const source of [
    `\`${tag}\``, `\`\`\`html\n${tag}\n\`\`\``, `    ${tag}`,
    `\\${tag}`, '&lt;img src="images/chart.png"&gt;',
  ]) {
    const result = rendered(t, source);
    assert.equal(result.document.images.length, 0, source);
    assert.equal(result.localImages, 0, source);
    assert.match(result.document.body.textContent, /<img/);
  }
});

test("HTML literal regions and other tags' attributes cannot reactivate image markup", (t) => {
  const image = '<img src="images/chart.png">';
  for (const source of [
    `<!-- ${image} -->`, `<!--\n\n${image}\n\n-->`, `before <!--\n\n${image}\n\n--> after`,
    `<!--\n\n${image}`, `<![CDATA[${image}]]>`, `<? processing ${image} ?>`,
    `<script>const text='${image}';</script>`, `<style>\n\n${image}\n\n</style>`,
    `<textarea>${image}</textarea>`, `<div title='${image}'>text</div>`, `<imgx data='${image}'>`,
    `<img src='${image}'>`, `<img src="unterminated ${image}`, '<img src="x.png"width="96">',
  ]) {
    const result = rendered(t, source);
    assert.equal(result.document.images.length, 0, source);
    assert.equal(result.localImages, 0, source);
  }
  const restored = rendered(t, `<!--\n\n${image}\n\n--> ${image}`);
  assert.equal(restored.document.images.length, 1, "normal images after the literal terminator still render");
  assert.equal(restored.localImages, 1);
  rendered(t, "<!-- unclosed");
  assert.equal(rendered(t, image).localImages, 1, "literal state belongs only to its current render request");
});

test("HTML image scanning is bounded and malformed tags stay literal", (t) => {
  for (const source of [
    '<image src="x.png">', '<imgsrc="x.png">', '</img>', '<img src="x.png"',
    `<img ${'ignored="x" '.repeat(65)}src="x.png">`, `<img alt="${"a".repeat(8200)}" src="x.png">`,
  ]) {
    const result = rendered(t, source);
    assert.equal(result.document.images.length, 0, source.slice(0, 100));
    assert.equal(result.localImages, 0);
  }
});

test("HTML image source switching and copy retain exact plain text without adding Find", async (t) => {
  const shell = await readFile(new URL("../src/index.html", import.meta.url), "utf8");
  const dom = new JSDOM(shell, { url: "https://quicklook.invalid/", runScripts: "outside-only" });
  t.after(() => dom.window.close());
  const { document } = dom.window;
  const renderer = createRenderer(document, dom.window);
  const source = '<img src="images/x.png" width="96" alt="HTML image">\n\n# 图片测试\n\n正文 **中文加粗** 和 `inline_code`。';
  await renderer.render({ text: source, mode: "markdown", language: "markdown", resourceToken: token, fileName: "image.md", encoding: "UTF-8", totalBytes: Buffer.byteLength(source), bytesRead: Buffer.byteLength(source), truncated: false }, "image-copy-request");
  assert.equal(document.querySelectorAll("#content img").length, 1);
  renderer.commands.selectAllBody();
  assert.equal(renderer.getBodyView().selectedPlainText(), "图片测试\n正文 中文加粗 和 inline_code。");
  document.getElementById("source-toggle").click();
  assert.equal(document.querySelectorAll("#content img").length, 0);
  renderer.commands.selectAllBody();
  assert.equal(renderer.getBodyView().selectedPlainText(), source);
  document.getElementById("source-toggle").click();
  assert.equal(document.querySelectorAll("#content img").length, 1);
  assert.equal(document.getElementById("search-input"), null);
  assert.equal(document.getElementById("search-toggle"), null);
  assert.equal(document.getElementById("copy-button"), null);
  assert.deepEqual([...document.querySelectorAll(".actions button")].map((button) => button.id), ["source-toggle", "wrap-toggle"]);
});
