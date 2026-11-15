import AppKit
import Foundation
import WebKit

/// Actual offscreen production WebKit layout and body extraction checks.
/// This non-sandbox probe does not establish Finder directory access or physical
/// keyboard delivery, and never reads or writes the system pasteboard.
@MainActor
enum MarkdownImageChecks {
    static func run(probe: RenderProbe) async throws -> [String: Any] {
        let view = probe.controller.webView
        let source = try String(contentsOf: probe.fileURL, encoding: .utf8)
        let originalSize = probe.window.contentView?.frame.size ?? NSSize(width: 1000, height: 760)
        func resize(_ size: NSSize) {
            probe.controller.preferredContentSize = size
            probe.window.setContentSize(size)
            probe.controller.view.setFrameSize(size)
            probe.controller.view.layoutSubtreeIfNeeded()
        }
        defer { resize(originalSize) }
        func script(_ source: String) async throws -> Any? {
            try await view.callAsyncJavaScript(source, arguments: [:], in: nil, contentWorld: .page)
        }
        let initial = try await script("""
            const q=window.quicklook,body=q.getBodyView();
            if(body?.kind!=='rendered')throw new Error('Use the Markdown image fixture');
            // Visit each lazy image through the real scroll/layout path.
            for(const image of body.root.querySelectorAll('img')){
              image.scrollIntoView({block:'center'});
              const deadline=Date.now()+1500;
              while(!image.complete&&Date.now()<deadline)await new Promise(r=>setTimeout(r,20));
            }
            window.scrollTo(0,0);
            const images=[...body.root.querySelectorAll('img')].map(img=>({
              alt:img.alt,src:img.getAttribute('src'),loaded:img.naturalWidth>0,
              width:img.getBoundingClientRect().width,height:img.getBoundingClientRect().height,
              naturalWidth:img.naturalWidth,naturalHeight:img.naturalHeight,
              attributes:[...img.attributes].map(a=>a.name)}));
            const image=alt=>images.find(x=>x.alt===alt),near=(a,b)=>Math.abs(a-b)<0.6;
            const icon=image('OrbisPeek 应用图标'),both=image('width-height'),height=image('height-only'),width=image('width-only');
            const copyParagraph=[...body.root.querySelectorAll('p')].find(p=>p.textContent.startsWith('渲染选区：'));
            const range=document.createRange();range.selectNodeContents(copyParagraph);
            const selection=document.getSelection();selection.removeAllRanges();selection.addRange(range);
            const event=new KeyboardEvent('keydown',{key:'f',metaKey:true,bubbles:true,cancelable:true});document.dispatchEvent(event);
            return {images,checks:{
              exactlySevenRenderedImages:images.length===7,
              allLocalImagesLoaded:images.every(x=>x.loaded),
              onlyCurrentCapabilityURLs:images.every(x=>x.src.startsWith('quicklook-resource://local/'+window.__containerProbe.resourceToken+'/')),
              readme96PixelWidth:!!icon&&near(icon.width,96),
              widthOnlyKeepsNaturalRatio:!!width&&near(width.width,84)&&near(width.height/width.width,width.naturalHeight/width.naturalWidth),
              heightOnlyKeepsNaturalRatio:!!height&&near(height.height,72)&&near(height.height/height.width,height.naturalHeight/height.naturalWidth),
              explicitWidthAndHeightApplied:!!both&&near(both.width,96)&&near(both.height,48),
              ordinaryMarkdownImageLoaded:!!image('ordinary')?.loaded,
              unknownImageAttributesAbsent:images.every(x=>x.attributes.every(a=>['src','alt','width','height','loading','decoding'].includes(a))),
              untrustedScriptDidNotRun:!window.quicklookFixtureScriptExecuted,
              authoredScriptIsEscaped:!body.root.querySelector('script'),
              codeImageTagsRemainText:!image('inline-code')&&!image('fenced-code')&&[...body.root.querySelectorAll('code')].some(c=>c.textContent.includes('alt="inline-code"'))&&[...body.root.querySelectorAll('pre code')].some(c=>c.textContent.includes('alt="fenced-code"')),
              remoteAndSVGBlocked:q.report().blockedImages===2,
              renderedSelectionIsPlainText:body.selectedPlainText()==='渲染选区：中文加粗 与 inline_code。',
              onlyModeAndWrapButtons:[...document.querySelectorAll('.actions button')].map(x=>x.id).join(',')==='source-toggle,wrap-toggle',
              noFindUI:!document.querySelector('#find-button,#search-bar,#search-input'),
              commandFSuppressed:event.defaultPrevented
            }};
            """) as? [String: Any] ?? [:]
        var checks = initial["checks"] as? [String: Bool] ?? [:]
        resize(NSSize(width: 300, height: originalSize.height))
        try await Task.sleep(for: .milliseconds(60))
        var narrow = try await script("""
            const root=window.quicklook.getBodyView().root,wide=root.querySelector('img[alt="wide"]');
            const canvas=root.querySelector('.markdown-body'),rect=wide.getBoundingClientRect(),article=canvas.getBoundingClientRect(),style=getComputedStyle(canvas);
            const available=article.width-parseFloat(style.paddingLeft)-parseFloat(style.paddingRight);
            return {viewport:window.innerWidth,imageWidth:rect.width,imageHeight:rect.height,available,
              fits:rect.width<=available+0.6&&rect.left>=-0.6&&rect.right<=window.innerWidth+0.6,
              noDocumentOverflow:document.documentElement.scrollWidth<=window.innerWidth+1};
            """) as? [String: Any] ?? [:]
        narrow["nativeWindowContent"] = NSStringFromRect(probe.window.contentLayoutRect)
        narrow["nativeControllerFrame"] = NSStringFromRect(probe.controller.view.frame)
        narrow["nativeWebViewFrame"] = NSStringFromRect(view.frame)
        narrow["nativeContentMinSize"] = NSStringFromSize(probe.window.contentMinSize)
        checks["narrowWindowImageFits"] = narrow["fits"] as? Bool == true && (narrow["viewport"] as? Double ?? .infinity) <= 301
        checks["narrowWindowHasNoHorizontalOverflow"] = narrow["noDocumentOverflow"] as? Bool == true
        resize(originalSize)
        _ = try await script("document.getElementById('source-toggle').click();return true")
        try await Task.sleep(for: .milliseconds(60))
        let raw = try await script("""
            const body=window.quicklook.getBodyView();body.selectAll();
            return {source:body.kind==='source',noImages:body.root.querySelectorAll('img').length===0,text:body.selectedPlainText()};
            """) as? [String: Any] ?? [:]
        checks["sourceModeHasLiteralTagsWithoutImages"] = raw["source"] as? Bool == true && raw["noImages"] as? Bool == true
        checks["sourceSelectionMatchesOriginalFileExactly"] = raw["text"] as? String == source
        _ = try await script("document.getElementById('source-toggle').click();return true")
        try await Task.sleep(for: .milliseconds(60))
        checks["returnToRenderedRestores96PixelImage"] = try await script("""
            const body=window.quicklook.getBodyView(),icon=body.root.querySelector('img[alt="OrbisPeek 应用图标"]');
            for(const image of body.root.querySelectorAll('img')){
              image.scrollIntoView({block:'center'});const deadline=Date.now()+1500;
              while(!image.complete&&Date.now()<deadline)await new Promise(r=>setTimeout(r,20));
            }
            window.scrollTo(0,0);document.getSelection().removeAllRanges();
            return body.kind==='rendered'&&!!icon&&icon.naturalWidth>0&&Math.abs(icon.getBoundingClientRect().width-96)<0.6;
            """) as? Bool == true
        checks["nativeFindResponderUnavailable"] = !view.responds(to: #selector(NSResponder.performTextFinderAction(_:)))
        guard checks.count == 23, checks.values.allSatisfy({ $0 }) else {
            throw NSError(domain: "MarkdownImageProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: checks.filter { !$0.value }.keys.sorted().joined(separator: ", ") + " checks: \(checks.count); images: \(initial["images"] ?? []); narrow: \(narrow)"])
        }
        return ["passed": true, "checks": checks, "initialImages": initial["images"] ?? [], "narrowWindow": narrow,
                "scope": "Offscreen production WebKit with a non-sandbox synthetic local fixture, real image layout, mode toggle and selected text extraction; no system pasteboard access. Finder access and physical copy acceptance are separate."]
    }
}
