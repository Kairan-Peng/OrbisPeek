import AppKit
import WebKit

/// Window-local standard actions enter the trusted main frame. Child event
/// listeners cannot run in the static HTML sandbox. Editing controls retain
/// native selection, clipboard and IME behavior.
@MainActor
final class PreviewWebView: WKWebView {
    var commandState: (() -> PreviewCommandState)?
    var runCommand: ((String) -> Void)?
    private lazy var bodyTarget = BodyCommandTarget { [weak self] in self?.copyBody() }
    private var markedText: Bool { inputContext?.client.hasMarkedText() == true }
    private var routesBody: Bool { !markedText && commandState?().routesBody == true }
    private var routesNativeCopy: Bool {
        guard let state = commandState?(), state.requestID != nil, state.generation >= 0, state.hasBody else { return false }
        return markedText || state.editorFocused || state.composing
    }

    private func copyBody() {
        if routesBody { runCommand?("copy") }
    }

    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(NSResponder.performTextFinderAction(_:)) || selector == NSSelectorFromString("performFindPanelAction:") { return false }
        if selector == #selector(NSText.copy(_:)), !routesNativeCopy { return false }
        return super.responds(to: selector)
    }

    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if action == #selector(NSText.copy(_:)), !routesNativeCopy { return bodyTarget }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    override func doCommand(by selector: Selector) {
        // Quick Look's service forwards Copy here rather than using AppKit's
        // supplemental action target. Letting WebKit forward it up the responder
        // chain returns to that service and recurses. Consume the body command
        // here once; editor and composition commands retain WebKit's behavior.
        // Loading/closed state cannot copy a previous document's remaining DOM.
        if selector == #selector(NSText.copy(_:)), !routesNativeCopy {
            copyBody()
            return
        }
        super.doCommand(by: selector)
    }

    override func selectAll(_ sender: Any?) {
        if routesBody { runCommand?("selectAll") }
        else { super.selectAll(sender) }
    }

    override func performTextFinderAction(_ sender: Any?) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "f" { return true }
        if !markedText, modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if routesBody, key == "a" || key == "c" { runCommand?(key == "a" ? "selectAll" : "copy"); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class BodyCommandTarget: NSResponder {
    private let copyBody: () -> Void
    init(copyBody: @escaping () -> Void) { self.copyBody = copyBody; super.init() }
    required init?(coder: NSCoder) { nil }
    @objc func copy(_ sender: Any?) { copyBody() }
}
