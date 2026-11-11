import { highlight, languageName } from "./languages.js";
import { formatJSON, validateJSON } from "./format.js";
import { escapeHTML, renderMarkdown } from "./markdown.js";

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
    html: `<div class="source-code" aria-label="文件内容">${lines.map((line, index) => `<div class="source-line"><span class="line-number" aria-hidden="true">${index + 1}</span><code class="hljs">${line || "&#8203;"}</code></div>`).join("")}</div>`,
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
    if (line.trim() === "") return `<div class="source-line"><span class="line-number" aria-hidden="true">${index + 1}</span><code>&#8203;</code></div>`;
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
    const result = renderMarkdown(source.text);
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
  let copyText = "";
  let lastReport;
  let currentMatch = -1;
  let matches = [];
  let searchTimer;

  function clearSearch() {
    for (const match of byID("content").querySelectorAll("mark.search-match")) match.replaceWith(...match.childNodes);
    byID("content").normalize();
    matches = [];
    currentMatch = -1;
  }

  function selectMatch(index) {
    if (!matches.length) return;
    matches[currentMatch]?.classList.remove("current-match");
    currentMatch = (index + matches.length) % matches.length;
    const selected = matches[currentMatch];
    selected.classList.add("current-match");
    selected.scrollIntoView?.({ block: "center", behavior: "instant" });
    byID("search-count").textContent = `${currentMatch + 1} / ${matches.length}${matches.length === MAX_SEARCH_MATCHES ? "+" : ""}`;
  }

  function search(query = byID("search-input").value) {
    clearSearch();
    const needle = String(query).toLocaleLowerCase();
    byID("search-count").textContent = needle ? "0 处" : "";
    if (!needle) return { matches: 0 };
    const walker = document.createTreeWalker(byID("content"), target.NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (node.parentElement.closest(".line-number, .line-state, .blocked-image")) return target.NodeFilter.FILTER_REJECT;
        return node.textContent.toLocaleLowerCase().includes(needle) ? target.NodeFilter.FILTER_ACCEPT : target.NodeFilter.FILTER_REJECT;
      },
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      const text = node.textContent;
      const lower = text.toLocaleLowerCase();
      const fragment = document.createDocumentFragment();
      let offset = 0;
      let found = lower.indexOf(needle);
      while (found !== -1 && matches.length < MAX_SEARCH_MATCHES) {
        fragment.append(text.slice(offset, found));
        const mark = document.createElement("mark");
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
    clearSearch();
    const result = renderDocument(payload, sourceMode);
    byID("content").innerHTML = result.html;
    byID("content").classList.toggle("source-view", payload.mode !== "markdown" || sourceMode);
    copyText = result.copyText;
    lastReport = result.report;
    byID("notices").replaceChildren(...result.notices.map((notice) => {
      const paragraph = document.createElement("p");
      paragraph.textContent = notice;
      return paragraph;
    }));
    byID("notices").hidden = result.notices.length === 0;
    byID("source-toggle").textContent = sourceMode ? "查看预览" : "查看原文";
    byID("source-toggle").setAttribute("aria-pressed", String(sourceMode));
    byID("source-toggle").hidden = payload.mode === "code";
    const meta = [String(payload.encoding || "UTF-8"), formatBytes(payload.totalBytes ?? 0)];
    if (payload.mode === "jsonl" && !sourceMode) meta.push(`${lastReport.records} 条记录`);
    else meta.push(`${lastReport.visibleLineCount.toLocaleString("zh-CN")} 行`);
    byID("file-meta").textContent = meta.join(" · ");
    const headings = new Map();
    for (const heading of byID("content").querySelectorAll("h1,h2,h3,h4,h5,h6")) {
      const slug = heading.textContent.toLowerCase().trim().replace(/[^\p{L}\p{N}\s_-]/gu, "").replace(/\s+/g, "-") || "section";
      const count = headings.get(slug) || 0;
      headings.set(slug, count + 1);
      heading.id = count ? `${slug}-${count}` : slug;
    }
    const imageReport = lastReport;
    for (const image of byID("content").querySelectorAll("img")) {
      image.addEventListener("error", () => {
        if (!image.isConnected) return;
        const placeholder = document.createElement("span");
        placeholder.className = "blocked-image";
        placeholder.textContent = `本地图片不可读：${image.alt || "图片"}（检查目录访问权限）`;
        image.replaceWith(placeholder);
        imageReport.failedImages += 1;
      }, { once: true });
    }
    if (byID("search-input").value) search();
    return { ...lastReport, notices: result.notices };
  }

  function render(input) {
    payload = {
      ...input,
      text: String(input?.text ?? ""),
      fileName: String(input?.fileName ?? "文档"),
      mode: ["markdown", "json", "jsonl", "code"].includes(input?.mode) ? input.mode : "code",
    };
    sourceMode = false;
    byID("file-name").textContent = payload.fileName;
    document.title = `${payload.fileName} · Quicklook`;
    byID("format-label").textContent = payload.mode === "code" ? String(payload.language || "text").toUpperCase() : payload.mode.toUpperCase();
    document.body.classList.remove("empty");
    return updateView();
  }

  byID("source-toggle").addEventListener("click", () => { sourceMode = !sourceMode; updateView(); });
  byID("wrap-toggle").addEventListener("click", () => {
    const wrap = document.body.classList.toggle("wrap-lines");
    byID("wrap-toggle").setAttribute("aria-pressed", String(wrap));
  });
  byID("copy-button").addEventListener("click", async () => {
    try {
      const bridge = target.webkit?.messageHandlers?.quicklook;
      if (bridge) bridge.postMessage({ action: "copy", text: copyText });
      else if (target.navigator.clipboard?.writeText) await target.navigator.clipboard.writeText(copyText);
      else throw new Error("clipboard unavailable");
      byID("copy-button").textContent = "已复制";
    } catch {
      byID("copy-button").textContent = "请选择文本复制";
    }
    target.setTimeout(() => { byID("copy-button").textContent = "复制"; }, 1500);
  });
  byID("find-button").addEventListener("click", () => {
    byID("search-bar").hidden = !byID("search-bar").hidden;
    if (!byID("search-bar").hidden) byID("search-input").focus();
    else { byID("search-input").value = ""; clearSearch(); }
  });
  byID("search-input").addEventListener("input", () => {
    target.clearTimeout(searchTimer);
    searchTimer = target.setTimeout(() => search(), 120);
  });
  byID("search-input").addEventListener("keydown", (event) => {
    if (event.key === "Enter") { event.preventDefault(); selectMatch(currentMatch + (event.shiftKey ? -1 : 1)); }
  });
  byID("search-next").addEventListener("click", () => selectMatch(currentMatch + 1));
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
  document.addEventListener("keydown", (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "f") {
      event.preventDefault(); byID("search-bar").hidden = false; byID("search-input").focus();
    }
  });
  return { render, search, report: () => ({ ...lastReport }), supportedModes: ["markdown", "json", "jsonl", "code"] };
}

if (globalThis.window?.document?.getElementById("content")) {
  globalThis.window.quicklook = createRenderer(globalThis.window.document, globalThis.window);
}
