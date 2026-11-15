const SPACE = /[\t\n\f\r ]/;
const NAME_START = /[A-Za-z_:]/;
const NAME = /[A-Za-z0-9_.:-]/;
const RAW_TEXT = new Set(["script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes", "plaintext"]);
const ATTRIBUTES = new Set(["src", "alt", "width", "height"]);

export function imageDimension(value) {
  return /^[1-9][0-9]{0,3}$/.test(value ?? "") && Number(value) <= 1600 ? value : null;
}

function decodeEntities(value, markdownIt) {
  // Decode HTML entities without applying Markdown backslash escapes to paths.
  return value.replace(/&(?:#x[0-9a-f]{1,6}|#[0-9]{1,7}|[a-z][a-z0-9]{1,31});/gi,
    (entity) => markdownIt.utils.unescapeAll(entity));
}

function tagEnd(source, start, maximum) {
  let quote = null;
  for (let index = start; index < maximum; index += 1) {
    const character = source[index];
    if (quote) { if (character === quote) quote = null; }
    else if (character === '"' || character === "'") quote = character;
    else if (character === ">") return index + 1;
  }
  return maximum;
}

function imageAttributes(tag, markdownIt) {
  if (tag.length > 8192 || !/^<img(?=[\t\n\f\r />])/i.test(tag)) return null;
  const attributes = new Map();
  let position = 4;
  let count = 0;
  while (position < tag.length) {
    const previous = position;
    while (SPACE.test(tag[position] ?? "")) position += 1;
    if (tag.slice(position) === ">" || tag.slice(position) === "/>") return attributes;
    if (position === previous || !NAME_START.test(tag[position] ?? "") || ++count > 64) return null;
    const start = position++;
    while (NAME.test(tag[position] ?? "")) position += 1;
    const name = tag.slice(start, position).toLowerCase();
    const nameEnd = position;
    while (SPACE.test(tag[position] ?? "")) position += 1;
    let value = "";
    if (tag[position] === "=") {
      position += 1;
      while (SPACE.test(tag[position] ?? "")) position += 1;
      const quote = tag[position];
      if (quote === '"' || quote === "'") {
        const end = tag.indexOf(quote, position + 1);
        if (end < 0) return null;
        value = tag.slice(position + 1, end);
        position = end + 1;
      } else {
        const start = position;
        while (position < tag.length && !SPACE.test(tag[position]) && tag[position] !== ">") {
          if (/["'=<>`]/.test(tag[position])) return null;
          position += 1;
        }
        if (position === start) return null;
        value = tag.slice(start, position);
      }
    } else position = nameEnd;
    if (ATTRIBUTES.has(name) && !attributes.has(name)) attributes.set(name, decodeEntities(value, markdownIt));
  }
  return null;
}

function terminatorEnd(source, start, terminator) {
  if (typeof terminator === "string") {
    const position = source.indexOf(terminator, start);
    return position < 0 ? -1 : position + terminator.length;
  }
  const match = source.slice(start).match(new RegExp(`</${terminator.tag}[\\t\\n\\f\\r ]*>`, "i"));
  return match ? start + match.index + match[0].length : -1;
}

function literal(state, silent, start, end, continuation) {
  if (!silent) {
    state.push("text", "", 0).content = state.src.slice(start, end);
    state.env.markdownLiteral = continuation;
  }
  state.pos = end;
  return true;
}

/** Keep HTML disabled. Only a parsed img tag becomes a standard image token;
 * all other tags and literal regions remain text, including across paragraphs. */
export function markdownImagePlugin(markdownIt) {
  // A closing > on its own line otherwise starts a Markdown blockquote before
  // inline parsing gets a chance to see the complete multiline image tag.
  markdownIt.block.ruler.before("blockquote", "quicklook-image-block", (state, startLine, endLine, silent) => {
    if (state.sCount[startLine] - state.blkIndent >= 4) return false;
    let source = state.src.slice(state.bMarks[startLine] + state.tShift[startLine], state.eMarks[startLine]);
    if (!/^<img(?=[\t\f\r />]|$)/i.test(source) || source.includes(">")) return false;
    for (let line = startLine + 1; line < endLine && source.length <= 8192; line += 1) {
      source += `\n${state.src.slice(state.bMarks[line] + state.tShift[line], state.eMarks[line])}`;
      const end = tagEnd(source, 4, source.length);
      if (!imageAttributes(source.slice(0, end), markdownIt) || source.slice(end).trim()) continue;
      if (silent) return true;
      state.push("paragraph_open", "p", 1).map = [startLine, line + 1];
      const token = state.push("inline", "", 0);
      token.content = source.slice(0, end);
      token.map = [startLine, line + 1];
      token.children = [];
      state.push("paragraph_close", "p", -1);
      state.line = line + 1;
      return true;
    }
    return false;
  });
  markdownIt.inline.ruler.before("text", "quicklook-html-continuation", (state, silent) => {
    const continuation = state.env.markdownLiteral;
    if (!continuation) return false;
    const end = terminatorEnd(state.src, state.pos, continuation);
    return literal(state, silent, state.pos, end < 0 ? state.posMax : end, end < 0 ? continuation : null);
  });
  markdownIt.inline.ruler.before("html_inline", "quicklook-html-image", (state, silent) => {
    const start = state.pos;
    if (state.src[start] !== "<") return false;
    const source = state.src.slice(start, state.posMax);
    const special = source.startsWith("<!--") ? ["-->", 4]
      : source.startsWith("<![CDATA[") ? ["]]>", 9]
      : source.startsWith("<?") ? ["?>", 2] : null;
    if (special) {
      const end = terminatorEnd(state.src, start + special[1], special[0]);
      return literal(state, silent, start, end < 0 ? state.posMax : end, end < 0 ? special[0] : null);
    }
    const name = source.match(/^<\/?([A-Za-z][A-Za-z0-9:-]*)(?=[\t\n\f\r />])/);
    if (!name) return false;
    const end = tagEnd(state.src, start + name[0].length, state.posMax);
    const tag = state.src.slice(start, end);
    const tagName = name[1].toLowerCase();
    if (!source.startsWith("</") && RAW_TEXT.has(tagName)) {
      const continuation = { tag: tagName };
      const close = terminatorEnd(state.src, end, continuation);
      return literal(state, silent, start, close < 0 ? state.posMax : close, close < 0 ? continuation : null);
    }
    const attributes = imageAttributes(tag, markdownIt);
    if (!attributes) return literal(state, silent, start, end, null);
    if (!silent) {
      const token = state.push("image", "img", 0);
      token.attrs = [["src", attributes.get("src") || ""]];
      token.content = attributes.get("alt") || "";
      token.children = [];
      for (const name of ["width", "height"]) {
        const value = imageDimension(attributes.get(name));
        if (value) token.attrSet(name, value);
      }
    }
    state.pos = end;
    return true;
  });
}
