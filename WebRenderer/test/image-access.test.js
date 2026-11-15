import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { JSDOM } from "jsdom";
import { createRenderer } from "../src/renderer.js";

const shell = await readFile(new URL("../src/index.html", import.meta.url), "utf8");
const token = "D74B9B4A-7C26-4A98-8A67-30E256E963DE";
const payload = (text, mode = "markdown") => ({
  text, mode, language: mode, fileName: `image.${mode === "html" ? "html" : "md"}`,
  resourceToken: token, encoding: "UTF-8", totalBytes: Buffer.byteLength(text), bytesRead: Buffer.byteLength(text), truncated: false,
});

function page(t) {
  const dom = new JSDOM(shell, { url: "https://quicklook.invalid/", runScripts: "outside-only" });
  t.after(() => dom.window.close());
  const messages = [];
  const copies = [];
  dom.window.webkit = { messageHandlers: {
    quicklookState: { postMessage: message => messages.push(message) },
    quicklook: { postMessage: message => copies.push(message) },
  } };
  return { window: dom.window, document: dom.window.document, messages, copies,
    accessMessages: () => messages.filter(message => message.action === "openImageAccess") };
}

function failedImages(document, window) {
  for (const image of document.querySelectorAll("#content img")) image.dispatchEvent(new window.Event("error"));
}

function staticHTML(t, document, window) {
  const prepared = new Map();
  let count = 0;
  window.webkit.messageHandlers.quicklookHTML = { postMessage(message) {
    const url = `quicklook-app://bundle/document/00000000-0000-0000-0000-${String(++count).padStart(12, "0")}/content.html`;
    prepared.set(url, message.html);
    return Promise.resolve({ ok: true, url });
  } };
  const observer = new window.MutationObserver(() => {
    for (const frame of document.querySelectorAll("iframe")) {
      if (frame.__loaded || !prepared.has(frame.getAttribute("src"))) continue;
      frame.__loaded = true;
      const child = new JSDOM(prepared.get(frame.getAttribute("src")), { url: frame.getAttribute("src") });
      t.after(() => child.window.close());
      for (const image of child.window.document.images) Object.defineProperty(image, "complete", { value: true });
      Object.defineProperty(frame, "contentDocument", { value: child.window.document });
      Object.defineProperty(frame, "contentWindow", { value: child.window });
      frame.dispatchEvent(new window.Event("load"));
    }
  });
  observer.observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["src"] });
  t.after(() => observer.disconnect());
}

test("readable previews and policy-blocked images do not invite directory authorization", async (t) => {
  for (const source of ["# Readable", "![local](images/a.png)", "![remote](https://example.invalid/a.png)\n\n![svg](a.svg)\n\n![outside](../a.png)"]) {
    const { document, window, accessMessages } = page(t);
    const renderer = createRenderer(document, window);
    await renderer.render(payload(source), "readable");
    assert.equal(document.getElementById("image-access-button"), null, source);
    assert.equal(accessMessages().length, 0);
    assert.deepEqual([...document.querySelectorAll(".actions button")].map(button => button.id), ["source-toggle", "wrap-toggle"]);
  }
});

test("multiple failed local images share one quiet parent notice and only a click opens access management", async (t) => {
  const { document, window, accessMessages, messages } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![one](one.png)\n\n![two](two.png)"), "request-images");
  failedImages(document, window);
  assert.equal(renderer.report().failedImages, 2);
  assert.equal(document.querySelectorAll(".blocked-image").length, 2);
  assert.match(document.querySelector(".blocked-image").textContent, /one/);
  assert.equal(document.querySelectorAll(".image-access-notice").length, 1);
  assert.equal(document.querySelectorAll("#image-access-button").length, 1);
  assert.match(document.getElementById("notices").textContent, /2 张本地图片不可读.*可能缺失或未获授权/);
  assert.ok(document.getElementById("notices").classList.contains("image-access-only"));
  assert.equal(accessMessages().length, 0, "render/error events never open the host");
  const generation = messages.filter(message => message.action === "commandState").at(-1).viewGeneration;
  document.getElementById("image-access-button").click();
  assert.deepEqual(accessMessages(), [{ action: "openImageAccess", requestID: "request-images", viewGeneration: generation }]);
});

test("source mode, new documents and detached old buttons revoke the prior access action", async (t) => {
  const { document, window, accessMessages } = page(t);
  const renderer = createRenderer(document, window);
  const source = "![one](one.png)\n\nBody";
  await renderer.render(payload(source), "first");
  failedImages(document, window);
  const oldButton = document.getElementById("image-access-button");
  document.getElementById("source-toggle").click();
  await renderer.whenIdle();
  assert.equal(document.getElementById("image-access-button"), null);
  assert.equal(document.getElementById("notices").hidden, true);
  oldButton.click();
  assert.deepEqual(accessMessages(), []);
  renderer.commands.selectAllBody();
  assert.equal(renderer.getBodyView().selectedPlainText(), source);
  document.getElementById("source-toggle").click();
  await renderer.whenIdle();
  failedImages(document, window);
  const secondButton = document.getElementById("image-access-button");
  await renderer.render(payload("# New"), "second");
  secondButton.click();
  assert.equal(document.getElementById("image-access-button"), null);
  assert.deepEqual(accessMessages(), []);
});

test("the native live-DOM recheck accepts only the current rendered failure entry", async (t) => {
  const { document, window, messages } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![one](one.png)"), "live-current");
  const generation = messages.filter(message => message.action === "commandState").at(-1).viewGeneration;
  assert.equal(renderer.canOpenImageAccess("live-current", generation), false);
  failedImages(document, window);
  assert.equal(renderer.canOpenImageAccess("live-current", generation), true);
  assert.equal(renderer.canOpenImageAccess("old-request", generation), false);
  assert.equal(renderer.canOpenImageAccess("live-current", generation - 1), false);
  document.getElementById("source-toggle").click();
  await renderer.whenIdle();
  assert.equal(renderer.canOpenImageAccess("live-current", generation), false);
  await renderer.render(payload("# New"), "live-new");
  assert.equal(renderer.canOpenImageAccess("live-current", generation), false);
});

test("a failed host open replaces only the current action with a persistent manual path and keeps copy clean", async (t) => {
  const { document, window, messages, accessMessages, copies } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![one](one.png)\n\n![two](two.png)\n\n正文 **中文加粗**。"), "failed-open");
  const images = [...document.querySelectorAll("#content img")];
  images[0].dispatchEvent(new window.Event("error"));
  const generation = messages.filter(message => message.action === "commandState").at(-1).viewGeneration;
  const oldButton = document.getElementById("image-access-button");
  assert.equal(renderer.imageAccessOpenFailed("failed-open", generation), true);
  assert.equal(renderer.canOpenImageAccess("failed-open", generation), false);
  assert.equal(document.getElementById("image-access-button"), null);
  assert.equal(document.getElementById("notices").textContent, "请在“应用程序”中打开 OrbisPeek，在“目录权限”中选择或添加文档所在目录，再重新打开预览。");
  oldButton.click();
  images[1].dispatchEvent(new window.Event("error"));
  assert.equal(document.getElementById("image-access-button"), null, "a later image failure cannot restore a known-failed action");
  assert.match(document.getElementById("notices").textContent, /“应用程序”/);
  assert.equal(renderer.imageAccessOpenFailed("failed-open", generation), false);
  assert.deepEqual(accessMessages(), []);
  assert.deepEqual(copies, [], "failure feedback does not copy anything automatically");
  renderer.commands.selectAllBody();
  assert.equal(renderer.getBodyView().selectedPlainText(), "正文 中文加粗。");
  assert.equal(renderer.commands.copySelection(), true);
  assert.equal(copies.at(-1).text, "正文 中文加粗。");
});

test("stale failure completions cannot change source mode or a newer document's live action", async (t) => {
  const { document, window, messages } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![old](old.png)"), "old-open");
  failedImages(document, window);
  const oldGeneration = messages.filter(message => message.action === "commandState").at(-1).viewGeneration;
  document.getElementById("source-toggle").click();
  await renderer.whenIdle();
  assert.equal(renderer.imageAccessOpenFailed("old-open", oldGeneration), false);
  assert.equal(document.getElementById("notices").hidden, true);
  await renderer.render(payload("![new](new.png)"), "new-open");
  failedImages(document, window);
  const generation = messages.filter(message => message.action === "commandState").at(-1).viewGeneration;
  const button = document.getElementById("image-access-button");
  assert.equal(renderer.imageAccessOpenFailed("old-open", generation), false);
  assert.equal(renderer.imageAccessOpenFailed("new-open", oldGeneration), false);
  assert.equal(document.getElementById("image-access-button"), button);
  assert.equal(renderer.canOpenImageAccess("new-open", generation), true);
  assert.doesNotMatch(document.getElementById("notices").textContent, /“应用程序”/);
});

test("HTML host-open failure feedback stays in the parent and resets only with a new view", async (t) => {
  const { document, window, messages } = page(t);
  staticHTML(t, document, window);
  const renderer = createRenderer(document, window);
  await renderer.render(payload('<p>HTML body</p><img src="one.png">', "html"), "html-open-failed");
  const child = renderer.getBodyView().document;
  const generation = messages.filter(message => message.action === "commandState").at(-1).viewGeneration;
  assert.equal(renderer.imageAccessOpenFailed("html-open-failed", generation), true);
  assert.match(document.getElementById("notices").textContent, /“应用程序”/);
  assert.doesNotMatch(child.body.textContent, /“应用程序”/);
  assert.equal(renderer.canOpenImageAccess("html-open-failed", generation), false);
  document.getElementById("source-toggle").click();
  await renderer.whenIdle();
  document.getElementById("source-toggle").click();
  await renderer.whenIdle();
  const nextGeneration = messages.filter(message => message.action === "commandState").at(-1).viewGeneration;
  assert.ok(document.getElementById("image-access-button"));
  assert.equal(renderer.canOpenImageAccess("html-open-failed", nextGeneration), true);
  assert.equal(renderer.imageAccessOpenFailed("html-open-failed", generation), false);
});

test("an old failed-image callback cannot add a notice even when its node is reattached to a newer document", async (t) => {
  const { document, window, accessMessages } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![old](old.png)"), "old");
  const oldImage = document.querySelector("#content img");
  await renderer.render(payload("# New"), "new");
  document.getElementById("content").append(oldImage);
  oldImage.dispatchEvent(new window.Event("error"));
  assert.equal(renderer.report().failedImages, 0);
  assert.equal(document.getElementById("image-access-button"), null);
  assert.deepEqual(accessMessages(), []);
});

test("the permission prompt and failed placeholders stay out of selected plain-text copy", async (t) => {
  const { document, window, copies } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![illustration](one.png)\n\n正文 **中文加粗** 与 `inline_code`。"), "copy-current");
  failedImages(document, window);
  const range = document.createRange();
  range.selectNodeContents(document.body);
  const selection = document.getSelection();
  selection.removeAllRanges(); selection.addRange(range);
  assert.equal(renderer.getBodyView().selectedPlainText(), "正文 中文加粗 与 inline_code。");
  assert.equal(renderer.commands.copySelection(), true);
  assert.equal(copies.at(-1).text, "正文 中文加粗 与 inline_code。");
  assert.equal(document.querySelector("#find-button,#search-bar,#copy-button"), null);
});

test("HTML image failures expose one trusted-parent action and keep it outside the authored child", async (t) => {
  const { document, window, accessMessages } = page(t);
  staticHTML(t, document, window);
  const renderer = createRenderer(document, window);
  await renderer.render(payload('<p>HTML body</p><img src="one.png" alt="one"><img src="two.png" alt="two"><img src="https://example.invalid/remote.png">', "html"), "html-current");
  const child = renderer.getBodyView().document;
  const button = document.getElementById("image-access-button");
  assert.ok(button);
  assert.equal(button.ownerDocument, document);
  assert.equal(child.querySelector("#image-access-button,.image-access-notice,button"), null);
  assert.equal(child.querySelectorAll('[data-quicklook-owned="failed-image"]').length, 2);
  assert.equal(renderer.report().failedImages, 2);
  assert.equal(renderer.report().blockedImages, 1);
  renderer.commands.selectAllBody();
  assert.equal(renderer.getBodyView().selectedPlainText(), "HTML body");
  assert.deepEqual(accessMessages(), []);
  button.click();
  assert.equal(accessMessages().length, 1);
  assert.equal(accessMessages()[0].requestID, "html-current");
  document.getElementById("source-toggle").click();
  await renderer.whenIdle();
  assert.equal(document.getElementById("image-access-button"), null);
  button.click();
  assert.equal(accessMessages().length, 1);
  document.getElementById("source-toggle").click();
  await renderer.whenIdle();
  assert.equal(document.querySelectorAll("#image-access-button").length, 1);
});

test("authored custom-protocol links remain blocked even beside the controlled permission action", async (t) => {
  const { document, window, accessMessages } = page(t);
  const renderer = createRenderer(document, window);
  await renderer.render(payload("![local](one.png)"), "custom-link");
  failedImages(document, window);
  const anchor = document.createElement("a");
  anchor.href = "orbispeek://image-access";
  anchor.textContent = "author link";
  document.getElementById("content").append(anchor);
  const event = new window.MouseEvent("click", { bubbles: true, cancelable: true });
  anchor.dispatchEvent(event);
  assert.equal(event.defaultPrevented, true);
  assert.deepEqual(accessMessages(), []);
});

test("the bundled renderer exposes the current-failure recheck and sends only its explicit parent action", async (t) => {
  const { document, window, messages, accessMessages } = page(t);
  const bundle = await readFile(new URL("../../Sources/QuicklookUI/Resources/renderer.js", import.meta.url), "utf8");
  window.eval(bundle);
  const renderer = window.quicklook;
  assert.equal(typeof renderer.canOpenImageAccess, "function");
  assert.equal(typeof renderer.imageAccessOpenFailed, "function");
  await renderer.render(payload("![local](one.png)"), "bundle-permission");
  failedImages(document, window);
  const generation = messages.filter(message => message.action === "commandState").at(-1).viewGeneration;
  assert.equal(renderer.canOpenImageAccess("bundle-permission", generation), true);
  assert.equal(accessMessages().length, 0);
  document.getElementById("image-access-button").click();
  assert.deepEqual(JSON.parse(JSON.stringify(accessMessages())), [{ action: "openImageAccess", requestID: "bundle-permission", viewGeneration: generation }]);
});
