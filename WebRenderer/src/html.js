import { localImageURL } from "./markdown.js";

const HTML_NAMESPACE = "http://www.w3.org/1999/xhtml";
const ELEMENTS = new Set("html head body a abbr address article aside b bdi bdo blockquote br caption cite code col colgroup dd del details dfn div dl dt em figcaption figure footer h1 h2 h3 h4 h5 h6 header hgroup hr i img ins kbd li main mark nav ol p pre q rp rt ruby s samp section small span strong style sub summary sup table tbody td tfoot th thead time tr u ul var wbr".split(" "));
// Drop whole subtrees whose parsing modes or descendants could reactivate markup.
const DROP = new Set("script noscript xmp plaintext iframe frame frameset object embed applet form input textarea select option optgroup button fieldset legend video audio picture source track canvas svg math template title base meta link".split(" "));
const GLOBAL_ATTRIBUTES = new Set("id class style title lang dir hidden".split(" "));
const ELEMENT_ATTRIBUTES = {
  a: new Set(["href"]), img: new Set(["alt", "width", "height"]),
  td: new Set(["colspan", "rowspan", "headers"]), th: new Set(["colspan", "rowspan", "headers", "scope", "abbr"]),
  col: new Set(["span"]), colgroup: new Set(["span"]), ol: new Set(["start", "reversed", "type"]),
  li: new Set(["value"]), details: new Set(["open"]), time: new Set(["datetime"]),
};
const RASTER = /\.(?:png|jpe?g|gif|webp|heic|heif|bmp|tiff?)$/i;
export const HTML_EXCLUDED_SELECTOR = "script, style, template, [hidden], [aria-hidden='true'], [data-quicklook-owned]";

function safeLink(value) {
  if (!value || /[\u0000-\u0020\u007f\\]/.test(value)) return null;
  if (value.startsWith("#")) return value;
  if (!/^(https?:|mailto:)/i.test(value)) return null;
  try { return ["http:", "https:", "mailto:"].includes(new URL(value).protocol) ? value : null; } catch { return null; }
}

/** Parse only in inactive documents and rebuild in a template's inert owner.
 * The live document's implementation creates a separate full HTML document;
 * that parser has no browsing context. Disconnected live-owned images can fetch
 * on src assignment, so no authored node is rebuilt in the live document. */
export function sanitizeHTML(source, document, resourceToken) {
  const template = document.createElement("template");
  template.innerHTML = String(source ?? "");
  const inert = template.content.ownerDocument;
  // A full inactive document parser retains authored html/body attributes.
  // Both this parser and the reconstruction owner have no browsing context.
  const parsed = document.implementation.createHTMLDocument("");
  if (parsed.defaultView !== null || inert.defaultView !== null) throw new Error("HTML parser must be inactive");
  parsed.open();
  parsed.write(String(source ?? ""));
  parsed.close();
  const output = inert.createElement("div");
  let localImages = 0;
  let blockedImages = 0;
  let remaining = 30_000;

  function reconstruct(node, parent, depth) {
    if (--remaining < 0 || depth > 64) throw new Error("HTML reconstruction budget exceeded");
    if (node.nodeType === 3) { parent.append(inert.createTextNode(node.data)); return; }
    if (node.nodeType !== 1 || node.namespaceURI !== HTML_NAMESPACE) return;
    const tag = node.localName;
    if (DROP.has(tag)) return;
    if (!ELEMENTS.has(tag)) {
      for (const child of node.childNodes) reconstruct(child, parent, depth + 1);
      return;
    }
    const element = inert.createElementNS(HTML_NAMESPACE, tag);
    for (const attr of node.attributes) {
      if (attr.namespaceURI || attr.prefix) continue;
      const name = attr.localName;
      if (!GLOBAL_ATTRIBUTES.has(name) && !ELEMENT_ATTRIBUTES[tag]?.has(name) && !/^aria-[a-z-]+$/.test(name)) continue;
      if (name === "href") {
        const href = safeLink(attr.value);
        if (href) element.setAttribute("href", href);
      } else element.setAttribute(name, attr.value);
    }
    if (tag === "img") {
      const source = node.getAttribute("src") || "";
      let path;
      try { path = decodeURIComponent(source.split(/[?#]/, 1)[0]); } catch { /* rejected below */ }
      const url = path && RASTER.test(path) ? localImageURL(source, resourceToken) : null;
      if (!url) {
        blockedImages += 1;
        const placeholder = inert.createElement("span");
        placeholder.setAttribute("data-quicklook-owned", "blocked-image");
        placeholder.textContent = `图片已阻止：${node.getAttribute("alt") || "图片"}`;
        parent.append(placeholder);
        return;
      }
      element.setAttribute("src", url);
      element.setAttribute("decoding", "async");
      localImages += 1;
    }
    for (const child of node.childNodes) reconstruct(child, element, depth + 1);
    parent.append(element);
  }
  reconstruct(parsed.documentElement, output, 0);
  const root = output.firstElementChild;
  const defaults = inert.createElement("style");
  // Browser-paper defaults keep unthemed authored colors readable in a dark
  // host. A first anonymous layer lets all later author layers/styles override
  // these weak defaults. Author CSS may opt into dark or replace the canvas; the
  // trusted toolbar and source view continue to follow the system appearance.
  defaults.textContent = "@layer{:where(html){color-scheme:light;background:Canvas;color:CanvasText}}html{font:15px/1.6 system-ui}body{margin:20px;overflow-wrap:anywhere}img{max-width:100%;height:auto}[data-quicklook-owned]{user-select:none;font:12px system-ui}mark[data-quicklook-search]{color:inherit;background:#f0cb6390}mark[data-quicklook-search].current-match{background:#f0ab45d9;outline:1px solid #bb8028}";
  root.querySelector("head").prepend(defaults);
  return {
    html: `<!doctype html>${root.outerHTML}`,
    localImages, blockedImages,
    parserDocumentHasNoView: parsed.defaultView === null, reconstructionDocumentHasNoView: inert.defaultView === null,
  };
}
