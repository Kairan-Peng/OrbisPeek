import AppKit
import Foundation
import WebKit

/// Offscreen production WebKit selection checks. DOM Ranges can address
/// unselectable nodes, so raw Range contents are diagnostic, not user-drag proof.
/// This probe does not send system events or touch the system pasteboard.
@MainActor
enum LineNumberSelectionChecks {
    static func run(probe: RenderProbe) async throws -> [String: Any] {
        let view = probe.controller.webView
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orbispeek-line-selection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let longText = String(repeating: "中文 long_value 123 ", count: 30)
        let fixtures: [(String, String, Bool)] = [
            ("selection.swift", "let message = \"中文 alpha 123\"\n\n\tlet count = 42\nlet longLine = \"\(longText)\"\nprint(message)\n", false),
            ("selection.md", "# 中文 selection 123\n\n\tindented value 42\nlong paragraph \(longText)\nfinal **bold** value\n", true),
            ("selection.json", "{\"alpha\":\"中文 123\",\"nested\":{\"count\":42,\"long\":\"\(longText)\"}}\n", false),
            ("selection.jsonl", "{\"alpha\":\"中文 123\"}\n\n  \t\n{\"beta\":\"\(longText)\"}\n{\"count\":42}\n", false),
        ]
        var checks: [String: Bool] = [:]
        var cases: [[String: Any]] = []

        func script(_ source: String) async throws -> Any? {
            try await view.callAsyncJavaScript(source, arguments: [:], in: nil, contentWorld: .page)
        }
        func load(_ url: URL) async throws {
            let count = probe.renderCount
            try await probe.controller.showFile(url)
            let deadline = Date().addingTimeInterval(3)
            while probe.renderCount == count && Date() < deadline { try await Task.sleep(for: .milliseconds(15)) }
            guard probe.renderCount > count else { throw NSError(domain: "LineSelectionProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthetic fixture render timed out"]) }
            _ = try await script("await window.quicklook.whenIdle();return true")
        }

        for (name, text, sourceMode) in fixtures {
            let file = directory.appendingPathComponent(name)
            try text.write(to: file, atomically: true, encoding: .utf8)
            try await load(file)
            if sourceMode { _ = try await script("document.getElementById('source-toggle').click();await window.quicklook.whenIdle();return true") }
            let result = try await script("""
                const q=window.quicklook,body=q.getBodyView();
                if(body?.kind!=='source')throw new Error('Expected a production source body');
                const codes=[...body.root.querySelectorAll('.source-line code')],numbers=[...body.root.querySelectorAll('.line-number')];
                const lines=body.sourceText.split('\\n'),last=codes.findLastIndex(code=>code.textContent.length>1);
                if(codes.length<4||last<3)throw new Error('Use the synthetic multiline fixture');
                const normalize=text=>text.replace(/\\s/g,'');
                const select=range=>{body.focus();const selection=document.getSelection();selection.removeAllRanges();selection.addRange(range);return selection;};
                function boundary(code,offset){
                  const walker=document.createTreeWalker(code,NodeFilter.SHOW_TEXT);let remaining=offset,node,last;
                  while((node=walker.nextNode())){last=node;if(remaining<=node.length)return [node,remaining];remaining-=node.length;}
                  return last?[last,last.length]:[code,0];
                }
                const startOffset=Math.min(2,codes[0].textContent.length);
                const range=document.createRange(),from=boundary(codes[0],startOffset),to=boundary(codes[last],codes[last].textContent.length-1);
                range.setStart(...from);range.setEnd(...to);const selection=select(range);
                const expected=lines.slice(0,last+1).join('\\n').slice(startOffset,-1),plain=body.selectedPlainText(),native=selection.toString();
                const numberStyle=getComputedStyle(numbers[1]),codeStyle=getComputedStyle(codes[1]);
                const current={native,plain,expected,rawRangeText:range.toString(),
                  style:{prefixed:numberStyle.getPropertyValue('-webkit-user-select'),unprefixed:numberStyle.getPropertyValue('user-select'),codePrefixed:codeStyle.getPropertyValue('-webkit-user-select'),codeUnprefixed:codeStyle.getPropertyValue('user-select')},
                  support:{prefixed:CSS.supports('-webkit-user-select','none'),unprefixed:CSS.supports('user-select','none')}};
                const excludes=current.style.prefixed==='none'||current.style.unprefixed==='none';
                const check={gutterUsesEffectiveNativeExclusion:excludes,
                  bodyRemainsNativelySelectable:native.length>0&&normalize(native).includes(normalize(lines[0].slice(startOffset))),
                  crossLineNativeSelectionHasNoGutterText:normalize(native)===normalize(expected),
                  crossLinePlainTextPreservesWhitespace:plain===expected};
                body.selectAll();const allNative=document.getSelection().toString(),allPlain=body.selectedPlainText();
                check.selectAllNativeSelectionHasNoGutterText=normalize(allNative)===normalize(body.sourceText);
                check.selectAllPlainTextPreservesBlankLinesAndIndentation=allPlain===body.sourceText;
                const toggle=document.getElementById('wrap-toggle');toggle.click();
                const unwrapped=getComputedStyle(codes[0]).whiteSpace;
                const wrappedSelection=select(range.cloneRange()),unwrappedNative=wrappedSelection.toString();
                check.wrapToggleDoesNotRestoreGutterSelection=normalize(unwrappedNative)===normalize(expected)&&body.selectedPlainText()===expected;
                toggle.click();
                const solo=document.createRange();solo.selectNodeContents(numbers[1]);select(solo);
                const gutterOnly={native:document.getSelection().toString(),rawRangeText:solo.toString(),plain:body.selectedPlainText()};
                check.gutterOnlyRangeCannotCopySource=body.selectedPlainText()===null;
                select(range.cloneRange());
                return {checks:check,...current,allNative,allPlain,sourceText:body.sourceText,gutterOnly,unwrappedWhiteSpace:unwrapped,wrappedWhiteSpace:getComputedStyle(codes[0]).whiteSpace,report:q.report()};
                """) as? [String: Any] ?? [:]
            for (key, value) in result["checks"] as? [String: Bool] ?? [:] { checks[name + "." + key] = value }
            var record = result
            record["fixture"] = name
            record["input"] = text
            cases.append(record)
        }

        // Leave a wrapped Markdown source selection for the optional snapshot.
        try await load(directory.appendingPathComponent("selection.md"))
        _ = try await script("""
            document.getElementById('source-toggle').click();await window.quicklook.whenIdle();
            const body=window.quicklook.getBodyView(),codes=[...body.root.querySelectorAll('.source-line code')];
            const range=document.createRange();range.setStart(codes[0],0);range.setEnd(codes.at(-2),codes.at(-2).childNodes.length);
            body.focus();const selection=document.getSelection();selection.removeAllRanges();selection.addRange(range);return true;
            """)
        return ["passed": checks.count == 32 && checks.values.allSatisfy({ $0 }), "checks": checks, "cases": cases,
                "scope": "Actual offscreen production WKWebView and native Selection text for synthetic Swift, Markdown source, formatted JSON and JSONL; no OS mouse/keyboard events, clipboard, folder permissions or registration. DOM Range can still address CSS-unselectable nodes; gutter-only native/raw strings are recorded without treating programmatic addressing as user-drag behavior. Physical drag highlight in Finder is a separate gate."]
    }
}
