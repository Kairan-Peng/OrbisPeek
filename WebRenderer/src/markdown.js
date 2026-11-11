// Task-list token adaptation is derived from FreeLook, MIT License.
// Copyright © 2026 Neo Lee. Source: neolee/freelook, d3f002589917f51279b49ea8b12b3bb343dd82dc.
// Full upstream license is retained in WebRenderer/licenses/FreeLook-MIT.txt.
import MarkdownIt from "markdown-it";
import { highlight, languageName } from "./languages.js";

export function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

function taskListPlugin(markdownIt) {
  markdownIt.core.ruler.after("inline", "quicklook-task-list", (state) => {
    for (let index = 2; index < state.tokens.length; index += 1) {
      const inlineToken = state.tokens[index];
      if (inlineToken.type !== "inline" || !inlineToken.children?.length) continue;
      const paragraphToken = state.tokens[index - 1];
      const listItemToken = state.tokens[index - 2];
      if (paragraphToken?.type !== "paragraph_open" || listItemToken?.type !== "list_item_open") continue;
      const firstChild = inlineToken.children[0];
      if (!firstChild || firstChild.type !== "text") continue;
      const match = firstChild.content.match(/^\[([ xX])\]\s+/);
      if (!match) continue;
      const isChecked = match[1].toLowerCase() === "x";
      firstChild.content = firstChild.content.slice(match[0].length);
      if (firstChild.content.length === 0) inlineToken.children.shift();
      listItemToken.attrJoin("class", "task-list-item");
      const checkboxToken = new state.Token("html_inline", "", 0);
      checkboxToken.content = `<input class="task-list-item-checkbox" type="checkbox"${isChecked ? " checked" : ""} disabled>`;
      inlineToken.children.unshift(checkboxToken);
    }
  });
}

export function localImageURL(source) {
  let path;
  // Strip URL metadata before decoding: %3F and %23 can be literal filename characters.
  try { path = decodeURIComponent(String(source).split(/[?#]/, 1)[0]); } catch { return null; }
  if (/^[a-z][a-z0-9+.-]*:/i.test(path) || path.startsWith("/") || /[\\\u0000-\u001f]/.test(path)) return null;
  const components = path.split("/").filter((component) => component && component !== ".");
  if (!components.length || components.includes("..")) return null;
  return `quicklook-resource://local/${components.map(encodeURIComponent).join("/")}`;
}

const markdown = new MarkdownIt({
  html: false,
  linkify: true,
  maxNesting: 32,
  highlight(content, language) {
    if (content.length > 150_000 || content.split("\n").some((line) => line.length > 8_000)) return escapeHTML(content);
    return highlight(content, languageName(language));
  },
}).use(taskListPlugin);

markdown.renderer.rules.image = (tokens, index, _options, environment) => {
  const token = tokens[index];
  const source = localImageURL(token.attrGet("src") || "");
  const alt = escapeHTML(token.content || "图片");
  if (!source) {
    environment.blockedImages += 1;
    return `<span class="blocked-image" role="img" aria-label="图片已阻止">图片已阻止：${alt}</span>`;
  }
  environment.localImages += 1;
  return `<img src="${escapeHTML(source)}" alt="${alt}" loading="lazy" decoding="async">`;
};

export function renderMarkdown(text) {
  const environment = { blockedImages: 0, localImages: 0 };
  return { html: markdown.render(text, environment), ...environment };
}
