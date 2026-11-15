import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { sanitizeHTML } from '../src/html.js';
const token = 'D74B9B4A-7C26-4A98-8A67-30E256E963DE';
function clean(t, source) {
  const shell = new JSDOM('<main>trusted shell</main>');
  t.after(() => shell.window.close());
  const result = sanitizeHTML(source, shell.window.document, token);
  const final = new JSDOM(result.html);
  t.after(() => final.window.close());
  return { ...result, document: final.window.document, shell: shell.window.document };
}
function canvasDefaults(document) {
  const layer = document.head.querySelector('style').sheet.cssRules[0];
  assert.equal(layer.cssText.slice(0, layer.cssText.indexOf('{')).trim(), '@layer', 'canvas fallback is in an initial anonymous layer');
  assert.equal(layer.cssRules.length, 1);
  return layer.cssRules[0];
}
function assertStatic(document) {
  for (const element of document.querySelectorAll('*')) {
    assert.equal(element.namespaceURI, 'http://www.w3.org/1999/xhtml');
    assert.ok(!/^(script|iframe|frame|object|embed|form|input|button|textarea|select|video|audio|source|picture|base|meta|link|noscript|xmp)$/i.test(element.localName), element.outerHTML);
    for (const attr of element.attributes) assert.ok(!/^on|^(srcset|contenteditable|background|lowsrc|ping|is)$/i.test(attr.name), attr.name);
  }
}
test('static HTML keeps readable structure, author classes and inline CSS outside the shell', (t) => {
  const { document, shell } = clean(t, '<style>p{color:red}</style><h1>Title</h1><p class="toolbar search-match" style="font-weight:bold">Alpha <em>beta</em></p><ul><li>one</li></ul><table><tr><td>cell</td></tr></table><pre> a\n b</pre>');
  assert.equal(document.querySelector('h1').textContent, 'Title');
  assert.equal(document.querySelector('p').className, 'toolbar search-match');
  assert.equal(document.querySelector('p').getAttribute('style'), 'font-weight:bold');
  assert.equal([...document.querySelectorAll('style')].at(-1).textContent, 'p{color:red}');
  assert.equal(document.querySelector('td').textContent, 'cell');
  assert.equal(shell.querySelector('style'), null);
  assertStatic(document);
});
test('scripts, policy loaders, controls and automatic resources are removed with readable siblings retained', (t) => {
  const { document } = clean(t, '<base href="https://bad/"><meta http-equiv="refresh" content="0"><link rel="stylesheet" href="remote"><ScRiPt type="module">bad()</sCrIpT><script type="importmap">{}</script><script type="speculationrules">{}</script><iframe>frame</iframe><object>object</object><form><input><p>form</p></form><video poster="remote"><source src="remote"></video><p ONCLICK="bad()" contenteditable="true" background="x">readable</p>');
  assert.equal(document.body.textContent, 'readable');
  assertStatic(document);
});
test('links retain fragments and explicit web/mail destinations only', (t) => {
  const values = ['#part', 'https://example.invalid/a', 'HTTP://example.invalid/', 'mailto:a@example.invalid', 'jav&#97;script:bad()', 'java&#9;script:bad()', 'data:text/html,bad', 'file:///tmp/x', 'relative.html', '//example.invalid/x', 'https&#10;://bad/'];
  const { document } = clean(t, values.map((v) => `<a href="${v}" ping="https://bad" target="_blank">link</a>`).join(''));
  assert.deepEqual([...document.querySelectorAll('a')].map(a => a.getAttribute('href')), [...values.slice(0, 4), ...values.slice(4).map(() => null)]);
  assertStatic(document);
});
test('HTML images use the current native capability and reject URL/path bypasses before serialization', (t) => {
  const bad = ['https://bad/x.png', ' https://bad/x.png', '%20/tmp/x.png', '/tmp/x.png', '../x.png', '%2e%2e/x.png', '%2Ftmp/x.png', 'http%3Ax.png', 'x%00.png', 'x%7f.png', 'x\\y.png', 'bad%zz.png', `quicklook-resource://local/${token}/x.png`, 'x.svg'];
  const { document, localImages, blockedImages } = clean(t, ['images/a%3Fb%23c.png?raw=1', '%252e%252e/x.png', ...bad].map(src => `<img src="${src}" srcset="https://bad/2.png 2x" lowsrc="bad" onerror="bad()">`).join(''));
  assert.equal(localImages, 2);
  assert.equal(blockedImages, bad.length);
  assert.deepEqual([...document.images].map(img => img.getAttribute('src')), [`quicklook-resource://local/${token}/images/a%3Fb%23c.png`, `quicklook-resource://local/${token}/%252e%252e/x.png`]);
  assertStatic(document);
});
test('picture, foreign namespaces, rawtext and scripting-mode mutation payloads stay absent after reparse', (t) => {
  const corpus = ['<picture><source srcset="https://bad"><img src="x.png"></picture><p>after</p>', '<svg><foreignObject><p onload="bad()">bad</p></foreignObject><image href="bad"/></svg><math><mtext><img src="bad"></mtext></math><p>after</p>', '<noscript><p title="</noscript><img src=x onerror=bad()>">bad</p></noscript><xmp><img src=x onerror=bad()></xmp><p>after</p>', '<table><b><tr><td><img src="bad.svg" onerror="bad()">cell</td></tr></b></table><p>after</p>'];
  for (const source of corpus) { const result = clean(t, source); assertStatic(result.document); assert.match(result.document.body.textContent, /after/); }
});
test('reserved internal attributes cannot be supplied by a document', (t) => {
  const { document } = clean(t, '<p data-quicklook-owned="notice" data-quicklook-search="true" class="blocked-image">author text</p>');
  const paragraph = document.querySelector('p');
  assert.equal(paragraph.className, 'blocked-image');
  assert.equal(paragraph.hasAttribute('data-quicklook-owned'), false);
  assert.equal(paragraph.hasAttribute('data-quicklook-search'), false);
});


test('full-document body styles and classes survive inert parsing', (t) => {
  const { document } = clean(t, '<!doctype html><html><head><style>h1{color:red}</style></head><body style="padding-left:13px" class="author"><h1>body style</h1></body></html>');
  assert.equal(document.body.getAttribute('style'), 'padding-left:13px');
  assert.equal(document.body.className, 'author');
  assertStatic(document);
});

test('authored root attributes survive full-document parsing and final reparse', (t) => {
  const { document } = clean(t, '<!doctype html><!-- <html class="wrong"> --><html class="dark" id="root" lang="zh" dir="rtl" title="a > b" style="color:rgb(71,82,93);font-size:19px" onload="bad()" data-quicklook-owned="forged"><head><style>.dark p{font-style:italic}</style></head><body><p>root styles</p></body></html>');
  const root = document.documentElement;
  assert.equal(root.className, 'dark');
  assert.equal(root.id, 'root');
  assert.equal(root.lang, 'zh');
  assert.equal(root.dir, 'rtl');
  assert.equal(root.title, 'a > b');
  assert.equal(root.style.color, 'rgb(71, 82, 93)');
  assert.equal(root.style.fontSize, '19px');
  assert.equal(root.hasAttribute('onload'), false);
  assert.equal(root.hasAttribute('data-quicklook-owned'), false);
  assertStatic(document);
});

test('reconstruction budget rejects partial output instead of silently dropping allowed content', (t) => {
  const dom = new JSDOM('');t.after(() => dom.window.close());
  const source = '<b>a</b>'.repeat(16_000) + '<p>tail survives in source</p>';
  assert.ok(source.length < 524_288);
  assert.throws(() => sanitizeHTML(source, dom.window.document, token), /reconstruction budget/);
});

test('static HTML starts on an opaque light browser canvas without changing author styles', (t) => {
  const { document } = clean(t, '<html style="color:rgb(18,52,86)"><head><style>p{font-style:italic}</style></head><body style="color:rgb(71,82,93)"><p>Paper canvas</p></body></html>');
  const defaults = canvasDefaults(document);
  assert.equal(defaults.selectorText, ':where(html)');
  assert.equal(defaults.style.getPropertyValue('color-scheme'), 'light');
  assert.equal(defaults.style.getPropertyValue('background').toLowerCase(), 'canvas');
  assert.equal(defaults.style.getPropertyValue('color').toLowerCase(), 'canvastext');
  assert.equal(document.documentElement.getAttribute('style'), 'color:rgb(18,52,86)');
  assert.equal(document.body.getAttribute('style'), 'color:rgb(71,82,93)');
  assert.equal([...document.head.querySelectorAll('style')].at(-1).textContent, 'p{font-style:italic}');
});

test('authored later CSS and inline root policy can override the default HTML canvas', (t) => {
  const { document } = clean(t, '<html style="color-scheme:dark;background:rgb(9,10,11);color:rgb(240,241,242)"><head><style>html{color-scheme:dark;background:rgb(1,2,3)}body{color:rgb(210,211,212)}</style></head><body><p>Author dark canvas</p></body></html>');
  const root = document.documentElement;
  assert.match(root.getAttribute('style'), /color-scheme:dark/);
  assert.equal(root.getAttribute('style'), 'color-scheme:dark;background:rgb(9,10,11);color:rgb(240,241,242)');
  assert.match([...document.head.querySelectorAll('style')].at(-1).textContent, /html\{color-scheme:dark/);
});


test('canvas defaults have zero specificity so later universal author policy can win', (t) => {
  const { document } = clean(t, '<style>*{color-scheme:dark;background:Canvas;color:CanvasText}</style><p>Universal authored theme</p>');
  const sheets = [...document.head.querySelectorAll('style')];
  assert.equal(canvasDefaults(document).selectorText, ':where(html)');
  const author = sheets.at(-1).sheet.cssRules[0];
  assert.equal(author.selectorText, '*');
  assert.equal(author.style.getPropertyValue('color-scheme'), 'dark');
  assert.equal(author.style.getPropertyValue('background').toLowerCase(), 'canvas');
});


test('initial anonymous canvas layer stays below authored named theme layers', (t) => {
  const { document } = clean(t, '<style>@layer theme{html{color-scheme:dark;background:rgb(8,9,10);color:rgb(230,231,232)}}</style><p>Layered authored theme</p>');
  assert.equal(canvasDefaults(document).selectorText, ':where(html)');
  const authorLayer = [...document.head.querySelectorAll('style')].at(-1).sheet.cssRules[0];
  assert.match(authorLayer.cssText, /^@layer theme/);
  assert.equal(authorLayer.cssRules[0].style.getPropertyValue('color-scheme'), 'dark');
});
