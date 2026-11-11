import { applyEdits, createScanner, format, printParseErrorCode, SyntaxKind, visit } from "jsonc-parser";

export const MAX_JSON_DEPTH = 128;
const MAX_FORMATTED_LENGTH = 1_048_576;

export function validateJSON(text) {
  const scanner = createScanner(text, true);
  let depth = 0;
  for (let token = scanner.scan(); token !== SyntaxKind.EOF; token = scanner.scan()) {
    if (token === SyntaxKind.OpenBraceToken || token === SyntaxKind.OpenBracketToken) {
      depth += 1;
      if (depth > MAX_JSON_DEPTH) return { valid: false, error: `嵌套超过 ${MAX_JSON_DEPTH} 层`, offset: scanner.getTokenOffset() };
    } else if (token === SyntaxKind.CloseBraceToken || token === SyntaxKind.CloseBracketToken) depth -= 1;
  }
  let firstError;
  visit(text, {
    onError(error, offset) {
      firstError ??= { valid: false, error: printParseErrorCode(error), offset };
    },
  }, { allowTrailingComma: false, disallowComments: true, allowEmptyContent: false });
  return firstError ?? { valid: true };
}

export function formatJSON(text) {
  const validation = validateJSON(text);
  if (!validation.valid) return { ...validation, text };
  const edits = format(text, undefined, { insertSpaces: true, tabSize: 2, eol: "\n" });
  const outputLength = edits.reduce((length, edit) => length + edit.content.length - edit.length, text.length);
  if (outputLength > MAX_FORMATTED_LENGTH) {
    return { valid: true, text, notice: "格式化后的内容过长，显示原文。" };
  }
  return { valid: true, text: applyEdits(text, edits) };
}
