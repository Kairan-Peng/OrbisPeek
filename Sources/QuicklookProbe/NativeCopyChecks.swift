import AppKit
import Foundation
import WebKit

/// Public native command dispatch against the production WebKit document.
/// A bounded service responder models Quick Look's Copy forwarding, without
/// activating an app or claiming actual Finder keyboard coverage.
@MainActor
enum NativeCopyChecks {
    static func run(probe: RenderProbe) async throws -> [String: Any] {
        let view = probe.controller.webView
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        func restore() {
            pasteboard.clearContents()
            let items = saved.map { representations in
                let item = NSPasteboardItem()
                for (type, data) in representations { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
        var restored = false
        defer { if !restored { restore() } }
        let previousResponder = view.nextResponder
        let service = CopyForwardingService(view: view)
        view.nextResponder = service
        defer { view.nextResponder = previousResponder }
        probe.window.makeFirstResponder(view)
        var checks: [String: Bool] = [:]
        var copiedTypes: [String: [String]] = [:]

        func script(_ source: String) async throws -> Any? {
            try await view.callAsyncJavaScript(source, arguments: [:], in: nil, contentWorld: .page)
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(50)) }
        func seed(_ value: String) {
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
        }
        func copy(expected: String) async throws -> Bool {
            service.copyCount = 0
            let sent = NSApp.sendAction(#selector(NSText.copy(_:)), to: service, from: nil)
            for _ in 0..<60 where pasteboard.string(forType: .string) != expected {
                try await Task.sleep(for: .milliseconds(15))
            }
            return sent && service.copyCount == 1 && pasteboard.string(forType: .string) == expected
        }
        func commandCount() async throws -> Int {
            try await script("return window.__nativeCopyCalls.length") as? Int ?? -1
        }
        func resetCalls() async throws { _ = try await script("window.__nativeCopyCalls=[];return true") }

        _ = try await script("""
            window.__nativeCopyOriginal=window.quicklook.commands.executeNative;
            window.__nativeCopyCalls=[];
            window.quicklook.commands.executeNative=(...args)=>{
              window.__nativeCopyCalls.push(args[0]);return window.__nativeCopyOriginal(...args);
            };
            const body=window.quicklook.getBodyView(),p=body.root.querySelector('p');
            if(body.kind!=='rendered'||!p)throw new Error('Use the native-copy synthetic Markdown fixture');
            body.focus();const range=document.createRange();range.selectNodeContents(p);
            const selection=document.getSelection();selection.removeAllRanges();selection.addRange(range);return true;
            """)
        try await settle()
        seed("render copy sentinel")
        checks["renderedServiceCopyMatchesPlainText"] = try await copy(expected: "渲染选区：中文加粗 与 inline_code。")
        checks["renderedServiceInvokesBodyExactlyOnce"] = try await commandCount() == 1
        copiedTypes["rendered"] = pasteboard.pasteboardItems?.flatMap { $0.types.map(\.rawValue) } ?? []
        checks["renderedCopyContainsOnlyPlainTextType"] = pasteboard.pasteboardItems?.count == 1 && pasteboard.pasteboardItems?.first?.types == [.string]

        _ = try await script("document.getSelection().removeAllRanges();window.__nativeCopyCalls=[];return true")
        seed("empty selection sentinel")
        let emptyChangeCount = pasteboard.changeCount
        service.copyCount = 0
        _ = NSApp.sendAction(#selector(NSText.copy(_:)), to: service, from: nil)
        try await settle()
        checks["emptySelectionKeepsClipboard"] = pasteboard.changeCount == emptyChangeCount && pasteboard.string(forType: .string) == "empty selection sentinel"
        let emptyCommandCount = try await commandCount()
        checks["emptySelectionConsumesServiceCopyOnce"] = service.copyCount == 1 && emptyCommandCount == 1

        _ = try await script("document.getElementById('source-toggle').click();return true")
        try await settle()
        _ = try await script("""
            const body=window.quicklook.getBodyView();if(body.kind!=='source')throw new Error('Source mode missing');
            const code=[...body.root.querySelectorAll('.source-line code')].find(el=>el.textContent.startsWith('渲染选区：'));
            if(!code)throw new Error('Source fixture paragraph missing');body.focus();
            const range=document.createRange();range.selectNodeContents(code);
            const selection=document.getSelection();selection.removeAllRanges();selection.addRange(range);
            window.__nativeCopyCalls=[];return true;
            """)
        try await settle()
        seed("source copy sentinel")
        checks["sourceServiceCopyRetainsMarkdown"] = try await copy(expected: "渲染选区：**中文加粗** 与 `inline_code`。")
        checks["sourceServiceInvokesBodyExactlyOnce"] = try await commandCount() == 1
        copiedTypes["source"] = pasteboard.pasteboardItems?.flatMap { $0.types.map(\.rawValue) } ?? []
        checks["sourceCopyContainsOnlyPlainTextType"] = pasteboard.pasteboardItems?.count == 1 && pasteboard.pasteboardItems?.first?.types == [.string]

        _ = try await script("""
            const editor=Object.assign(document.body.appendChild(document.createElement('input')),{id:'native-copy-editor',value:'native editing sentinel'});
            editor.focus();editor.setSelectionRange(7,14);window.__nativeCopyCalls=[];return true;
            """)
        try await settle()
        seed("editor copy sentinel")
        checks["editorServiceCopyUsesNativeSelection"] = try await copy(expected: "editing")
        checks["editorServiceDoesNotInvokeBodyCommand"] = try await commandCount() == 0
        _ = NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: view, from: nil)
        try await settle()
        checks["editorSelectAllRemainsNative"] = try await script("const e=document.getElementById('native-copy-editor');return e.selectionStart===0&&e.selectionEnd===e.value.length") as? Bool == true
        seed("native pasted sentinel")
        _ = NSApp.sendAction(#selector(NSText.paste(_:)), to: view, from: nil)
        try await settle()
        checks["editorPasteRemainsNative"] = try await script("return document.getElementById('native-copy-editor').value==='native pasted sentinel'") as? Bool == true

        // Exercise the controller's DOM recheck fallback when a body command
        // arrives after focus has moved into an editor.
        _ = try await script("const e=document.getElementById('native-copy-editor');e.value='focus editing sentinel';e.focus();e.setSelectionRange(6,13);window.__nativeCopyCalls=[];return true")
        seed("focus race sentinel")
        probe.controller.performPreviewCommand("copy")
        for _ in 0..<60 where pasteboard.string(forType: .string) != "editing" { try await Task.sleep(for: .milliseconds(15)) }
        let editorRecheckCommandCount = try await commandCount()
        checks["liveEditorRecheckCopiesNativelyOnce"] = pasteboard.string(forType: .string) == "editing" && editorRecheckCommandCount == 1
        try await resetCalls()
        _ = try await script("document.getElementById('native-copy-editor').dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true}));return true")
        try await settle()
        seed("composition sentinel")
        checks["compositionServiceCopyRetainsNativeEditor"] = try await copy(expected: "editing")
        checks["compositionDoesNotInvokeBodyCommand"] = try await commandCount() == 0
        _ = try await script("document.getElementById('native-copy-editor').dispatchEvent(new CompositionEvent('compositionend',{bubbles:true}));window.quicklook.getBodyView().focus();window.quicklook.getBodyView().selectAll();return true")
        try await settle()

        // The old WebKit DOM intentionally remains visible after invalidation.
        // Neither queued body work nor a new service action may copy it.
        try await resetCalls()
        seed("closed request sentinel")
        let closedChangeCount = pasteboard.changeCount
        probe.controller.performPreviewCommand("copy")
        probe.controller.invalidatePreview()
        service.copyCount = 0
        _ = NSApp.sendAction(#selector(NSText.copy(_:)), to: service, from: nil)
        try await settle()
        checks["closedRequestCannotCopyRemainingDOM"] = pasteboard.changeCount == closedChangeCount && pasteboard.string(forType: .string) == "closed request sentinel"
        let closedCommandCount = try await commandCount()
        checks["closedRequestDoesNotInvokeBodyOrReenterService"] = service.copyCount == 1 && closedCommandCount == 0
        checks["findRemainsUnavailable"] = !view.responds(to: #selector(NSResponder.performTextFinderAction(_:)))
        restore()
        restored = true
        let after = pasteboard.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
        checks["clipboardAllItemsAndTypesRestoredExactly"] = saved.count == after.count && zip(saved, after).allSatisfy { left, right in
            left.count == right.count && zip(left, right).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }
        guard checks.values.allSatisfy({ $0 }) else {
            throw NSError(domain: "NativeCopyProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: checks.filter { !$0.value }.keys.sorted().joined(separator: ", ") + " synthetic copy types: \(copiedTypes)"])
        }
        return ["passed": true, "checks": checks, "syntheticCopyItemTypes": copiedTypes,
                "scope": "Offscreen production WebKit; Objective-C service Copy action forwarding public doCommand(by:), native editor actions, and saved/restored pasteboard. Actual Finder keyboard acceptance is separate."]
    }
}

@MainActor
private final class CopyForwardingService: NSResponder {
    private weak var view: WKWebView?
    var copyCount = 0
    init(view: WKWebView) { self.view = view; super.init() }
    required init?(coder: NSCoder) { nil }
    @objc func copy(_ sender: Any?) {
        copyCount += 1
        guard copyCount < 8 else { return }
        view?.doCommand(by: #selector(NSText.copy(_:)))
    }
}
