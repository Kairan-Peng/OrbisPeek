const EXCLUDED = "script, style, template, input, textarea, select, button, [hidden], [aria-hidden='true'], [role='status'], .line-number, .line-state, .blocked-image, .resource-notice, .notices, .toolbar";
const BLOCK_TAGS = new Set(["ADDRESS", "ARTICLE", "ASIDE", "BLOCKQUOTE", "DIV", "DL", "DT", "DD", "FIGCAPTION", "FIGURE", "FOOTER", "H1", "H2", "H3", "H4", "H5", "H6", "HEADER", "HR", "LI", "MAIN", "NAV", "OL", "P", "PRE", "SECTION", "UL"]);
const STRUCTURAL_WHITESPACE = new Set(["ARTICLE", "MAIN", "BODY", "OL", "UL", "TABLE", "THEAD", "TBODY", "TFOOT", "TR"]);

// Keep the original DOM nodes: cloned fragments lose ancestor visibility and
// selections can start outside the readable body (for example in the toolbar).
function clampedRange(range, root) {
  const contents = root.ownerDocument.createRange();
  contents.selectNodeContents(root);
  const start = contents.comparePoint(range.startContainer, range.startOffset);
  const end = contents.comparePoint(range.endContainer, range.endOffset);
  if (start === 1 || end === -1) return null;
  const result = range.cloneRange();
  if (start === -1) result.setStart(contents.startContainer, contents.startOffset);
  if (end === 1) result.setEnd(contents.endContainer, contents.endOffset);
  return result.collapsed ? null : result;
}

function sourceSelection(range, root, sourceText) {
  const lines = sourceText.split("\n");
  let start = 0;
  const rows = [...root.querySelectorAll(".source-line")].map((line, index) => {
    const code = line.querySelector("code");
    const row = { line, code, start, length: lines[index]?.length ?? 0 };
    start += row.length + 1;
    return row;
  });

  const rowByLine = new Map(rows.map((row) => [row.line, row]));
  function codeRange(row) {
    const result = root.ownerDocument.createRange();
    result.selectNodeContents(row.code);
    return result;
  }

  function offset(node, position) {
    const element = node.nodeType === 1 ? node : node.parentElement;
    const containingRow = rowByLine.get(element?.closest(".source-line"));
    if (containingRow?.code) {
      const range = codeRange(containingRow);
      const relation = range.comparePoint(node, position);
      if (relation === -1) return containingRow.start;
      if (relation === 1) return containingRow.start + containingRow.length;
      range.setEnd(node, position);
      return containingRow.start + Math.min(containingRow.length, range.toString().length);
    }
    // Element boundaries between rows map to the following line's start.
    // Binary search avoids a DOM Range walk through every preceding row.
    let low = 0;
    let high = rows.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (codeRange(rows[middle]).comparePoint(node, position) === 1) low = middle + 1;
      else high = middle;
    }
    return rows[low]?.start ?? sourceText.length;
  }

  const from = offset(range.startContainer, range.startOffset);
  const to = offset(range.endContainer, range.endOffset);
  return to > from ? sourceText.slice(from, to) : null;
}

// Closed details expose only their first direct summary. Computed display and
// visibility alone do not reveal this native rendering rule (including WebKit).
function isClosedDetailsContent(node) {
  for (let ancestor = node.parentElement; ancestor; ancestor = ancestor.parentElement) {
    if (ancestor.tagName !== "DETAILS" || ancestor.hasAttribute("open")) continue;
    const summary = [...ancestor.children].find((child) => child.tagName === "SUMMARY");
    if (!summary?.contains(node)) return true;
  }
  return false;
}

function readableStyle(element, excludedSelector) {
  if (element.matches(excludedSelector)) return null;
  const style = element.ownerDocument.defaultView.getComputedStyle(element);
  return style.display === "none" || style.contentVisibility === "hidden" || style.opacity === "0" ? null : style;
}

function effectiveWhiteSpace(value, inherited) {
  // Browsers return the inherited computed value. jsdom can omit it on inline
  // descendants, so inherit only when that computed value is actually absent.
  if (!value || value === "inherit" || value === "unset") return inherited;
  return value === "initial" ? "normal" : value;
}

function renderedSelection(range, root, excludedSelector) {
  const document = root.ownerDocument;
  // Range clamping limits what can be copied, but ancestors outside that range
  // can still hide the entire body (notably authored html root attributes).
  let inheritedWhiteSpace;
  for (let ancestor = root.parentElement; ancestor; ancestor = ancestor.parentElement) {
    const style = readableStyle(ancestor, excludedSelector);
    if (!style) return null;
    if (inheritedWhiteSpace === undefined && style.whiteSpace && !["inherit", "unset"].includes(style.whiteSpace)) {
      inheritedWhiteSpace = effectiveWhiteSpace(style.whiteSpace, "normal");
    }
  }
  const tokens = [];
  let hasReadableText = false;

  function isBlock(element) {
    return element && (BLOCK_TAGS.has(element.tagName)
      || ["block", "list-item", "flex", "grid"].includes(document.defaultView.getComputedStyle(element).display));
  }

  function visit(node, context) {
    if (isClosedDetailsContent(node)) return;
    if (node.nodeType === 3) {
      if (!context.visible) return;
      const selected = clampedRange(range, node);
      if (!selected) return;
      const from = selected.startContainer === node ? selected.startOffset : 0;
      const to = selected.endContainer === node ? selected.endOffset : node.length;
      let text = node.data.slice(from, to);
      if (!context.preserve) {
        const preserveLines = context.whiteSpace === "pre-line";
        if (!preserveLines && node.previousSibling?.nodeName === "BR" && range.intersectsNode(node.previousSibling)) {
          text = text.replace(/^[\t\f ]*[\r\n][\t\n\r\f ]*/, "");
        }
        if (!preserveLines && /^[\t\n\r\f ]*$/.test(text) && (STRUCTURAL_WHITESPACE.has(node.parentElement.tagName)
          || isBlock(node.previousElementSibling) || isBlock(node.nextElementSibling))) return;
        text = preserveLines
          ? text.replace(/\r\n?/g, "\n").replace(/[\t\f ]+/g, " ").replace(/ *\n */g, "\n")
          : text.replace(/[\t\n\r\f ]+/g, " ");
      }
      if (text) {
        hasReadableText = true;
        tokens.push({ ...context, text });
      }
      return;
    }
    if (node.nodeType !== 1 || !range.intersectsNode(node)) return;
    const style = readableStyle(node, excludedSelector);
    if (!style) return;
    const whiteSpace = effectiveWhiteSpace(style.whiteSpace, context.whiteSpace);
    const next = {
      block: isBlock(node) ? node : context.block,
      cell: node.matches("td, th") ? node : context.cell,
      row: node.tagName === "TR" ? node : context.row,
      visible: style.visibility !== "hidden" && style.visibility !== "collapse",
      whiteSpace,
      preserve: /^(pre|pre-wrap|break-spaces)$/.test(whiteSpace),
    };
    if (node.tagName === "BR") {
      if (next.visible) tokens.push({ ...next, text: "\n", hardBreak: true });
    }
    else {
      const before = tokens.length;
      for (const child of node.childNodes) visit(child, next);
      if (next.visible && next.cell === node && tokens.length === before) tokens.push({ ...next, text: "" });
    }
  }

  visit(root, { block: root, cell: null, row: null, visible: true, whiteSpace: inheritedWhiteSpace || "normal", preserve: false });
  if (!hasReadableText) return null;
  let text = "";
  let previous;
  for (const token of tokens) {
    let separator = "";
    if (previous) {
      if (previous.row && token.row && previous.row !== token.row) separator = "\n";
      else if (previous.cell && token.cell && previous.cell !== token.cell && previous.row === token.row) separator = "\t";
      else if (previous.block !== token.block) separator = "\n";
      if (separator === "\n" && (text.endsWith("\n") || token.text.startsWith("\n"))) separator = "";
      const sameInlineRun = previous.block === token.block && previous.cell === token.cell && previous.row === token.row;
      if (sameInlineRun && !previous.hardBreak && !token.hardBreak) {
        // pre-line collapses line-edge spaces across inline DOM boundaries too.
        // Remove only the adjacent collapsed space, never a preserved-space run
        // or whitespace outside the selected tokens. BR remains its own barrier.
        if (previous.whiteSpace === "pre-line" && text.endsWith("\n") && !token.preserve && token.text.startsWith(" ")) {
          token.text = token.text.slice(1);
          if (!token.text) continue;
        }
        if (token.whiteSpace === "pre-line" && token.text.startsWith("\n") && !previous.preserve && text.endsWith(" ")) {
          text = text.slice(0, -1);
        }
      }
      if (!separator && !previous.preserve && !token.preserve && text.endsWith(" ") && token.text.startsWith(" ")) token.text = token.text.slice(1);
    }
    text += separator + token.text;
    previous = token;
  }
  return text || null;
}

export function isReadableText(node, root, excludedSelector = EXCLUDED) {
  if (!root.contains(node) || isClosedDetailsContent(node)) return false;
  let visible = true;
  for (let element = node.parentElement; element; element = element.parentElement) {
    const style = readableStyle(element, excludedSelector);
    if (!style) return false;
    // visibility is inherited and a descendant may explicitly restore it.
    if (element === node.parentElement) visible = style.visibility !== "hidden" && style.visibility !== "collapse";
  }
  return visible;
}

export function createBodyView({ root, document = root.ownerDocument, kind, sourceText = "", excludedSelector = EXCLUDED }) {
  return {
    document, root, kind, sourceText, excludedSelector,
    focus() { root.focus({ preventScroll: true }); },
    selectAll() {
      const range = document.createRange();
      range.selectNodeContents(root);
      const selection = document.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    },
    selectedPlainText() {
      const selection = document.getSelection();
      if (!selection?.rangeCount || selection.isCollapsed) return null;
      const range = clampedRange(selection.getRangeAt(0), root);
      if (!range) return null;
      return kind === "source" ? sourceSelection(range, root, sourceText) : renderedSelection(range, root, excludedSelector);
    },
  };
}
