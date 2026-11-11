import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { JSDOM } from "jsdom";
import { formatJSON, validateJSON } from "../src/format.js";
import { localImageURL, renderMarkdown } from "../src/markdown.js";
import { languageName, supportedLanguages } from "../src/languages.js";
import { boundedText, createRenderer, renderDocument, renderJSONLines } from "../src/renderer.js";

const html = await readFile(new URL("../src/index.html", import.meta.url), "utf8");
function page(t) {
  const dom = new JSDOM(html, { url: "https://quicklook.invalid/", runScripts: "outside-only" });
  t.after(() => dom.window.close());
  return { ...dom, dom, document: dom.window.document, window: dom.window };
}
const payload = (text, mode = "code", language = "plaintext") => ({
  text, mode, language, fileName: "样例", encoding: "UTF-8", totalBytes: Buffer.byteLength(text), bytesRead: Buffer.byteLength(text), truncated: false,
});

test("JSON formatting preserves large integer tokens, duplicate keys, key order and escape spelling", () => {
  const source = '{"z":9007199254740993123456789,"a":1e+23,"z":2,"escaped":"\\u4f60"}';
  const result = formatJSON(source);
  assert.equal(result.valid, true);
  assert.match(result.text, /9007199254740993123456789/);
  assert.match(result.text, /1e\+23/);
  assert.match(result.text, /\\u4f60/);
  assert.equal((result.text.match(/"z"/g) || []).length, 2);
  assert.ok(result.text.indexOf('"z"') < result.text.indexOf('"a"'));
});

test("invalid JSON, comments and trailing commas preserve original source", () => {
  for (const source of ['{"a":}', '{"a":1,}', '{/* comment */ "a":1}', '']) {
    const result = formatJSON(source);
    assert.equal(result.valid, false);
    assert.equal(result.text, source);
    assert.equal(typeof result.offset, "number");
  }
});

test("JSON has a nesting budget before recursive library parsing", () => {
  const source = "[".repeat(129) + "1" + "]".repeat(129);
  assert.equal(validateJSON(source).valid, false);
  assert.match(validateJSON(source).error, /128/);
  assert.equal(validateJSON('["brackets [ { inside strings"] ]').valid, false);
  assert.equal(validateJSON('["brackets [ { inside strings"] ' ).valid, true);
});

test("JSONL keeps healthy records and annotates a bad line without deleting it", () => {
  const result = renderJSONLines('{"ok":1}\nnot json\n\n{"ok":2}');
  assert.equal(result.records, 3);
  assert.equal(result.invalidLines, 1);
  assert.match(result.html, /not json/);
  assert.match(result.html, /invalid-line/);
  assert.match(result.notices.join(" "), /1 行无效/);
});

test("JSONL final partial record is marked as truncated only when native prefix was truncated", () => {
  assert.equal(renderJSONLines('{"ok":1}\n{"cut":', true).incompleteLines, 1);
  assert.equal(renderJSONLines('{"ok":1}\n{"cut":', true).invalidLines, 0);
  assert.equal(renderJSONLines('{"ok":1}\n{"cut":', false).invalidLines, 1);
});

test("JSONL DOM is bounded even with many records", () => {
  const source = Array.from({ length: 20_000 }, () => '{"n":1}').join("\n");
  const result = renderDocument(payload(source, "jsonl", "json"));
  assert.equal(result.report.visibleLineCount, 2_000);
  assert.equal(result.report.truncated, true);
  assert.equal((result.html.match(/class="source-line/g) || []).length, 2_000);
});

test("pretty-printed JSON also respects the display line budget", () => {
  const source = `[${Array.from({ length: 10_000 }, (_, index) => index).join(",")}]`;
  const result = renderDocument(payload(source, "json", "json"));
  assert.equal(result.report.validJSON, true);
  assert.equal(result.report.visibleLineCount, 4_000);
  assert.equal(result.report.truncated, true);
  assert.equal((result.html.match(/class="source-line/g) || []).length, 4_000);
});

test("Markdown renders GFM tables, task lists and highlighted code", () => {
  const result = renderMarkdown("# 标题\n\n| 列 | 值 |\n|---|---|\n| a | b |\n\n- [x] 完成\n- [ ] 待办\n\n```javascript\nconst answer = 42;\n```\n");
  assert.match(result.html, /<table>/);
  assert.match(result.html, /type="checkbox" checked disabled/);
  assert.match(result.html, /type="checkbox" disabled/);
  assert.match(result.html, /hljs-keyword/);
});

test("Markdown escapes document HTML and rejects remote, data and traversal images", () => {
  const result = renderMarkdown('<script>globalThis.pwned=true</script>\n<img src="https://example.invalid/x">\n\n![remote](https://example.invalid/test.png)\n\n![data](data:image/png;base64,AAAA)\n\n![escape](../private.png)\n\n![ok](images/chart.png)');
  assert.doesNotMatch(result.html, /<script>/);
  assert.doesNotMatch(result.html, /<img src="https:/);
  assert.equal(result.blockedImages, 3);
  assert.equal(result.localImages, 1);
  assert.match(result.html, /quicklook-resource:\/\/local\/images\/chart.png/);
});

test("local image URLs use encoded relative segments and reject ambiguous paths", () => {
  assert.equal(localImageURL("./图片/示意图.png?raw=1"), "quicklook-resource://local/%E5%9B%BE%E7%89%87/%E7%A4%BA%E6%84%8F%E5%9B%BE.png");
  assert.equal(localImageURL("images/a%3Fb%23c.png?raw=1#caption"), "quicklook-resource://local/images/a%3Fb%23c.png");
  for (const source of ["/tmp/image.png", "//remote/image.png", "file:///tmp/image.png", "../secret.png", "images/%2e%2e/secret.png", "C:\\tmp\\image.png", "images/a%00.png", "bad%zz.png"]) assert.equal(localImageURL(source), null, source);
});

test("every manifest language has a real bundled grammar", async () => {
  const manifest = JSON.parse(await readFile(new URL("../../Sources/QuicklookCore/Resources/file-types.json", import.meta.url), "utf8"));
  for (const item of manifest) {
    assert.ok(supportedLanguages.includes(item.language) || ["html", "erb"].includes(item.language), item.language);
    assert.equal(languageName(item.language), item.language);
  }
});

test("source escaping and balanced multiline syntax spans retain readable code", (t) => {
  const { document } = page(t);
  const source = '/* first\nsecond */\nconst html = "<script>alert(1)</script>";';
  document.getElementById("content").innerHTML = renderDocument(payload(source, "code", "javascript")).html;
  assert.equal(document.querySelectorAll("script").length, 1, "only the trusted script tag in the static template exists");
  const lines = [...document.querySelectorAll(".source-line code")];
  assert.deepEqual(lines.map((line) => line.textContent), source.split("\n"));
  assert.equal(lines[0].querySelector(".hljs-comment")?.textContent, "/* first");
  assert.equal(lines[1].querySelector(".hljs-comment")?.textContent, "second */");
});

test("large files and long lines fall back to bounded plain text", () => {
  const source = "const text = '" + "a".repeat(2_000_000) + "';";
  const result = renderDocument(payload(source, "code", "javascript"));
  assert.equal(result.report.truncated, true);
  assert.ok(result.copyText.length <= 524_288);
  assert.doesNotMatch(result.html, /hljs-keyword/);
  assert.match(result.notices.join(" "), /纯文本/);
  assert.equal(boundedText("a\r\nb\rc\n").visibleLineCount, 4);
});

test("DOM UI switches rendered/source modes without interpreting source", (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  renderer.render(payload("# Hello\n\n<script>alert(1)</script>", "markdown", "markdown"));
  assert.equal(document.querySelector(".markdown-body h1").textContent, "Hello");
  document.getElementById("source-toggle").click();
  assert.equal(renderer.report().sourceMode, true);
  assert.equal(document.querySelector(".markdown-body"), null);
  assert.match(document.querySelector(".source-code").textContent, /<script>/);
  assert.equal(document.querySelectorAll("script").length, 1);
});

test("search treats its query as text and skips line numbers", (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  renderer.render(payload("<script>\nhello hello\nlast"));
  assert.equal(renderer.search("hello").matches, 2);
  assert.equal(renderer.search("<script>").matches, 1);
  assert.equal(document.querySelectorAll("script").length, 1);
  assert.equal(renderer.search("1").matches, 0);
  assert.equal(document.querySelectorAll("mark").length, 0);
});

test("copy bridge receives the visible lossless JSON text", (t) => {
  const { document, window } = page(t);
  const messages = [];
  window.webkit = { messageHandlers: { quicklook: { postMessage: (message) => messages.push(message) } } };
  const renderer = createRenderer(document, window);
  renderer.render(payload('{"n":9007199254740993}', "json", "json"));
  document.getElementById("copy-button").click();
  assert.equal(messages[0].action, "copy");
  assert.match(messages[0].text, /9007199254740993/);
});

test("image load failure becomes a readable permission placeholder and is reported", (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  renderer.render(payload("![本地图片](images/chart.png)", "markdown", "markdown"));
  document.querySelector("#content img").dispatchEvent(new window.Event("error"));
  assert.equal(renderer.report().failedImages, 1);
  assert.match(document.querySelector(".blocked-image").textContent, /本地图片不可读/);
});

test("a removed image's late failure does not change the next document's report", (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  renderer.render(payload("![old](images/old.png)", "markdown", "markdown"));
  const oldImage = document.querySelector("#content img");
  renderer.render(payload("# New document", "markdown", "markdown"));
  oldImage.dispatchEvent(new window.Event("error"));
  assert.equal(renderer.report().failedImages, 0);
  assert.equal(document.querySelector(".blocked-image"), null);
});

test("only explicit web/mail links reach native user-navigation handling", (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  renderer.render(payload("# Links", "markdown", "markdown"));
  const anchor = document.createElement("a");
  anchor.textContent = "link";
  document.getElementById("content").append(anchor);
  for (const [href, prevented] of [
    ["https://example.invalid/", false], ["HTTP://example.invalid/", false], ["mailto:hello@example.invalid", false],
    ["file:///tmp/secret", true], ["quicklook-resource://local/a.png", true], ["javascript:alert(1)", true],
    ["another.md", true], ["#links", true],
  ]) {
    anchor.setAttribute("href", href);
    let observed;
    document.addEventListener("click", (event) => {
      observed = event.defaultPrevented;
      event.preventDefault(); // Avoid jsdom's own navigation after observing the preview's decision.
    }, { once: true });
    anchor.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
    assert.equal(observed, prevented, href);
  }
});

test("bundled artifact installs the public API and renders without a network runtime", async (t) => {
  const { document, window } = page(t);
  const bundle = await readFile(new URL("../../Sources/QuicklookUI/Resources/renderer.js", import.meta.url), "utf8");
  window.eval(bundle);
  assert.equal(typeof window.quicklook.render, "function");
  const report = window.quicklook.render(payload("# Bundled\n\nOffline", "markdown", "markdown"));
  assert.equal(report.mode, "markdown");
  assert.equal(document.querySelector(".markdown-body h1").textContent, "Bundled");
  assert.match(html, /connect-src 'none'/);
  assert.match(html, /img-src quicklook-resource:/);
});
