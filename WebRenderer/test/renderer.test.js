import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { JSDOM } from "jsdom";
import { formatJSON, validateJSON } from "../src/format.js";
import { localImageURL, renderMarkdown } from "../src/markdown.js";
import { languageName, supportedLanguages } from "../src/languages.js";
import { boundedText, createRenderer, renderDocument, renderJSONLines } from "../src/renderer.js";
import { createPreviewCommands } from "../src/preview-commands.js";
import { createBodyView } from "../src/selection.js";

const html = await readFile(new URL("../src/index.html", import.meta.url), "utf8");
const stylesheet = await readFile(new URL("../src/styles.css", import.meta.url), "utf8");
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
  assert.equal(result.blockedImages, 4);
  assert.equal(result.localImages, 1);
  assert.match(result.html, /quicklook-resource:\/\/local\/images\/chart.png/);
});

test("local image URLs use encoded relative segments and reject ambiguous paths", () => {
  assert.equal(localImageURL("./图片/示意图.png?raw=1"), "quicklook-resource://local/%E5%9B%BE%E7%89%87/%E7%A4%BA%E6%84%8F%E5%9B%BE.png");
  assert.equal(localImageURL("images/a%3Fb%23c.png?raw=1#caption"), "quicklook-resource://local/images/a%3Fb%23c.png");
  for (const source of ["/tmp/image.png", "//remote/image.png", "file:///tmp/image.png", "../secret.png", "images/%2e%2e/secret.png", "C:\\tmp\\image.png", "images/a%00.png", "bad%zz.png"]) assert.equal(localImageURL(source), null, source);
});

test("native resource capabilities are included in Markdown image URLs", () => {
  const token = "D74B9B4A-7C26-4A98-8A67-30E256E963DE";
  const result = renderDocument({ ...payload("![local](images/chart.png)", "markdown", "markdown"), resourceToken: token });
  assert.match(result.html, new RegExp(`quicklook-resource://local/${token}/images/chart\\.png`));
  for (const invalid of ["../other", "not-a-uuid", "x/../../", "<script>"]) {
    assert.equal(localImageURL("images/chart.png", invalid), null);
  }
});

test("every manifest language has a real bundled grammar", async () => {
  const manifest = JSON.parse(await readFile(new URL("../../Sources/QuicklookCore/Resources/file-types.json", import.meta.url), "utf8"));
  for (const item of manifest) {
    assert.ok(supportedLanguages.includes(item.language) || ["html", "erb"].includes(item.language), item.language);
    assert.equal(languageName(item.language), item.language);
  }
});

test("source escaping and balanced multiline syntax spans retain readable code", async (t) => {
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

test("DOM UI switches rendered/source modes without interpreting source", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("# Hello\n\n<script>alert(1)</script>", "markdown", "markdown"));
  assert.equal(document.querySelector(".markdown-body h1").textContent, "Hello");
  document.getElementById("source-toggle").click();
  assert.equal(renderer.report().sourceMode, true);
  assert.equal(document.querySelector(".markdown-body"), null);
  assert.match(document.querySelector(".source-code").textContent, /<script>/);
  assert.equal(document.querySelectorAll("script").length, 1);
});

test("toolbar keeps independent icon actions with accessible names and no whole-document copy", async (t) => {
  const { document } = page(t);
  await createRenderer(document).render(payload("# Hello", "markdown", "markdown"));
  assert.deepEqual([...document.querySelectorAll(".actions button")].map((button) => button.id), ["source-toggle", "wrap-toggle"]);
  assert.equal(document.getElementById("copy-button"), null);
  for (const id of ["source-toggle", "wrap-toggle"]) {
    const button = document.getElementById(id);
    assert.ok(button.getAttribute("aria-label"), id);
    assert.ok(button.title, id);
    assert.ok(button.querySelector("svg"), id);
    for (const icon of button.querySelectorAll("svg")) assert.equal(icon.getAttribute("aria-hidden"), "true", id);
  }
});

for (const [mode, returnLabel] of [["markdown", "查看预览"], ["json", "查看格式化内容"], ["jsonl", "查看记录视图"]]) {
  test(`${mode} toolbar preserves mode icons and accurately describes the return action`, async (t) => {
    const { document } = page(t);
    const renderer = createRenderer(document);
    await renderer.render(payload(mode === "markdown" ? "# Hello" : '{"n":1}', mode, mode === "markdown" ? "markdown" : "json"));
    const button = document.getElementById("source-toggle");
    const sourceIcon = button.querySelector(".source-icon");
    const previewIcon = button.querySelector(".preview-icon");
    assert.ok(sourceIcon);
    assert.ok(previewIcon);
    for (let count = 0; count < 2; count += 1) {
      assert.equal(button.hidden, false);
      assert.equal(button.getAttribute("aria-label"), "查看原文");
      assert.equal(button.getAttribute("aria-pressed"), "false");
      assert.equal(sourceIcon.hasAttribute("hidden"), false);
      assert.equal(previewIcon.hasAttribute("hidden"), true);
      button.click();
      assert.equal(button.getAttribute("aria-label"), returnLabel);
      assert.equal(button.title, returnLabel);
      assert.equal(button.getAttribute("aria-pressed"), "true");
      assert.equal(sourceIcon.hasAttribute("hidden"), true);
      assert.equal(previewIcon.hasAttribute("hidden"), false);
      assert.equal(button.querySelector(".source-icon"), sourceIcon);
      assert.equal(button.querySelector(".preview-icon"), previewIcon);
      button.click();
    }
    await renderer.render(payload("plain source"));
    assert.equal(button.hidden, true, "source-only documents have no alternate mode");
  });
}

test("wrapping is enabled by default for text and disabled in rendered Markdown", async (t) => {
  const { document } = page(t);
  const renderer = createRenderer(document);
  const button = document.getElementById("wrap-toggle");
  await renderer.render(payload("# Hello", "markdown", "markdown"));
  assert.equal(button.disabled, true);
  assert.equal(button.getAttribute("aria-pressed"), "true");
  button.click();
  assert.equal(document.body.classList.contains("wrap-lines"), true);
  document.getElementById("source-toggle").click();
  assert.equal(button.disabled, false);
  button.click();
  assert.equal(document.body.classList.contains("wrap-lines"), false);
  assert.equal(button.getAttribute("aria-pressed"), "false");
  document.getElementById("source-toggle").click();
  assert.equal(button.disabled, true);
  document.getElementById("source-toggle").click();
  assert.equal(button.getAttribute("aria-pressed"), "false", "returning to source retains the chosen wrap state");
  for (const mode of ["json", "jsonl", "code"]) {
    await renderer.render(payload('{"n":1}', mode, "json"));
    assert.equal(button.disabled, false, mode);
  }
});

test("filename remains nonvisual with exact document identity and accessible metadata", async (t) => {
  const { document } = page(t);
  const style = document.createElement("style");
  style.textContent = stylesheet;
  document.head.append(style);
  const renderer = createRenderer(document);
  const cases = [
    ["产品需求说明.md", "产品需求说明", ".md"],
    ["archive.backup.tar.gz", "archive.backup.tar", ".gz"],
    [".gitignore", ".gitignore", ""],
    [".env.local", ".env", ".local"],
    ["Makefile", "Makefile", ""],
    ["trailing.", "trailing.", ""],
    ['<img src=x onerror="alert(1)">.txt', '<img src=x onerror="alert(1)">', ".txt"],
  ];
  for (const [fileName, basename, extension] of cases) {
    await renderer.render({ ...payload("one\ntwo"), fileName });
    const filename = document.getElementById("file-name");
    assert.equal(document.getElementById("file-basename").textContent, basename);
    assert.equal(document.getElementById("file-extension").textContent, extension);
    assert.equal(filename.textContent, fileName);
    assert.equal(filename.querySelector("img"), null);
    assert.equal(document.title, `${fileName} · OrbisPeek`);
    const filenameStyle = document.defaultView.getComputedStyle(filename);
    assert.equal(filenameStyle.position, "absolute");
    assert.equal(filenameStyle.width, "1px");
    assert.equal(filenameStyle.height, "1px");
    assert.equal(filenameStyle.overflow, "hidden");
    assert.equal(filenameStyle.clipPath, "inset(50%)");
    assert.equal(filename.closest('[hidden], [aria-hidden="true"]'), null, "the filename stays accessible");
    assert.equal(filename.title, `${fileName} · PLAINTEXT · UTF-8 · 7 B · 2 行`);
    assert.equal(document.querySelector(".document-info").title, filename.title);
    const description = document.getElementById(filename.getAttribute("aria-describedby"));
    assert.equal(description.textContent, "PLAINTEXT · UTF-8 · 7 B · 2 行");
    assert.equal(description.closest('[hidden], [aria-hidden="true"]'), null);
    assert.equal(document.getElementById("file-meta").getAttribute("aria-hidden"), "true");
    assert.ok(filename.compareDocumentPosition(document.getElementById("file-meta")) & 4, "filename precedes metadata");
  }
});

test("metadata occupies the left of the compact toolbar with icon actions at the right", async (t) => {
  const { document, window } = page(t);
  const style = document.createElement("style");
  style.textContent = stylesheet;
  document.head.append(style);
  const renderer = createRenderer(document);
  for (const mode of ["markdown", "json", "jsonl", "code"]) {
    await renderer.render({ ...payload(mode === "markdown" ? "# Body" : '{"n":1}', mode), fileName: "document-name.txt" });
    const toolbar = document.querySelector(".toolbar");
    const info = document.querySelector(".document-info");
    const metadata = document.getElementById("file-meta");
    const actions = document.querySelector(".actions");
    assert.equal(window.getComputedStyle(toolbar).display, "flex");
    assert.equal(window.getComputedStyle(toolbar).flexWrap, "nowrap");
    assert.equal(window.getComputedStyle(info).flexGrow, "1");
    assert.equal(window.getComputedStyle(metadata).display, "flex");
    assert.equal(window.getComputedStyle(metadata).whiteSpace, "nowrap");
    assert.equal(window.getComputedStyle(actions).flexShrink, "0");
    assert.equal(metadata.closest(".document-info"), info);
    assert.ok(info.compareDocumentPosition(actions) & 4, "metadata precedes the right-hand icon actions");
    assert.equal(metadata.textContent.includes("document-name.txt"), false);
    assert.ok(document.getElementById("format-label").textContent);
    assert.ok(document.getElementById("file-encoding").textContent);
    assert.ok(document.getElementById("file-size").textContent);
    assert.ok(document.getElementById("file-count").textContent);
    assert.deepEqual([...actions.querySelectorAll("button")].map((button) => button.id), ["source-toggle", "wrap-toggle"]);
    assert.equal(document.querySelector(".search-bar, #search-toggle, #copy-button"), null);
  }
});

test("metadata follows current display counts and preserves encoding warnings outside optional metadata", async (t) => {
  const { document } = page(t);
  const renderer = createRenderer(document);
  await renderer.render({ ...payload('{"n":1}\n\n{"n":2}', "jsonl", "json"), encoding: "GB 18030", warning: "推测编码为 GB 18030，请核对内容。" });
  assert.equal(document.getElementById("file-count").textContent, "2 条记录");
  assert.match(document.getElementById("file-description").textContent, /JSONL · GB 18030 · .* · 2 条记录/);
  assert.equal(document.getElementById("notices").hidden, false);
  assert.match(document.getElementById("notices").textContent, /推测编码为 GB 18030/);
  document.getElementById("source-toggle").click();
  assert.equal(document.getElementById("file-count").textContent, "3 行");
  assert.match(document.getElementById("file-description").textContent, /3 行$/);
  assert.match(document.getElementById("file-name").title, /3 行$/);
  assert.match(document.getElementById("notices").textContent, /推测编码为 GB 18030/);
  await renderer.render(payload('{"n":1}', "json", "json"));
  assert.equal(document.getElementById("file-count").textContent, "3 行", "formatted JSON reports displayed lines");
  document.getElementById("source-toggle").click();
  assert.equal(document.getElementById("file-count").textContent, "1 行");
});

test("search treats its query as text and skips line numbers", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("<script>\nhello hello\nlast"));
  assert.equal(renderer.search("hello").matches, 2);
  assert.equal(renderer.search("<script>").matches, 1);
  assert.equal(document.querySelectorAll("script").length, 1);
  assert.equal(renderer.search("1").matches, 0);
  assert.equal(document.querySelectorAll("mark").length, 0);
});

function key(window, element, value, options = {}) {
  const event = new window.KeyboardEvent("keydown", { key: value, bubbles: true, cancelable: true, ...options });
  element.dispatchEvent(event);
  return event;
}

function windowClock(t, window) {
  let now = 0;
  let sequence = 0;
  const timers = new Map();
  t.mock.method(window, "setTimeout", (callback, delay = 0, ...args) => {
    const handle = ++sequence;
    timers.set(handle, { at: now + Math.max(0, Number(delay) || 0), callback, args });
    return handle;
  });
  t.mock.method(window, "clearTimeout", (handle) => timers.delete(handle));
  return {
    advance(milliseconds) {
      const end = now + milliseconds;
      while (true) {
        const next = [...timers].filter(([, timer]) => timer.at <= end)
          .sort(([leftID, left], [rightID, right]) => left.at - right.at || leftID - rightID)[0];
        if (!next) break;
        const [handle, timer] = next;
        timers.delete(handle);
        now = timer.at;
        timer.callback(...timer.args);
      }
      now = end;
    },
  };
}

function selectBodyText(document, node, from = 0, to = node.length) {
  const range = document.createRange();
  range.setStart(node, from);
  range.setEnd(node, to);
  const selection = document.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
}

function copyEvent(window, target, clipboardData) {
  const event = new window.Event("copy", { bubbles: true, cancelable: true });
  if (clipboardData) Object.defineProperty(event, "clipboardData", { value: clipboardData });
  target.dispatchEvent(event);
  return event;
}

test("selection copy bridge receives current formatted and source JSON with its request ID", async (t) => {
  const { document, window } = page(t);
  const messages = [];
  window.webkit = { messageHandlers: { quicklook: { postMessage: (message) => messages.push(message) } } };
  const renderer = createRenderer(document, window);
  const text = '{"n":9007199254740993123456789,"escaped":"\\u4f60","n":2}';
  await renderer.render(payload(text, "json", "json"), "copy-request");
  const content = document.getElementById("content");
  assert.equal(key(window, content, "a", { metaKey: true }).defaultPrevented, true);
  assert.equal(key(window, content, "c", { metaKey: true }).defaultPrevented, false, "copy is handled once by the standard copy event");
  assert.equal(messages.length, 0);
  assert.equal(copyEvent(window, content).defaultPrevented, true);
  assert.deepEqual(messages, [{ action: "copy", text: formatJSON(text).text, requestID: "copy-request", viewGeneration: 1 }]);
  const firstView = renderer.getBodyView();
  document.getElementById("source-toggle").click();
  assert.notEqual(renderer.getBodyView(), firstView, "mode changes replace the current body adapter");
  renderer.commands.selectAllBody();
  assert.equal(renderer.commands.copySelection(), true);
  assert.deepEqual(messages[1], { action: "copy", text, requestID: "copy-request", viewGeneration: 2 });
});

test("rendered Markdown copy uses only the selected readable DOM and source mode uses Markdown", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  const text = "# Hello **world**\n\n- first\n- second\n\n```text\n  code  \n```\n\n![blocked](https://example.invalid/image.png)";
  await renderer.render(payload(text, "markdown", "markdown"));
  const writes = [];
  const clipboardData = { setData: (type, value) => writes.push({ type, value }) };
  const content = document.getElementById("content");
  const word = content.querySelector("strong").firstChild;
  selectBodyText(document, word, 1, 4);
  assert.equal(copyEvent(window, content, clipboardData).defaultPrevented, true);
  assert.deepEqual(writes.pop(), { type: "text/plain", value: "orl" });
  renderer.commands.selectAllBody();
  copyEvent(window, content, clipboardData);
  assert.deepEqual(writes.pop(), { type: "text/plain", value: "Hello world\nfirst\nsecond\n  code  \n" });
  assert.equal(renderer.getBodyView().kind, "rendered");
  assert.equal(renderer.commands.getBodyView(), renderer.getBodyView());
  document.getElementById("source-toggle").click();
  renderer.commands.selectAllBody();
  copyEvent(window, content, clipboardData);
  assert.deepEqual(writes.pop(), { type: "text/plain", value: text });
  assert.equal(renderer.getBodyView().kind, "source");
});

for (const mode of ["code", "jsonl"]) {
  test(`${mode} selection copy retains source whitespace and excludes row decorations`, async (t) => {
    const { document, window } = page(t);
    const renderer = createRenderer(document, window);
    const text = mode === "jsonl" ? '{"n":9007199254740993123456789}\nnot json\n  \t\n' : '  const n = 9007199254740993123456789;\n\n\t你\u200b好\n';
    await renderer.render(payload(text, mode, mode === "jsonl" ? "json" : "javascript"));
    renderer.commands.selectAllBody();
    const writes = [];
    const event = copyEvent(window, document.getElementById("content"), { setData: (type, value) => writes.push({ type, value }) });
    assert.equal(event.defaultPrevented, true);
    assert.deepEqual(writes, [{ type: "text/plain", value: text }]);
  });
}

test("body select all includes only current bounded display content", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  const text = Array.from({ length: 4_100 }, (_, index) => `line ${index}`).join("\r\n");
  await renderer.render(payload(text));
  const content = document.getElementById("content");
  assert.equal(key(window, document, "a", { metaKey: true }).defaultPrevented, true);
  const view = renderer.getBodyView();
  assert.equal(view.document, document);
  assert.equal(view.root, content);
  assert.equal(document.activeElement, content);
  assert.equal(view.selectedPlainText(), boundedText(text).text);
  assert.doesNotMatch(view.selectedPlainText(), /line 4000|查看原文|UTF-8/);
  assert.equal(document.getSelection().getRangeAt(0).commonAncestorContainer, content);
});

test("copy without a body selection leaves the clipboard unchanged", async (t) => {
  const { document, window } = page(t);
  const messages = [];
  window.webkit = { messageHandlers: { quicklook: { postMessage: (message) => messages.push(message) } } };
  const renderer = createRenderer(document, window);
  await renderer.render(payload("visible body"), "no-selection-request");
  const writes = [];
  const clipboardData = { setData: (...args) => writes.push(args) };
  assert.equal(copyEvent(window, document.getElementById("content"), clipboardData).defaultPrevented, true, "an empty body copy is canceled without supplying data");
  assert.equal(renderer.commands.copySelection(), false);
  const toolbar = document.getElementById("file-basename").firstChild;
  selectBodyText(document, toolbar);
  assert.equal(copyEvent(window, document.body, clipboardData).defaultPrevented, false);
  assert.deepEqual(messages, []);
  assert.deepEqual(writes, []);
});

test("copying a blocked-image-only body selection cancels default copy without changing the clipboard", async (t) => {
  const { document, window } = page(t);
  const messages = [];
  window.webkit = { messageHandlers: { quicklook: { postMessage: (message) => messages.push(message) } } };
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![remote](https://example.invalid/image.png)", "markdown", "markdown"), "blocked-copy-request");
  const blocked = document.querySelector("#content .blocked-image");
  selectBodyText(document, blocked.firstChild);
  assert.equal(renderer.getBodyView().selectedPlainText(), null);
  const writes = [];
  for (const clipboardData of [{ setData: (...args) => writes.push(args) }, undefined]) {
    const event = copyEvent(window, document.getElementById("content"), clipboardData);
    assert.equal(event.defaultPrevented, true, "excluded notice text must not reach the browser's default copy action");
  }
  assert.deepEqual(writes, []);
  assert.deepEqual(messages, []);
});

test("editing controls preserve native select/copy/paste even with an existing body selection", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("visible body"));
  renderer.commands.selectAllBody();
  const input = document.createElement("input");
  document.body.append(input);
  input.focus();
  input.value = "editing text";
  input.setSelectionRange(1, 5);
  const writes = [];
  for (const letter of ["a", "c", "v"]) assert.equal(key(window, input, letter, { metaKey: true }).defaultPrevented, false);
  assert.equal(copyEvent(window, input, { setData: (...args) => writes.push(args) }).defaultPrevented, false);
  assert.equal(renderer.commands.copySelection(), false);
  assert.equal(renderer.commands.selectAllBody(), false, "parent/native commands also leave the active editor alone");
  assert.equal(document.activeElement, input);
  assert.deepEqual(writes, []);
  assert.equal(input.selectionStart, 1);
  assert.equal(input.selectionEnd, 5);
});

test("disposing commands removes body select and copy handling", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("body"));
  renderer.commands.selectAllBody();
  renderer.commands.dispose();
  const writes = [];
  assert.equal(copyEvent(window, document.getElementById("content"), { setData: (...args) => writes.push(args) }).defaultPrevented, false);
  assert.equal(key(window, document, "a", { metaKey: true }).defaultPrevented, false);
  assert.equal(renderer.commands.copySelection(), false);
  assert.deepEqual(writes, []);
});

test("image load failure becomes a readable permission placeholder and is reported", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![本地图片](images/chart.png)", "markdown", "markdown"));
  document.querySelector("#content img").dispatchEvent(new window.Event("error"));
  assert.equal(renderer.report().failedImages, 1);
  assert.match(document.querySelector(".blocked-image").textContent, /本地图片不可读/);
});

test("a removed image's late failure does not change the next document's report", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![old](images/old.png)", "markdown", "markdown"));
  const oldImage = document.querySelector("#content img");
  await renderer.render(payload("# New document", "markdown", "markdown"));
  oldImage.dispatchEvent(new window.Event("error"));
  assert.equal(renderer.report().failedImages, 0);
  assert.equal(document.querySelector(".blocked-image"), null);
});

test("only explicit web/mail links reach native user-navigation handling", async (t) => {
  const { document, window } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("# Links", "markdown", "markdown"));
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
  assert.equal(document.title, "OrbisPeek");
  const bundle = await readFile(new URL("../../Sources/QuicklookUI/Resources/renderer.js", import.meta.url), "utf8");
  window.eval(bundle);
  assert.equal(typeof window.quicklook.render, "function");
  const report = await window.quicklook.render(payload("# Bundled\n\nOffline", "markdown", "markdown"));
  assert.equal(report.mode, "markdown");
  assert.equal(document.querySelector(".markdown-body h1").textContent, "Bundled");
  assert.equal(document.title, "样例 · OrbisPeek");
  assert.match(html, /connect-src 'none'/);
  assert.match(html, /img-src quicklook-resource:/);
});

test("parent commands read a separate body document while the clipboard closure remains in the shell", async (t) => {
  const { document, window } = page(t);
  const child = new JSDOM('<main tabindex="0"><p>child <strong>selection</strong></p></main>');
  t.after(() => child.window.close());
  const childDocument = child.window.document;
  const bodyView = createBodyView({ document: childDocument, root: childDocument.querySelector("main"), kind: "rendered" });
  const messages = [];
  window.webkit = { messageHandlers: { quicklook: { postMessage: (message) => messages.push(message) } } };
  child.window.webkit = { messageHandlers: { quicklook: { postMessage: () => assert.fail("child bridge must not be used") } } };
  const commands = createPreviewCommands({
    root: document.getElementById("content"), view: window,
    search() {}, clearSearch() {}, nextMatch() {},
    getBodyView: () => bodyView,
    writeClipboard: (text, requestID) => window.webkit.messageHandlers.quicklook.postMessage({ action: "copy", text, requestID }),
  });
  commands.bindDocument("parent-request");
  assert.equal(commands.selectAllBody(), true);
  assert.equal(childDocument.activeElement, bodyView.root);
  assert.equal(commands.copySelection(), true);
  assert.deepEqual(messages, [{ action: "copy", text: "child selection", requestID: "parent-request" }]);
  const editor = childDocument.createElement("textarea");
  childDocument.body.append(editor);
  editor.focus();
  assert.equal(commands.selectAllBody(), false, "an editor in the separate document retains its selection command");
  assert.equal(commands.copySelection(), false);
  commands.dispose();
});

function htmlBridge(t, document, window, { delayed = false, reject = false } = {}) {
  const prepared = new Map();
  let count = 0;
  let resolvePreparation;
  window.webkit = { messageHandlers: { quicklookHTML: { postMessage(message) {
    count += 1;
    const url = `quicklook-app://bundle/document/00000000-0000-0000-0000-${String(count).padStart(12, '0')}/content.html`;
    prepared.set(url, message.html);
    const reply = { ok: !reject, url };
    return delayed ? new Promise(resolve => { resolvePreparation = () => resolve(reply); }) : Promise.resolve(reply);
  } } } };
  const observer = new window.MutationObserver(() => {
    for (const frame of document.querySelectorAll('iframe')) {
      if (frame.__loaded || !prepared.has(frame.getAttribute('src'))) continue;
      frame.__loaded = true;
      const child = new JSDOM(prepared.get(frame.getAttribute('src')), { url: frame.getAttribute('src') });
      t.after(() => child.window.close());
      for (const image of child.window.document.images) Object.defineProperty(image, 'complete', { value: true });
      Object.defineProperty(frame, 'contentDocument', { value: child.window.document });
      Object.defineProperty(frame, 'contentWindow', { value: child.window });
      frame.dispatchEvent(new window.Event('load'));
    }
  });
  observer.observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
  t.after(() => observer.disconnect());
  return { resolve: () => resolvePreparation(), count: () => count };
}

test('HTML render resolves after the prepared sandbox child and uses its current body for search and copy', async (t) => {
  const { document, window } = page(t);
  const bridge = htmlBridge(t, document, window);
  const renderer = createRenderer(document, window);
  const promise = renderer.render(payload('<style>p{color:red}</style><h1>HTML title</h1><p class="toolbar blocked-image search-match">needle author</p><mark class="search-match">authored mark</mark><p hidden>needle hidden</p>', 'html'), 'html-request');
  assert.equal(typeof promise.then, 'function');
  const report = await promise;
  assert.equal(report.sourceMode, false);
  const frame = document.querySelector('iframe');
  assert.equal(frame.getAttribute('sandbox'), 'allow-same-origin');
  assert.equal(document.querySelector('#content h1'), null);
  const body = renderer.getBodyView();
  assert.equal(body.document, frame.contentDocument);
  assert.equal(renderer.search('needle').matches, 1, 'author class names are not decorations; hidden content is excluded');
  assert.equal(renderer.search('authored').matches, 1);
  renderer.search('');
  assert.equal(body.root.querySelector('mark.search-match').textContent, 'authored mark', 'only owned marks are removed');
  renderer.commands.selectAllBody();
  assert.equal(body.selectedPlainText(), 'HTML title\nneedle author\nauthored mark');
  assert.equal(bridge.count(), 1);
});

test('HTML source switch reuses the live prepared frame without Find controls', async (t) => {
  const { document, window } = page(t);
  const bridge = htmlBridge(t, document, window);
  const renderer = createRenderer(document, window);
  await renderer.render(payload('<p>needle</p>', 'html'), 'request');
  const frame = document.querySelector('iframe');
  document.getElementById('source-toggle').click();
  await renderer.whenIdle();
  assert.equal(frame.isConnected, true);
  assert.equal(frame.hidden, true);
  assert.equal(renderer.getBodyView().document, document);
  assert.equal(renderer.report().sourceMode, true);
  document.getElementById('source-toggle').click();
  await renderer.whenIdle();
  assert.equal(document.querySelector('iframe'), frame);
  assert.equal(frame.hidden, false);
  assert.equal(bridge.count(), 1);
  assert.equal(frame.contentDocument.querySelectorAll('mark[data-quicklook-search]').length, 0);
  assert.equal(document.getElementById('wrap-toggle').disabled, true);
});

test('late HTML preparation cannot overwrite source mode or a different file', async (t) => {
  for (const newFile of [false, true]) {
    const { document, window } = page(t);
    const bridge = htmlBridge(t, document, window, { delayed: true });
    const renderer = createRenderer(document, window);
    const old = renderer.render(payload('<p>old child</p>', 'html'), 'old');
    if (newFile) await renderer.render(payload('new file'), 'new');
    else { document.getElementById('source-toggle').click(); await renderer.whenIdle(); }
    bridge.resolve();
    const completed = await old;
    if (newFile) assert.equal(completed.stale, true);
    else { assert.equal(completed.mode, 'html'); assert.equal(completed.sourceMode, true); }
    assert.equal(document.querySelector('iframe'), null);
    assert.match(document.getElementById('content').textContent, newFile ? /new file/ : /<p>old child/);
    assert.equal(renderer.report().sourceMode, !newFile);
  }
});

test('HTML preparation failure settles to readable source with a retry action', async (t) => {
  const { document, window } = page(t);
  htmlBridge(t, document, window, { reject: true });
  const renderer = createRenderer(document, window);
  const report = await renderer.render(payload('<p>safe source</p>', 'html'), 'request');
  assert.equal(report.sourceMode, true);
  assert.match(report.notices.join(' '), /已显示原文/);
  assert.match(document.querySelector('#content code').textContent, /<p>/);
  assert.equal(document.getElementById('source-toggle').getAttribute('aria-label'), '查看预览');
});


test('all failed child images are inspected without relying on suppressed image callbacks', async (t) => {
  const { document, window } = page(t);
  htmlBridge(t, document, window);
  const renderer = createRenderer(document, window);
  const report = await renderer.render(payload('<img src="one.png"><img src="two.png">', 'html'), 'request');
  assert.equal(report.failedImages, 2);
  assert.equal(renderer.getBodyView().root.querySelectorAll('[data-quicklook-owned="failed-image"]').length, 2);
  assert.match(document.getElementById('notices').textContent, /2 张本地图片不可读/);
});

test('native commands reject stale requests and view generations and return the live query editing state', async (t) => {
  const { document, window } = page(t);
  const states = [];
  window.webkit = { messageHandlers: { quicklookState: { postMessage: state => states.push(state) } } };
  const renderer = createRenderer(document, window);
  await renderer.render(payload('# current', 'markdown'), 'request');
  const first = states.at(-1);
  assert.equal(renderer.commands.executeNative('selectAll', 'old-request', first.viewGeneration).handled, false);
  assert.equal(renderer.commands.executeNative('selectAll', 'request', first.viewGeneration).handled, true);
  document.getElementById('source-toggle').click();await renderer.whenIdle();
  assert.equal(renderer.commands.executeNative('copy', 'request', first.viewGeneration).handled, false);
  const input = document.createElement('input');document.body.append(input);input.focus();
  const queryState = states.at(-1);
  const refused = renderer.commands.executeNative('copy', 'request', queryState.viewGeneration);
  assert.equal(refused.handled, false);
  assert.equal(refused.editorFocused, true);
  assert.ok(refused.stateSequence > queryState.stateSequence);
  input.dispatchEvent(new window.CompositionEvent('compositionstart', { bubbles: true }));
  assert.equal(renderer.commands.executeNative('escape', 'request', queryState.viewGeneration).handled, false);
  assert.equal(renderer.commands.executeNative('find', 'request', queryState.viewGeneration).handled, false);
});

test('HTML preparation timeout falls back once and ignores a late reply', async (t) => {
  const { document, window } = page(t);
  const clock = windowClock(t, window);
  const bridge = htmlBridge(t, document, window, { delayed: true });
  const renderer = createRenderer(document, window);
  const pending = renderer.render(payload('<p>timeout source</p>', 'html'), 'request');
  clock.advance(1800);
  const report = await pending;
  assert.equal(report.sourceMode, true);
  bridge.resolve();
  await Promise.resolve();await Promise.resolve();
  assert.equal(document.querySelector('iframe'), null);
  assert.match(document.getElementById('content').textContent, /<p>timeout source<\/p>/);
  assert.equal(renderer.report().sourceMode, true);
});

test('HTML child load timeout settles to source before render completion', async (t) => {
  const { document, window } = page(t);
  const clock = windowClock(t, window);
  window.webkit = { messageHandlers: { quicklookHTML: { postMessage: () => Promise.resolve({ ok: true, url: 'quicklook-app://bundle/document/00000000-0000-0000-0000-000000000001/content.html' }) } } };
  const renderer = createRenderer(document, window);
  const pending = renderer.render(payload('<p>load timeout</p>', 'html'), 'request');
  for (let i = 0; i < 10; i += 1) await Promise.resolve();
  assert.ok(document.querySelector('iframe'));
  clock.advance(2200);
  const report = await pending;
  assert.equal(report.sourceMode, true);
  assert.equal(renderer.getBodyView().kind, 'source');
  assert.equal(document.querySelector('iframe'), null);
});


test('HTML reconstruction budget falls back to complete bounded source before preparing a child', async (t) => {
  const { document, window } = page(t);
  let prepares = 0;
  window.webkit = { messageHandlers: { quicklookHTML: { postMessage: () => { prepares += 1; } } } };
  const renderer = createRenderer(document, window);
  const text = '<b>a</b>'.repeat(16_000) + '<p>tail survives in source</p>';
  const report = await renderer.render(payload(text, 'html'), 'request');
  assert.equal(report.sourceMode, true);
  assert.equal(prepares, 0);
  assert.match(report.notices.join(' '), /已显示原文/);
  assert.equal(document.querySelector('.source-line code').textContent, text);
});

test('late mode-toggle completion from HTML A cannot focus the newer document B query', async (t) => {
  const { document, window } = page(t);
  const bridge = htmlBridge(t, document, window, { delayed: true });
  const renderer = createRenderer(document, window);
  const old = renderer.render(payload('<p>HTML A</p>', 'html'), 'request-A');
  const toggle = document.getElementById('source-toggle');
  toggle.click(); // A source; its completion is queued.
  toggle.click(); // A rendered; waiting on the delayed preparation.
  await renderer.render(payload('Document B'), 'request-B');
  const body = renderer.getBodyView();
  body.focus();
  assert.equal(document.activeElement, body.root);
  bridge.resolve();
  await old;
  await Promise.resolve();await Promise.resolve();
  assert.match(body.root.textContent, /Document B/);
  assert.equal(document.activeElement, body.root, 'an old mode callback must not steal B body focus');
});

test("preview has no Find UI or callable Find action and Cmd+F cannot activate it", async (t) => {
  const { document, window } = page(t);
  const copies = [];
  window.webkit = { messageHandlers: { quicklook: { postMessage: message => copies.push(message.text) } } };
  const renderer = createRenderer(document);
  await renderer.render(payload("# visible body", "markdown", "markdown"), "no-find");
  assert.deepEqual([...document.querySelectorAll('.actions button')].map(button => button.id), ['source-toggle', 'wrap-toggle']);
  assert.equal(document.querySelector('#find-button, #search-bar, #search-input, #reader-status'), null);
  assert.equal(renderer.commands.openFind, undefined);
  const event = new window.KeyboardEvent('keydown', { key: 'f', metaKey: true, bubbles: true, cancelable: true });
  document.dispatchEvent(event);
  assert.equal(event.defaultPrevented, true);
  assert.equal(document.querySelector('input'), null);
  assert.equal(renderer.commands.executeNative('find', 'no-find', 1).handled, false);
  renderer.commands.selectAllBody();
  assert.equal(renderer.commands.copySelection(), true);
});
