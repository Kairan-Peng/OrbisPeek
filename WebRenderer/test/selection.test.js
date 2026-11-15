import assert from "node:assert/strict";
import test from "node:test";
import { JSDOM } from "jsdom";
import { createBodyView, isReadableText } from "../src/selection.js";
import { HTML_EXCLUDED_SELECTOR } from "../src/html.js";
import { renderDocument } from "../src/renderer.js";

const sourceText = 'const id = 9007199254740993123456789;\n\n\tconst text = "你\u200b好";\n';

function body(t, html, options = {}) {
  const dom = new JSDOM(`<style>.hidden { display: none }</style><header>toolbar</header><main tabindex="0">${html}</main><aside>notice</aside>`);
  t.after(() => dom.window.close());
  const document = dom.window.document;
  const root = document.querySelector("main");
  const view = createBodyView({ document, root, kind: "rendered", ...options });
  return { document, root, view };
}

function source(t, text = sourceText, mode = "code", language = "javascript") {
  const result = renderDocument({ text, mode, language });
  return body(t, result.html, { kind: "source", sourceText: result.copyText });
}

function select(document, start, startOffset, end = start, endOffset = startOffset) {
  const range = document.createRange();
  range.setStart(start, startOffset);
  range.setEnd(end, endOffset);
  const selection = document.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  return range;
}

function textNodes(document, root) {
  const walker = document.createTreeWalker(root, document.defaultView.NodeFilter.SHOW_TEXT);
  const result = [];
  while (walker.nextNode()) result.push(walker.currentNode);
  return result;
}

test("source selection maps partial tokens across highlighted spans", (t) => {
  const { document, root, view } = source(t);
  const nodes = textNodes(document, root.querySelector("code"));
  assert.ok(nodes.length > 2, "selection crosses real highlight spans");
  select(document, nodes[0], 2, nodes.at(-1), nodes.at(-1).length);
  assert.equal(view.selectedPlainText(), sourceText.split("\n")[0].slice(2));
});

test("source select all preserves blank lines, indentation, actual U+200B and final newline", (t) => {
  const { document, root, view } = source(t);
  view.selectAll();
  assert.equal(document.getSelection().getRangeAt(0).commonAncestorContainer, root);
  assert.equal(view.selectedPlainText(), sourceText);
  assert.equal(root.querySelectorAll("code")[1].textContent, "", "empty rows contain no fake text");
});

test("source ranges retain line breaks and whitespace-only selections", (t) => {
  const { document, root, view } = source(t);
  const rows = root.querySelectorAll(".source-line code");
  const first = textNodes(document, rows[0]).at(-1);
  const third = textNodes(document, rows[2])[0];
  select(document, first, first.length, third, 1);
  assert.equal(view.selectedPlainText(), "\n\n\t");
  select(document, third, 0, third, 1);
  assert.equal(view.selectedPlainText(), "\t");
  select(document, rows[2], rows[2].childNodes.length, rows[3], 0);
  assert.equal(view.selectedPlainText(), "\n");
});

test("JSONL source excludes error badges while preserving whitespace-only rows", (t) => {
  const text = '{"n":9007199254740993123456789}\nnot json\n  \t\n';
  const { document, root, view } = source(t, text, "jsonl", "json");
  assert.ok(root.querySelector(".line-state"));
  view.selectAll();
  assert.equal(view.selectedPlainText(), text);
  const badge = root.querySelector(".line-state").firstChild;
  select(document, badge, 0, badge, badge.length);
  assert.equal(view.selectedPlainText(), null);
  const number = root.querySelector(".line-number").firstChild;
  select(document, number, 0, number, number.length);
  assert.equal(view.selectedPlainText(), null);
});

test("source selections clamp to body and no selection never means the whole source", (t) => {
  const { document, root, view } = source(t);
  assert.equal(view.selectedPlainText(), null);
  const toolbar = document.querySelector("header").firstChild;
  select(document, toolbar, 0, toolbar, toolbar.length);
  assert.equal(view.selectedPlainText(), null);
  const notice = document.querySelector("aside").firstChild;
  select(document, toolbar, 0, notice, notice.length);
  assert.equal(view.selectedPlainText(), sourceText);
  select(document, root, 0);
  assert.equal(view.selectedPlainText(), null);
});

test("rendered selection serializes selected paragraphs and list items with readable line breaks", (t) => {
  const { document, root, view } = body(t, '<article><p>Hello <strong>world</strong></p>\n<p>Second paragraph</p>\n<ul><li>first</li>\n<li>second</li></ul></article>');
  const first = root.querySelector("strong").firstChild;
  const last = root.querySelectorAll("li")[1].firstChild;
  select(document, first, 2, last, 3);
  assert.equal(view.selectedPlainText(), "rld\nSecond paragraph\nfirst\nsec");
});

test("rendered pre keeps selected indentation, blank lines and trailing whitespace", (t) => {
  const { document, root, view } = body(t, '<article><p>before</p>\n<pre><code>  alpha\n\n\tbeta \n</code></pre>\n<p>after</p></article>');
  const code = root.querySelector("code").firstChild;
  select(document, code, 0, code, code.length);
  assert.equal(view.selectedPlainText(), "  alpha\n\n\tbeta \n");
  select(document, code, 0, code, 2);
  assert.equal(view.selectedPlainText(), "  ");
  view.selectAll();
  assert.equal(view.selectedPlainText(), "before\n  alpha\n\n\tbeta \nafter");
});

test("rendered table selection uses tabs between cells and newlines between rows", (t) => {
  const { document, root, view } = body(t, '<table><thead><tr><th>Name</th><th>Value</th></tr></thead><tbody><tr><td>alpha</td><td>123</td></tr><tr><td>beta</td><td>456</td></tr></tbody></table>');
  view.selectAll();
  assert.equal(view.selectedPlainText(), "Name\tValue\nalpha\t123\nbeta\t456");
  const cells = root.querySelectorAll("td");
  select(document, cells[0].firstChild, 2, cells[3].firstChild, 2);
  assert.equal(view.selectedPlainText(), "pha\t123\nbeta\t45");
});

test("rendered copy excludes decorations, scripts, styles, templates and CSS-hidden text", (t) => {
  const { document, root, view } = body(t, '<p>visible<span class="blocked-image">blocked image</span><span class="line-number">7</span><span class="line-state">error</span><span role="status">resource notice</span><span class="toolbar">actions</span><span hidden>hidden attribute</span><span class="hidden">hidden CSS</span><span style="visibility:hidden">invisible</span><script>secret()</script><style>.secret{}</style><template>template secret</template><span aria-hidden="true">decoration</span> text</p>');
  view.selectAll();
  assert.equal(view.selectedPlainText(), "visible text");
  const decoration = root.querySelector(".blocked-image").firstChild;
  select(document, decoration, 0, decoration, decoration.length);
  assert.equal(view.selectedPlainText(), null);
});

test("rendered selections clamp outside the body and retain real U+200B", (t) => {
  const { document, root, view } = body(t, '<p>你\u200b好<br>next</p>');
  const toolbar = document.querySelector("header").firstChild;
  const last = root.querySelector("p").lastChild;
  select(document, toolbar, 0, last, 2);
  assert.equal(view.selectedPlainText(), "你\u200b好\nne");
  document.getSelection().removeAllRanges();
  assert.equal(view.selectedPlainText(), null);
});

test("rendered table copy preserves empty cells in the selected grid", (t) => {
  const { view } = body(t, '<table><tr><td></td><td>one</td><td></td><td>two</td></tr><tr><td>three</td><td></td><td>four</td><td></td></tr></table>');
  view.selectAll();
  assert.equal(view.selectedPlainText(), "\tone\t\ttwo\nthree\t\tfour\t");
});


test("a rendered Markdown table containing only blocked remote images has no readable selection", (t) => {
  const markdown = "| ![a](https://example.invalid/a.png) | ![b](https://example.invalid/b.png) |\n| --- | --- |\n| ![c](https://example.invalid/c.png) | ![d](https://example.invalid/d.png) |";
  const result = renderDocument({ text: markdown, mode: "markdown" });
  const { root, view } = body(t, result.html);
  assert.equal(root.querySelectorAll("table .blocked-image").length, 4);
  view.selectAll();
  assert.equal(view.selectedPlainText(), null);
});

test("rendered structural separators alone are not readable text, while pre whitespace is retained", (t) => {
  const { root, view } = body(t, '<p><br></p><table><tr><td></td><td></td></tr></table>');
  view.selectAll();
  assert.equal(view.selectedPlainText(), null);
  root.innerHTML = '<pre><code>  \t\n </code></pre>';
  view.selectAll();
  assert.equal(view.selectedPlainText(), "  \t\n ");
});

test("rendered copy allows a visible child to restore visibility inside a hidden container", (t) => {
  const { document, root, view } = body(t, '<div style="visibility:hidden">hidden before<span>inherited hidden</span><span style="visibility:visible">visible child</span>hidden after</div>');
  const visible = root.querySelector('[style="visibility:visible"]');
  assert.equal(document.defaultView.getComputedStyle(visible).visibility, "visible");
  assert.equal(document.defaultView.getComputedStyle(root.querySelector("div > span")).visibility, "hidden");
  view.selectAll();
  assert.equal(view.selectedPlainText(), "visible child");
});

test("rendered Markdown hard breaks do not copy a formatting newline as a line-start space", (t) => {
  const result = renderDocument({ text: "one  \ntwo", mode: "markdown" });
  const { root, view } = body(t, result.html);
  assert.equal(root.querySelector("p").innerHTML, "one<br>\ntwo");
  view.selectAll();
  assert.equal(view.selectedPlainText(), "one\ntwo");
});

test("rendered partial whitespace selections after a hard break remain selected whitespace", (t) => {
  const result = renderDocument({ text: "one  \ntwo three", mode: "markdown" });
  const { document, root, view } = body(t, result.html);
  const afterBreak = root.querySelector("br").nextSibling;
  select(document, afterBreak, 4, afterBreak, 5);
  assert.equal(view.selectedPlainText(), " ");
  select(document, afterBreak, 0, afterBreak, 1);
  assert.equal(view.selectedPlainText(), " ", "a partial whitespace range does not include the structural break");
});

test('closed details copy and search visibility keep only the first direct summary', (t) => {
  const { document, root, view } = body(t, '<details><summary><strong>Visible summary</strong></summary>direct hidden text<summary>Hidden second summary</summary><p>Hidden needle</p></details><p>After details</p>');
  const details = root.querySelector('details');
  view.selectAll();
  assert.equal(view.selectedPlainText(), 'Visible summary\nAfter details');
  assert.equal(isReadableText(details.querySelector('strong').firstChild, root), true);
  assert.equal(isReadableText(details.querySelector('p').firstChild, root), false);
  assert.equal(isReadableText(details.querySelectorAll('summary')[1].firstChild, root), false);
  assert.equal(isReadableText(details.childNodes[1], root), false);
  details.open = true;
  view.selectAll();
  assert.match(view.selectedPlainText(), /Hidden needle/);
  assert.match(view.selectedPlainText(), /Hidden second summary/);
  assert.equal(isReadableText(details.querySelector('p').firstChild, root), true);
});

for (const [attribute, value] of [['hidden', ''], ['style', 'display:none'], ['style', 'opacity:0'], ['style', 'content-visibility:hidden'], ['aria-hidden', 'true']]) {
  test(`HTML root ancestor ${attribute}=${value} excludes body copy and search visibility`, (t) => {
    const dom = new JSDOM('<!doctype html><html><head></head><body><p>hidden needle</p></body></html>');
    t.after(() => dom.window.close());
    const document = dom.window.document;
    document.documentElement.setAttribute(attribute, value);
    const root = document.body;
    const view = createBodyView({ document, root, kind: 'html', excludedSelector: HTML_EXCLUDED_SELECTOR });
    view.selectAll();
    assert.equal(view.selectedPlainText(), null);
    assert.equal(isReadableText(root.querySelector('p').firstChild, root, HTML_EXCLUDED_SELECTOR), false);
  });
}

test('root visibility hidden still permits explicitly visible authored children and classes', (t) => {
  const dom = new JSDOM('<!doctype html><html class="toolbar" style="visibility:hidden"><body><p>hidden ancestor text</p><p class="blocked-image" style="visibility:visible">visible child</p></body></html>');
  t.after(() => dom.window.close());
  const document = dom.window.document, root = document.body;
  const view = createBodyView({ document, root, kind: 'html', excludedSelector: HTML_EXCLUDED_SELECTOR });
  view.selectAll();
  assert.equal(view.selectedPlainText(), 'visible child');
  assert.equal(isReadableText(root.querySelectorAll('p')[0].firstChild, root, HTML_EXCLUDED_SELECTOR), false);
  assert.equal(isReadableText(root.querySelectorAll('p')[1].firstChild, root, HTML_EXCLUDED_SELECTOR), true);
});

test('HTML pre-line collapses horizontal whitespace while retaining selected line breaks', (t) => {
  const { document, root, view } = body(t, '<p style="white-space:pre-line">alpha \t beta \n \t gamma   delta</p>', { kind: 'html' });
  const text = root.querySelector('p').firstChild;
  view.selectAll();
  assert.equal(view.selectedPlainText(), 'alpha beta\ngamma delta');
  select(document, text, 2, text, text.length - 2);
  assert.equal(view.selectedPlainText(), 'pha beta\ngamma del');
  const newline = text.data.indexOf('\n');
  select(document, text, newline, text, newline + 1);
  assert.equal(view.selectedPlainText(), '\n');
});

for (const whiteSpace of ['normal', 'nowrap']) {
  test(`HTML ${whiteSpace} descendant overrides inherited pre whitespace for selected copy`, (t) => {
    const { document, root, view } = body(t, `<pre><span style="white-space:${whiteSpace}"><em>alpha\nbeta \t gamma</em></span></pre>`, { kind: 'html' });
    const text = root.querySelector('em').firstChild;
    view.selectAll();
    assert.equal(view.selectedPlainText(), 'alpha beta gamma');
    select(document, text, 2, text, text.length - 2);
    assert.equal(view.selectedPlainText(), 'pha beta gam');
  });
}

for (const whiteSpace of ['pre-wrap', 'break-spaces']) {
  test(`HTML inherited ${whiteSpace} retains selected spacing when computed inheritance is omitted`, (t) => {
    const { document, root, view } = body(t, `<p style="white-space:${whiteSpace}"><span>  alpha\n\tbeta </span></p>`, { kind: 'html' });
    const text = root.querySelector('span').firstChild;
    view.selectAll();
    assert.equal(view.selectedPlainText(), '  alpha\n\tbeta ');
    select(document, text, 0, text, 2);
    assert.equal(view.selectedPlainText(), '  ');
  });
}

for (const [name, markup] of [
  ['newline before inline child', '<p style="white-space:pre-line">AA \n<span> CC</span></p>'],
  ['newline after inline child', '<p style="white-space:pre-line"><span>AA </span>\n CC</p>'],
]) {
  test(`pre-line ${name} trims collapsed line edges across selected text nodes`, (t) => {
    const { document, root, view } = body(t, markup, { kind: 'html' });
    const nodes = textNodes(document, root.querySelector('p'));
    select(document, nodes[0], 0, nodes[1], nodes[1].length);
    assert.equal(view.selectedPlainText(), 'AA\nCC');
    select(document, nodes[0], 1, nodes[1], nodes[1].length - 1);
    assert.equal(view.selectedPlainText(), 'A\nC');
    const trailing = nodes[1].data.includes('\n') ? nodes[1].data.indexOf('\n') + 1 : 0;
    select(document, nodes[1], trailing, nodes[1], nodes[1].length);
    assert.equal(view.selectedPlainText(), ' CC', 'an unselected preceding newline cannot trim the range');
    const beforeNewline = nodes[0].data.includes('\n') ? nodes[0].data.indexOf('\n') : nodes[0].length;
    select(document, nodes[0], 0, nodes[0], beforeNewline);
    assert.equal(view.selectedPlainText(), 'AA ', 'an unselected following newline cannot trim the range');
  });
}

test('pre-line boundary normalization retains preserved spaces and explicit BR boundaries', (t) => {
  const cases = [
    ['<p style="white-space:pre-line">AA\n<span style="white-space:pre"> CC</span></p>', 'AA\n CC'],
    ['<p style="white-space:pre-line"><span style="white-space:pre">AA </span>\nCC</p>', 'AA \nCC'],
    ['<p style="white-space:pre-line"><span style="white-space:pre">AA  </span><span> </span>\nCC</p>', 'AA  \nCC'],
    ['<p style="white-space:pre-line"><span>AA </span><br><span> CC</span></p>', 'AA \n CC'],
    ['<pre>AA \n<span> CC</span></pre>', 'AA \n CC'],
    ['<p>AA <span> CC</span></p>', 'AA CC'],
    ['<p style="white-space:pre-line">AA\n<span> </span><span> CC</span></p>', 'AA\nCC'],
    ['<p style="white-space:pre-line">AA\n<span style="white-space:normal"> CC</span></p>', 'AA\nCC'],
    ['<p style="white-space:pre-line"><span style="white-space:normal">AA </span>\nCC</p>', 'AA\nCC'],
    ['<p style="white-space:pre-line">AA\n</p><p style="white-space:pre-line"> CC</p>', 'AA\n CC'],
    ['<table style="white-space:pre-line"><tr><td>AA\n</td><td> CC</td></tr></table>', 'AA\n\t CC'],
  ];
  for (const [markup, expected] of cases) {
    const { view } = body(t, markup, { kind: 'html' });
    view.selectAll();
    assert.equal(view.selectedPlainText(), expected);
  }
});
