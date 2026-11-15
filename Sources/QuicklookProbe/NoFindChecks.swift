import AppKit
import Foundation
import WebKit

/// Offscreen checks of the final toolbar and native action surface.
@MainActor
enum NoFindChecks {
    static func run(probe: RenderProbe) async throws -> [String: Any] {
        let view = probe.controller.webView
        var checks = try await view.callAsyncJavaScript("""
            const q=window.quicklook,body=q.getBodyView();
            const noUI=()=>!document.querySelector('#find-button,#search-bar,#search-input,#reader-status');
            const event=new KeyboardEvent('keydown',{key:'f',metaKey:true,bubbles:true,cancelable:true});
            document.dispatchEvent(event);
            body.selectAll();
            const result=q.commands.executeNative('copy',window.__containerProbe.requestID,1);
            return {twoToolbarIcons:[...document.querySelectorAll('.actions button')].map(x=>x.id).join(',')==='source-toggle,wrap-toggle',
              noFindUI:noUI(),noFindCommand:typeof q.commands.openFind==='undefined',
              commandFSuppressed:event.defaultPrevented,
              nativeFindCommandRejected:q.commands.executeNative('find',window.__containerProbe.requestID,1).handled===false,
              selectedPlainTextCopyAvailable:result.handled===true&&typeof result.text==='string'&&result.text.length>0};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Bool] ?? [:]
        checks["nativeFindResponderUnavailable"] = !view.responds(to: #selector(NSResponder.performTextFinderAction(_:)))
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                    timestamp: 0, windowNumber: probe.window.windowNumber, context: nil,
                                    characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!
        checks["nativeCommandFConsumed"] = view.performKeyEquivalent(with: event)
        view.performTextFinderAction(nil)
        probe.controller.performPreviewCommand("find")
        checks["nativeActionsCannotCreateFindUI"] = try await view.callAsyncJavaScript("return !document.querySelector('#find-button,#search-bar,#search-input')", arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        guard checks.count == 9, checks.values.allSatisfy({ $0 }) else {
            throw NSError(domain: "NoFindProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: checks.filter { !$0.value }.keys.sorted().joined(separator: ", ")])
        }
        return ["passed": true, "checks": checks, "scope": "Offscreen actual WebKit and public native action dispatch; no physical keyboard, Finder or clipboard writes."]
    }
}
