import { highlight, languageName } from "./languages.js";
import { formatJSON, validateJSON } from "./format.js";
import { escapeHTML, renderMarkdown } from "./markdown.js";
import { createPreviewCommands } from "./preview-commands.js";
import { createBodyView, isReadableText } from "./selection.js";
import { sanitizeHTML, HTML_EXCLUDED_SELECTOR } from "./html.js";

const MAX_PREVIEW_CHARACTERS = 524_288;
const MAX_PREVIEW_LINES = 4_000;
const MAX_JSONL_LINES = 2_000;
const MAX_HIGHLIGHT_CHARACTERS = 180_000;
const MAX_HIGHLIGHT_LINE = 8_000;
const MAX_SEARCH_MATCHES = 1_000;

export function boundedText(input, maxLines = MAX_PREVIEW_LINES) {
  const text = String(input ?? "");
  const limited = text.slice(0, MAX_PREVIEW_CHARACTERS);
  const lines = limited.split(/\r\n|\r|\n/);
  const visibleLines = lines.slice(0, maxLines);
  return {
    text: visibleLines.join("\n"),
    lineCount: lines.length,
    visibleLineCount: visibleLines.length,
    truncated: text.length > limited.length || lines.length > maxLines,
  };
}

// highlight.js emits trusted span markup. Keep those spans balanced on each
// display line so wrapping and line-number alignment do not change tokenization.
function splitHighlightedLines(html) {
  const lines = [];
  const openSpans = [];
  let line = "";
  for (const fragment of html.split(/(<\/?span\b[^>]*>|\n)/g)) {
    if (fragment === "\n") {
      lines.push(line + "</span>".repeat(openSpans.length));
      line = openSpans.join("");
    } else {
      line += fragment;
      if (fragment.startsWith("<span")) openSpans.push(fragment);
      else if (fragment === "</span>") openSpans.pop();
    }
  }
  lines.push(line);
  return lines;
}

function renderCode(text, language) {
  const useHighlight = text.length <= MAX_HIGHLIGHT_CHARACTERS
    && text.split("\n").every((line) => line.length <= MAX_HIGHLIGHT_LINE);
  let html = escapeHTML(text);
  if (useHighlight) {
    try { html = highlight(text, language); } catch { /* readable source remains */ }
  }
  const lines = splitHighlightedLines(html);
  return {
    html: `<div class="source-code" aria-label="文件内容">${lines.map((line, index) => `<div class="source-line"><span class="line-number" aria-hidden="true">${index + 1}</span><code class="hljs">${line}</code></div>`).join("")}</div>`,
    highlighted: useHighlight && languageName(language) !== "plaintext",
    notice: useHighlight ? null : "为保持流畅，较大内容使用纯文本显示。",
  };
}

function errorLocation(text, offset) {
  const lines = text.slice(0, offset ?? 0).split("\n");
  return `${lines.length}:${lines.at(-1).length + 1}`;
}

export function renderJSONLines(text, prefixTruncated = false) {
  const source = boundedText(text, MAX_JSONL_LINES);
  const lines = source.text.split("\n");
  const notices = [];
  let invalidLines = 0;
  let records = 0;
  let incompleteLines = 0;
  let highlightBudget = MAX_HIGHLIGHT_CHARACTERS;
  const html = lines.map((line, index) => {
    if (line.trim() === "") return `<div class="source-line"><span class="line-number" aria-hidden="true">${index + 1}</span><code>${escapeHTML(line)}</code></div>`;
    records += 1;
    const validation = validateJSON(line);
    const incomplete = !validation.valid && prefixTruncated && !source.truncated && index === lines.length - 1;
    if (!validation.valid && !incomplete) invalidLines += 1;
    if (incomplete) incompleteLines += 1;
    let content = escapeHTML(line);
    if (highlightBudget >= line.length && line.length <= MAX_HIGHLIGHT_LINE) {
      try { content = highlight(line, "json"); } catch { /* plain fallback */ }
      highlightBudget -= line.length;
    }
    const status = incomplete ? "记录被截断" : validation.valid ? "" : `无效 JSON：${validation.error}`;
    return `<div class="source-line jsonl-row${status ? " invalid-line" : ""}"><span class="line-number" aria-hidden="true">${index + 1}</span><code class="hljs">${content}</code>${status ? `<span class="line-state" title="${escapeHTML(status)}">${incomplete ? "截断" : "错误"}</span>` : ""}</div>`;
  }).join("");
  if (invalidLines) notices.push(`${records} 条记录中有 ${invalidLines} 行无效 JSON，原文已保留。`);
  if (incompleteLines) notices.push("末条记录尚未完整读取，显示已读取的原文。");
  if (source.truncated) notices.push(`仅显示前 ${MAX_JSONL_LINES.toLocaleString("zh-CN")} 行。`);
  return { html: `<div class="source-code jsonl-code" aria-label="JSON Lines">${html}</div>`, records, invalidLines, incompleteLines, notices, text: source.text, visibleLineCount: source.visibleLineCount };
}

export function renderDocument(payload, sourceMode = false) {
  const source = boundedText(payload.text, payload.mode === "jsonl" && !sourceMode ? MAX_JSONL_LINES : MAX_PREVIEW_LINES);
  const notices = [];
  if (payload.warning) notices.push(String(payload.warning));
  if (payload.truncated) notices.push(`文件较大，当前预览已读取的 ${formatBytes(payload.bytesRead ?? 0)}，原文件 ${formatBytes(payload.totalBytes ?? 0)}。`);
  if (source.truncated) notices.push(`为保持流畅，仅显示前 ${source.visibleLineCount.toLocaleString("zh-CN")} 行。`);
  const report = { mode: payload.mode, sourceMode, lineCount: source.lineCount, visibleLineCount: source.visibleLineCount, truncated: Boolean(payload.truncated || source.truncated), invalidLines: 0, records: 0, localImages: 0, blockedImages: 0, failedImages: 0 };
  let html;
  let copyText = source.text;
  if (payload.mode === "markdown" && !sourceMode) {
    const result = renderMarkdown(source.text, payload.resourceToken);
    html = `<article class="markdown-body">${result.html}</article>`;
    report.localImages = result.localImages;
    report.blockedImages = result.blockedImages;
    if (result.blockedImages) notices.push(`已阻止 ${result.blockedImages} 张外部或越界图片，预览保持离线。`);
  } else if (payload.mode === "json" && !sourceMode) {
    const result = formatJSON(source.text);
    const formatted = boundedText(result.text);
    copyText = formatted.text;
    const code = renderCode(formatted.text, "json");
    html = code.html;
    report.visibleLineCount = formatted.visibleLineCount;
    report.truncated ||= formatted.truncated;
    if (formatted.truncated) notices.push(`格式化预览仅显示前 ${formatted.visibleLineCount.toLocaleString("zh-CN")} 行。`);
    report.validJSON = result.valid;
    if (!result.valid) notices.push(`JSON 无法格式化（${errorLocation(source.text, result.offset)} · ${result.error}），显示原文。`);
    if (result.notice) notices.push(result.notice);
    if (code.notice) notices.push(code.notice);
  } else if (payload.mode === "jsonl" && !sourceMode) {
    const result = renderJSONLines(source.text, Boolean(payload.truncated && !source.truncated));
    html = result.html;
    copyText = result.text;
    report.records = result.records;
    report.invalidLines = result.invalidLines;
    report.incompleteLines = result.incompleteLines;
    notices.push(...result.notices);
  } else {
    const code = renderCode(source.text, payload.mode === "jsonl" ? "json" : payload.language);
    html = code.html;
    if (code.notice) notices.push(code.notice);
  }
  return { html, copyText, notices, report };
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes < 0) return "未知大小";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KiB`;
  if (bytes < 1024 ** 3) return `${(bytes / 1024 ** 2).toFixed(1)} MiB`;
  return `${(bytes / 1024 ** 3).toFixed(1)} GiB`;
}

export function createRenderer(document, target = document.defaultView) {
  const byID = (id) => document.getElementById(id);
  let payload;
  let sourceMode = false;
  let bodyView;
  let lastReport;
  let currentMatch = -1;
  let matches = [];
  let viewGeneration = 0;
  let documentGeneration = 0;
  let requestID;
  let preparedHTML;
  let pendingView = Promise.resolve();
  let imageAccessNotice;
  let imageAccessLaunchFailed = false;

  function clearImageAccessNotice() {
    imageAccessNotice?.remove();
    imageAccessNotice = undefined;
    const notices = byID("notices");
    notices.classList.remove("image-access-only");
    notices.hidden = notices.childElementCount === 0;
  }

  function canOpenImageAccess(expectedRequest, expectedGeneration) {
    return Boolean(requestID && requestID === expectedRequest && viewGeneration === expectedGeneration
      && !sourceMode && !imageAccessLaunchFailed && bodyView?.root.isConnected && ["markdown", "html"].includes(payload?.mode)
      && lastReport?.failedImages && imageAccessNotice?.isConnected
      && imageAccessNotice.parentElement === byID("notices") && !byID("notices").hidden);
  }

  function imageAccessOpenFailed(expectedRequest, expectedGeneration) {
    if (!canOpenImageAccess(expectedRequest, expectedGeneration)) return false;
    imageAccessLaunchFailed = true;
    updateImageAccessNotice();
    return true;
  }

  function updateImageAccessNotice() {
    clearImageAccessNotice();
    if (sourceMode || !bodyView || !["markdown", "html"].includes(payload?.mode) || !lastReport?.failedImages) return;
    const generation = viewGeneration;
    const fileGeneration = documentGeneration;
    const currentRequest = requestID;
    const notice = document.createElement("div");
    notice.className = "image-access-notice";
    notice.setAttribute("data-quicklook-owned", "image-access");
    const explanation = document.createElement("span");
    explanation.textContent = imageAccessLaunchFailed
      ? "请在“应用程序”中打开 OrbisPeek，在“目录权限”中选择或添加文档所在目录，再重新打开预览。"
      : `${lastReport.failedImages} 张本地图片不可读，可能缺失或未获授权。允许文档目录后重开预览。`;
    notice.append(explanation);
    if (!imageAccessLaunchFailed) {
      const button = document.createElement("button");
      button.id = "image-access-button";
      button.type = "button";
      button.textContent = "允许图片访问…";
      button.title = "打开 OrbisPeek，选择文档所在的项目或笔记目录";
      button.addEventListener("click", () => {
        if (!canOpenImageAccess(currentRequest, generation) || documentGeneration !== fileGeneration
          || imageAccessNotice !== notice) return;
        target.webkit?.messageHandlers?.quicklookState?.postMessage({ action: "openImageAccess", requestID: currentRequest, viewGeneration: generation });
      });
      notice.append(button);
    }
    const notices = byID("notices");
    notices.classList.toggle("image-access-only", notices.childElementCount === 0);
    notices.append(notice);
    notices.hidden = false;
    imageAccessNotice = notice;
  }

  function clearSearch() {
    for (const match of matches) if (match.isConnected) match.replaceWith(...match.childNodes);
    bodyView?.root.normalize();
    matches = [];
    currentMatch = -1;
    if (byID("search-count")) byID("search-count").textContent = "";
  }

  function selectMatch(index) {
    if (!matches.length) return;
    matches[currentMatch]?.classList.remove("current-match");
    currentMatch = (index + matches.length) % matches.length;
    const selected = matches[currentMatch];
    selected.classList.add("current-match");
    selected.scrollIntoView?.({ block: "center", behavior: "instant" });
    if (byID("search-count")) byID("search-count").textContent = `${currentMatch + 1} / ${matches.length}${matches.length === MAX_SEARCH_MATCHES ? "+" : ""}`;
  }

  function search(query = "") {
    clearSearch();
    const needle = String(query).toLocaleLowerCase();
    if (byID("search-count")) byID("search-count").textContent = needle ? "0 处" : "";
    if (!needle || !bodyView) return { matches: 0 };
    const bodyDocument = bodyView.document;
    const walker = bodyDocument.createTreeWalker(bodyView.root, target.NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!isReadableText(node, bodyView.root, bodyView.excludedSelector)) return target.NodeFilter.FILTER_REJECT;
        return node.textContent.toLocaleLowerCase().includes(needle) ? target.NodeFilter.FILTER_ACCEPT : target.NodeFilter.FILTER_REJECT;
      },
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      const text = node.textContent;
      const lower = text.toLocaleLowerCase();
      const fragment = bodyDocument.createDocumentFragment();
      let offset = 0;
      let found = lower.indexOf(needle);
      while (found !== -1 && matches.length < MAX_SEARCH_MATCHES) {
        fragment.append(text.slice(offset, found));
        const mark = bodyDocument.createElement("mark");
        mark.setAttribute("data-quicklook-search", "true");
        mark.className = "search-match";
        mark.textContent = text.slice(found, found + needle.length);
        fragment.append(mark);
        matches.push(mark);
        offset = found + needle.length;
        found = lower.indexOf(needle, offset);
      }
      fragment.append(text.slice(offset));
      node.replaceWith(fragment);
      if (matches.length === MAX_SEARCH_MATCHES) break;
    }
    if (matches.length) selectMatch(0);
    return { matches: matches.length, capped: matches.length === MAX_SEARCH_MATCHES };
  }

  function updateView() {
    const generation = ++viewGeneration;
    imageAccessLaunchFailed = false;
    clearImageAccessNotice();
    clearSearch();
    bodyView = undefined;
    commands.publishState();
    if (payload.mode === "html" && !sourceMode) {
      bodyView = undefined;
      if (!preparedHTML?.frame?.isConnected) byID("content").replaceChildren();
      pendingView = showHTML(generation);
      return pendingView;
    }
    const result = renderDocument(payload, sourceMode);
    const cachedFrame = payload.mode === "html" ? preparedHTML?.frame : null;
    if (cachedFrame?.isConnected) {
      cachedFrame.hidden = true;
      for (const node of [...byID("content").childNodes]) if (node !== cachedFrame) node.remove();
      const source = document.createElement("div");
      source.innerHTML = result.html;
      byID("content").append(source);
    } else byID("content").innerHTML = result.html;
    byID("content").classList.remove("html-view");
    byID("content").classList.toggle("source-view", payload.mode !== "markdown" || sourceMode);
    bodyView = createBodyView({
      document, root: byID("content"),
      kind: payload.mode === "markdown" && !sourceMode ? "rendered" : "source",
      sourceText: result.copyText,
    });
    return finishView(result);
  }

  function finishView(result) {
    lastReport = result.report;
    byID("notices").replaceChildren(...result.notices.map((notice) => {
      const paragraph = document.createElement("p");
      paragraph.textContent = notice;
      return paragraph;
    }));
    byID("notices").hidden = result.notices.length === 0;
    const sourceToggle = byID("source-toggle");
    const returnLabel = payload.mode === "json" ? "查看格式化内容" : payload.mode === "jsonl" ? "查看记录视图" : "查看预览";
    const modeLabel = sourceMode ? returnLabel : "查看原文";
    sourceToggle.title = modeLabel;
    sourceToggle.setAttribute("aria-label", modeLabel);
    sourceToggle.setAttribute("aria-pressed", String(sourceMode));
    sourceToggle.hidden = payload.mode === "code";
    sourceToggle.querySelector(".source-icon").toggleAttribute("hidden", sourceMode);
    sourceToggle.querySelector(".preview-icon").toggleAttribute("hidden", !sourceMode);
    const wrapToggle = byID("wrap-toggle");
    wrapToggle.disabled = ["markdown", "html"].includes(payload.mode) && !sourceMode;
    wrapToggle.title = wrapToggle.disabled ? "自动换行适用于原文视图" : "切换长行自动换行";
    wrapToggle.setAttribute("aria-label", wrapToggle.title);
    const format = payload.mode === "code" ? String(payload.language || "text").toUpperCase() : payload.mode === "markdown" ? "Markdown" : payload.mode.toUpperCase();
    const encoding = String(payload.encoding || "UTF-8");
    const size = formatBytes(payload.totalBytes ?? 0);
    const count = payload.mode === "jsonl" && !sourceMode ? `${lastReport.records.toLocaleString("zh-CN")} 条记录` : `${lastReport.visibleLineCount.toLocaleString("zh-CN")} 行`;
    byID("format-label").textContent = format;
    byID("file-encoding").textContent = encoding;
    byID("file-size").textContent = size;
    byID("file-count").textContent = count;
    const description = [format, encoding, size, count].join(" · ");
    byID("file-description").textContent = description;
    const fullInfo = `${payload.fileName} · ${description}`;
    byID("file-name").title = fullInfo;
    byID("file-meta").title = fullInfo;
    byID("file-name").parentElement.title = fullInfo;
    const headings = new Map();
    for (const heading of payload.mode === "markdown" && !sourceMode ? byID("content").querySelectorAll("h1,h2,h3,h4,h5,h6") : []) {
      const slug = heading.textContent.toLowerCase().trim().replace(/[^\p{L}\p{N}\s_-]/gu, "").replace(/\s+/g, "-") || "section";
      const count = headings.get(slug) || 0;
      headings.set(slug, count + 1);
      heading.id = count ? `${slug}-${count}` : slug;
    }
    const imageReport = lastReport;
    const imageGeneration = viewGeneration;
    const imageDocumentGeneration = documentGeneration;
    for (const image of payload.mode === "html" ? [] : byID("content").querySelectorAll("img")) {
      image.addEventListener("error", () => {
        if (!image.isConnected || sourceMode || viewGeneration !== imageGeneration
          || documentGeneration !== imageDocumentGeneration || lastReport !== imageReport
          || !bodyView?.root.contains(image)) return;
        const placeholder = document.createElement("span");
        placeholder.className = "blocked-image";
        placeholder.textContent = `本地图片不可读：${image.alt || "图片"}`;
        image.replaceWith(placeholder);
        imageReport.failedImages += 1;
        updateImageAccessNotice();
      }, { once: true });
    }
    updateImageAccessNotice();
    commands.publishState();
    return { ...lastReport, notices: result.notices };
  }

  function boundedWait(promise, milliseconds) {
    let timer;
    return Promise.race([promise, new Promise((_, reject) => {
      timer = target.setTimeout(() => reject(new Error("HTML preview timed out")), milliseconds);
    })]).finally(() => target.clearTimeout(timer));
  }

  async function showHTML(generation) {
    const fileGeneration = documentGeneration;
    const currentPayload = payload;
    const currentRequest = requestID;
    const isCurrent = () => documentGeneration === fileGeneration && viewGeneration === generation && !sourceMode;
    try {
      if (!preparedHTML) {
        const source = boundedText(currentPayload.text);
        const clean = sanitizeHTML(source.text, document, currentPayload.resourceToken);
        const bridge = target.webkit?.messageHandlers?.quicklookHTML;
        if (!bridge || !currentRequest) throw new Error("HTML container unavailable");
        const pending = boundedWait(Promise.resolve(bridge.postMessage({ action: "prepareHTML", html: clean.html, requestID: currentRequest })), 1800)
          .then((reply) => {
            if (!reply?.ok || !/^quicklook-app:\/\/bundle\/document\/[0-9A-F-]{36}\/content\.html$/.test(reply.url)) throw new Error("HTML preparation rejected");
            return { ...clean, url: reply.url };
          });
        preparedHTML = { pending };
      }
      const prepared = preparedHTML;
      const clean = await prepared.pending;
      if (!isCurrent()) return { stale: true };
      let frame = prepared.frame;
      if (!frame) {
        frame = document.createElement("iframe");
        frame.className = "html-document";
        frame.title = "HTML 预览";
        frame.setAttribute("sandbox", "allow-same-origin");
        prepared.frame = frame;
        prepared.loaded = boundedWait(new Promise((resolve, reject) => {
          frame.addEventListener("load", () => {
            if (frame.contentDocument?.URL === clean.url && frame.contentDocument.body) resolve();
          });
          frame.addEventListener("error", () => reject(new Error("HTML load failed")), { once: true });
        }), 2200);
        byID("content").replaceChildren(frame);
        frame.src = clean.url;
      } else {
        for (const node of [...byID("content").childNodes]) if (node !== frame) node.remove();
        if (!frame.isConnected) byID("content").append(frame);
        frame.hidden = false;
      }
      await prepared.loaded;
      if (!isCurrent()) return { stale: true };
      const child = frame.contentDocument;
      if (!(child?.URL === clean.url || child?.URL.startsWith(clean.url + "#")) || !child.body) throw new Error("HTML document unavailable");
      // No child callbacks run in the no-script sandbox. Inspect from the shell.
      const deadline = Date.now() + 1000;
      while ([...child.images].some((image) => !image.complete) && Date.now() < deadline) {
        await new Promise((resolve) => target.setTimeout(resolve, 30));
        if (!isCurrent()) return { stale: true };
      }
      let failedImages = 0;
      for (const image of [...child.images]) {
        if (image.complete && image.naturalWidth > 0) continue;
        const placeholder = child.createElement("span");
        placeholder.setAttribute("data-quicklook-owned", "failed-image");
        placeholder.textContent = `本地图片不可读：${image.alt || "图片"}`;
        image.replaceWith(placeholder);
        failedImages += 1;
      }
      prepared.failedImages = (prepared.failedImages || 0) + failedImages;
      byID("content").classList.remove("source-view");
      byID("content").classList.add("html-view");
      child.body.tabIndex = 0;
      bodyView = createBodyView({ document: child, root: child.body, kind: "html", excludedSelector: HTML_EXCLUDED_SELECTOR });
      const result = renderDocument(currentPayload, true);
      result.report.sourceMode = false;
      Object.assign(result.report, { localImages: clean.localImages, blockedImages: clean.blockedImages, failedImages: prepared.failedImages });
      if (clean.blockedImages) result.notices.push(`已阻止 ${clean.blockedImages} 张外部或越界图片，预览保持离线。`);
      return finishView(result);
    } catch {
      if (!isCurrent()) return { stale: true };
      preparedHTML = undefined;
      sourceMode = true;
      const result = renderDocument(currentPayload, true);
      result.notices.push("HTML 预览暂不可用，已显示原文。可再次切换预览。");
      byID("content").innerHTML = result.html;
      byID("content").classList.remove("html-view");
      byID("content").classList.add("source-view");
      bodyView = createBodyView({ document, root: byID("content"), kind: "source", sourceText: result.copyText });
      return finishView(result);
    }
  }

  async function render(input, nextRequestID, options) {
    documentGeneration += 1;
    preparedHTML = undefined;
    requestID = nextRequestID;
    bodyView = undefined;
    commands.bindDocument(requestID, options);
    payload = {
      ...input,
      text: String(input?.text ?? ""),
      fileName: String(input?.fileName ?? "文档"),
      language: input?.mode === "html" ? "html" : input?.language,
      mode: ["markdown", "html", "json", "jsonl", "code"].includes(input?.mode) ? input.mode : "code",
    };
    sourceMode = false;
    document.body.classList.add("wrap-lines");
    byID("wrap-toggle").setAttribute("aria-pressed", "true");
    const extensionIndex = payload.fileName.lastIndexOf(".");
    const hasExtension = extensionIndex > 0 && extensionIndex < payload.fileName.length - 1;
    byID("file-basename").textContent = hasExtension ? payload.fileName.slice(0, extensionIndex) : payload.fileName;
    byID("file-extension").textContent = hasExtension ? payload.fileName.slice(extensionIndex) : "";
    document.title = `${payload.fileName} · OrbisPeek`;
    document.body.classList.remove("empty");
    const fileGeneration = documentGeneration;
    pendingView = Promise.resolve(updateView());
    // A mode click may supersede the first asynchronous HTML view while the
    // native render call is awaiting it. Complete only the latest settled view
    // for this file so the receipt describes what is actually displayed.
    while (documentGeneration === fileGeneration) {
      const pending = pendingView;
      const result = await pending;
      if (documentGeneration !== fileGeneration) break;
      if (pending === pendingView && !result.stale) return result;
    }
    return { stale: true };
  }

  function writeClipboard(text, requestID) {
    const bridge = target.webkit?.messageHandlers?.quicklook;
    if (bridge) return bridge.postMessage({ action: "copy", text, requestID, viewGeneration });
    if (target.navigator.clipboard?.writeText) return target.navigator.clipboard.writeText(text);
    throw new Error("clipboard unavailable");
  }

  const commands = createPreviewCommands({
    root: byID("content"),
    view: target,
    getBodyView: () => bodyView,
    writeClipboard,
    getViewGeneration: () => viewGeneration,
    publishNativeState: (state) => target.webkit?.messageHandlers?.quicklookState?.postMessage({ action: "commandState", ...state }),
  });

  byID("source-toggle").addEventListener("click", () => {
    sourceMode = !sourceMode;
    pendingView = Promise.resolve(updateView());
  });
  byID("wrap-toggle").addEventListener("click", () => {
    const wrap = document.body.classList.toggle("wrap-lines");
    byID("wrap-toggle").setAttribute("aria-pressed", String(wrap));
  });
  byID("content").addEventListener("click", (event) => {
    const link = event.target.closest("a");
    if (!link) return;
    const href = link.getAttribute("href");
    if (href?.startsWith("#")) {
      event.preventDefault();
      try { document.getElementById(decodeURIComponent(href.slice(1)))?.scrollIntoView?.({ block: "start" }); } catch { /* malformed link */ }
      return;
    }
    // The native navigation delegate opens only explicit, user-activated web/mail links.
    // All local/custom URLs remain inside the preview's resource boundary.
    if (!/^(https?:|mailto:)/i.test(href || "")) event.preventDefault();
  });
  return { render, search, commands, canOpenImageAccess, imageAccessOpenFailed, getBodyView: () => bodyView, sanitizeHTML: (source, token) => sanitizeHTML(source, document, token), report: () => ({ ...lastReport }), whenIdle: () => pendingView, supportedModes: ["markdown", "html", "json", "jsonl", "code"] };
}

if (globalThis.window?.document?.getElementById("content")) {
  globalThis.window.quicklook = createRenderer(globalThis.window.document, globalThis.window);
}
