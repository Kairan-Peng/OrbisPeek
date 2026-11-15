export function createPreviewCommands({ root, view, getBodyView, writeClipboard, getViewGeneration = () => 0, publishNativeState }) {
  const document = root.ownerDocument;
  const listeners = [];
  let composing = false;
  let disposed = false;
  let requestID;
  let stateSequence = 0;

  function listen(element, type, handler) {
    element.addEventListener(type, handler);
    listeners.push(() => element.removeEventListener(type, handler));
  }

  function isEditing(element) {
    const control = element?.closest?.("input, textarea, select, [contenteditable]");
    return Boolean(control && (control.matches("input, textarea, select") || control.getAttribute("contenteditable") !== "false"));
  }

  function selectAllBody() {
    const body = getBodyView?.();
    if (disposed || !body || isEditing(document.activeElement) || isEditing(body.document.activeElement)) return false;
    body.focus();
    body.selectAll();
    return true;
  }

  function copySelection(event) {
    const body = getBodyView?.();
    if (disposed || !body || isEditing(event?.target) || isEditing(document.activeElement)
      || isEditing(body.document.activeElement)) return false;
    const text = body.selectedPlainText();
    if (text === null) {
      const selection = body.document.getSelection();
      if (event && (body.root.contains(event.target) || (selection?.rangeCount && !selection.isCollapsed
        && selection.getRangeAt(0).intersectsNode(body.root)))) event.preventDefault();
      return false;
    }
    try {
      if (event?.clipboardData?.setData) event.clipboardData.setData("text/plain", text);
      else if (writeClipboard) Promise.resolve(writeClipboard(text, requestID)).catch(() => {});
      else return false;
      event?.preventDefault();
      return true;
    } catch { return false; }
  }

  function handleKeyDown(event) {
    if (disposed) return;
    // Suppress WebKit's inherited Find entry; this preview has no Find feature.
    if ((event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === "f") {
      event.preventDefault();
      return;
    }
    if (composing || event.isComposing || event.keyCode === 229) return;
    if ((event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === "a"
      && !isEditing(event.target) && !isEditing(document.activeElement)) {
      if (selectAllBody()) event.preventDefault();
    }
  }

  function routingState() {
    const body = getBodyView?.();
    return { requestID, viewGeneration: getViewGeneration(), stateSequence: ++stateSequence,
      editorFocused: isEditing(document.activeElement), composing, hasBody: Boolean(body), htmlBody: body?.kind === "html" };
  }

  function publishState() {
    if (!disposed && requestID && publishNativeState) publishNativeState(routingState());
  }

  function executeNative(command, expectedRequest, expectedGeneration) {
    if (disposed || requestID !== expectedRequest || getViewGeneration() !== expectedGeneration) return { handled: false };
    let handled = false;
    let text;
    if (!composing && !isEditing(document.activeElement) && !isEditing(getBodyView?.()?.document.activeElement)) {
      if (command === "selectAll") handled = selectAllBody();
      else if (command === "copy" && getBodyView?.()) { text = getBodyView().selectedPlainText(); handled = true; }
    }
    const state = routingState();
    publishNativeState?.(state);
    return { handled, ...state, ...(typeof text === "string" ? { text } : {}) };
  }

  function bindDocument(nextRequest) { composing = false; requestID = nextRequest; publishState(); }
  function dispose() { composing = false; disposed = true; for (const remove of listeners) remove(); }

  listen(document, "keydown", handleKeyDown);
  listen(document, "copy", copySelection);
  listen(document, "focusin", publishState);
  listen(document, "focusout", () => view.queueMicrotask(publishState));
  listen(view, "focus", publishState);
  listen(view, "blur", () => view.queueMicrotask(publishState));
  listen(document, "compositionstart", () => { composing = true; publishState(); });
  listen(document, "compositionend", () => { composing = false; publishState(); });

  return { handleKeyDown, bindDocument, dispose, selectAllBody, copySelection, getBodyView, publishState, executeNative,
    get isComposing() { return composing; } };
}
