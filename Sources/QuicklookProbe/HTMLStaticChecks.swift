import AppKit
import Foundation
import WebKit

/// Explicit forced-mode engine coverage for the sanitizer, container and commands.
/// Normal unforced file-pipeline cases are validated separately by validate-core.
@MainActor
enum HTMLStaticChecks {
    static func run(probe: RenderProbe) async throws -> [String: Any] {
        let view = probe.controller.webView
        let canvas = try await canvasPolicy(probe: probe)
        var result = try await view.callAsyncJavaScript("""
            const body=window.quicklook.getBodyView(),frame=document.querySelector('iframe.html-document');
            if(body?.kind!=='html'||!frame)throw new Error('Production HTML child unavailable');
            const child=body.document;
            window.__staticInitialFrame=frame;
            return {forcedMode:true,registryMode:window.__containerProbe.payload.mode,report:window.quicklook.report(),
              bodyKind:body.kind,childURL:child.URL,sandbox:frame.getAttribute('sandbox'),text:child.body.innerText,
              childScripts:child.scripts.length,parentScripts:document.scripts.length,
              parentScriptRan:!!window.quicklookFixtureScriptExecuted,childScriptRan:!!frame.contentWindow.quicklookFixtureScriptExecuted,
              childColor:frame.contentWindow.getComputedStyle(child.body).color,
              titleSize:child.getElementById('html-title')?frame.contentWindow.getComputedStyle(child.getElementById('html-title')).fontSize:null,
              parentColor:getComputedStyle(document.getElementById('file-basename')).color,
              images:[...child.images].map(img=>({src:img.getAttribute('src'),loaded:img.naturalWidth>0})),
              failedPlaceholders:child.querySelectorAll('[data-quicklook-owned="failed-image"]').length,
              forbiddenNodes:child.querySelectorAll('script,iframe,object,embed,form,input,video,audio,svg,math,base,meta,link,picture,source').length,
              eventAttributes:[...child.querySelectorAll('*')].flatMap(el=>[...el.attributes].filter(a=>/^on/i.test(a.name)).map(a=>a.name))};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
        result["canvasPolicy"] = canvas
        result["whitespaceCopy"] = try await whitespaceCopy(view: view)
        result["whitespaceBoundaryCopy"] = try await whitespaceBoundaryCopy(view: view)
        result["rootAndDetails"] = try await view.callAsyncJavaScript("""
            const body=window.quicklook.getBodyView(),child=body.document,root=child.documentElement,inherited=child.getElementById('root-inherited'),details=child.getElementById('visibility-details');
            const rootStyle=inherited?child.defaultView.getComputedStyle(inherited):null;
            const result={root:{className:root.className,lang:root.lang,dir:root.dir,inlineStyle:root.getAttribute('style'),
              inheritedColor:rootStyle?.color??null,inheritedFontSize:rootStyle?.fontSize??null,selectorFontStyle:rootStyle?.fontStyle??null}};
            const savedRootStyle=root.getAttribute('style'),savedHidden=root.hasAttribute('hidden');
            result.hiddenRoot=[];
            for(const rule of ['hidden','display:none','opacity:0','content-visibility:hidden']){
              root.removeAttribute('hidden');root.setAttribute('style',savedRootStyle??'');
              if(rule==='hidden')root.setAttribute('hidden','');else root.style.cssText+=';'+rule;
              body.selectAll();const copied=body.selectedPlainText();
              result.hiddenRoot.push({rule,copy:copied,matches:window.quicklook.search('needle').matches,
                display:child.defaultView.getComputedStyle(root).display,opacity:child.defaultView.getComputedStyle(root).opacity,
                contentVisibility:child.defaultView.getComputedStyle(root).contentVisibility});
            }
            root.removeAttribute('hidden');root.setAttribute('style',savedRootStyle??'');window.quicklook.search('');
            if(inherited){
              const inheritedStyle=inherited.getAttribute('style');root.style.visibility='hidden';inherited.style.visibility='visible';body.selectAll();
              result.visibleDescendant={copy:body.selectedPlainText(),visibleMatches:window.quicklook.search('Root inheritance marker').matches,
                hiddenMatches:window.quicklook.search('Alpha needle').matches};
              if(inheritedStyle===null)inherited.removeAttribute('style');else inherited.setAttribute('style',inheritedStyle);
            }
            if(savedRootStyle===null)root.removeAttribute('style');else root.setAttribute('style',savedRootStyle);
            if(savedHidden)root.setAttribute('hidden','');window.quicklook.search('');child.getSelection().removeAllRanges();
            if(details){
              body.selectAll();
              result.closed={nativeText:child.body.innerText,nativeSelection:child.getSelection().toString(),copy:body.selectedPlainText(),
                hiddenMatches:window.quicklook.search('Hidden detail needle').matches,summaryMatches:window.quicklook.search('Visible summary').matches,
                secondSummaryMatches:window.quicklook.search('Hidden second summary').matches};
              window.quicklook.search('');details.open=true;body.selectAll();
              result.open={nativeText:child.body.innerText,nativeSelection:child.getSelection().toString(),copy:body.selectedPlainText(),
                hiddenMatches:window.quicklook.search('Hidden detail needle').matches};
              window.quicklook.search('');details.open=false;child.getSelection().removeAllRanges();
            }
            return result;
            """, arguments: [:], in: nil, contentWorld: .page)
        result["anchor"] = try await view.callAsyncJavaScript("""
            const body=window.quicklook.getBodyView(),anchor=body.root.querySelector('a[href="#bottom"]');
            if(!anchor)return {present:false};
            anchor.click();await new Promise(resolve=>setTimeout(resolve,60));
            return {present:true,url:body.document.URL,fragment:body.document.defaultView.location.hash,scrollY:body.document.defaultView.scrollY};
            """, arguments: [:], in: nil, contentWorld: .page)
        result["modes"] = try await view.callAsyncJavaScript("""
            const child=window.quicklook.getBodyView().document,authored=child.querySelector('.toolbar');
            const authorText=authored?.textContent??null;
            document.getElementById('source-toggle').click();await window.quicklook.whenIdle();
            const source={kind:window.quicklook.getBodyView().kind,sourceMode:window.quicklook.report().sourceMode,
              hiddenFrame:window.__staticInitialFrame.hidden};
            document.getElementById('source-toggle').click();await window.quicklook.whenIdle();
            return {authorText,source,rendered:{kind:window.quicklook.getBodyView().kind,
              sameFrame:document.querySelector('iframe.html-document')===window.__staticInitialFrame,
              sourceMode:window.quicklook.report().sourceMode,wrapDisabled:document.getElementById('wrap-toggle').disabled},
              noFindUI:!document.querySelector('#find-button,#search-bar,#search-input')};
            """, arguments: [:], in: nil, contentWorld: .page)
        result["commands"] = try await commands(probe: probe)
        result["resourceCapabilities"] = try await resourceCapabilities(probe: probe)
        if probe.fileURL.lastPathComponent == "preview.html" { result["lifecycle"] = try await lifecycle(probe: probe) }
        // Restore the initial rendered view for the ordinary active-body metrics.
        _ = try await view.callAsyncJavaScript("""
            document.getElementById('probe-editor')?.remove();window.quicklook.getBodyView().focus();return true;
            """, arguments: [:], in: nil, contentWorld: .page)
        result["limitations"] = [
            "This explicit forced-mode engine probe is separate from normal unforced HTML file-pipeline cases in validate-core.",
            "Probe-only NSApplication keyWindow/mainWindow overrides enable standard menu target lookup without activation.",
            "Synthetic native action dispatch and editor clipboard checks do not prove physical keyboard, IME or Finder delivery.",
            "Synthetic child anchor.click did not navigate; genuine physical link navigation remains unverified.",
            "Copy coverage is standard nil-target menu/action lookup. Explicit-to-web or WebKit-owned context-menu Copy is not claimed custom serialized.",
        ]
        return result
    }

    private static func canvasPolicy(probe: RenderProbe) async throws -> [String: Any] {
        let view = probe.controller.webView
        let oldApp = NSApp.appearance, oldWindow = probe.window.appearance
        let oldRoot = probe.controller.view.appearance, oldWeb = view.appearance
        func restoreAppearance() { NSApp.appearance = oldApp; probe.window.appearance = oldWindow; probe.controller.view.appearance = oldRoot; view.appearance = oldWeb }
        defer { restoreAppearance() }
        let originalDark = try await view.callAsyncJavaScript("return matchMedia('(prefers-color-scheme: dark)').matches", arguments: [:], in: nil, contentWorld: .page) as? Bool ?? false
        var hosts: [[String: Any]] = []
        for (host, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let native = NSAppearance(named: appearance)
            NSApp.appearance = native; probe.window.appearance = native; probe.controller.view.appearance = native; view.appearance = native
            let evidence = try await view.callAsyncJavaScript("""
                const expectedDark=host==='dark',expectedPage=expectedDark?'rgb(30, 32, 36)':'rgb(255, 255, 255)';
                for(let i=0;i<100;i++){
                  if(matchMedia('(prefers-color-scheme: dark)').matches===expectedDark&&getComputedStyle(document.body).backgroundColor===expectedPage)break;
                  await new Promise(resolve=>setTimeout(resolve,20));
                }
                const state=window.__containerProbe;
                const documents=[
                  {name:'unstyled',html:'<p>Browser paper</p>'},
                  {name:'authored-root',html:'<html style="color:rgb(18,52,86)"><body><p>Authored root foreground</p></body></html>'},
                  {name:'authored-body',html:'<html style="color:rgb(18,52,86)"><body style="color:rgb(71,82,93);background:rgb(240,241,242)"><p>Authored body foreground</p></body></html>'},
                  {name:'authored-dark-inline',html:'<html style="color-scheme:dark"><body><p>Explicit dark scheme</p></body></html>'},
                  {name:'authored-dark-stylesheet',html:'<style>html{color-scheme:dark;background:Canvas;color:CanvasText}</style><p>Explicit dark stylesheet</p>'},
                  {name:'authored-dark-root-selector',html:'<style>:root{color-scheme:dark;background:Canvas;color:CanvasText}</style><p>Explicit dark root selector</p>'},
                  {name:'authored-dark-universal',html:'<style>*{color-scheme:dark;background:Canvas;color:CanvasText}</style><p>Explicit dark universal selector</p>'},
                  {name:'authored-dark-layer',html:'<style>@layer theme{html{color-scheme:dark;background:rgb(8,9,10);color:rgb(230,231,232)}}</style><p>Explicit layered author theme</p>'}];
                const cases=[];
                for(const test of documents){
                  await window.quicklook.render({...state.payload,text:test.html,mode:'html',language:'html',fileName:'canvas-policy.html',resourceToken:state.resourceToken},state.requestID,{});
                  const child=window.quicklook.getBodyView().document,root=child.documentElement,body=child.body;
                  function reference(scheme){const element=child.createElement('div');element.style.cssText='color-scheme:'+scheme+';background:Canvas;color:CanvasText';body.append(element);const css=child.defaultView.getComputedStyle(element);const result={background:css.backgroundColor,color:css.color};element.remove();return result;}
                  const rootCSS=child.defaultView.getComputedStyle(root),bodyCSS=child.defaultView.getComputedStyle(body);
                  cases.push({name:test.name,root:{scheme:rootCSS.colorScheme,background:rootCSS.backgroundColor,color:rootCSS.color,inline:root.getAttribute('style')},
                    body:{background:bodyCSS.backgroundColor,color:bodyCSS.color,inline:body.getAttribute('style')},
                    lightCanvas:reference('light'),darkCanvas:reference('dark'),parentBackground:getComputedStyle(document.body).backgroundColor,
                    toolbarBackground:getComputedStyle(document.querySelector('.toolbar')).backgroundColor,mainDark:matchMedia('(prefers-color-scheme: dark)').matches});
                }
                document.getElementById('source-toggle').click();await window.quicklook.whenIdle();
                const source={kind:window.quicklook.getBodyView().kind,background:getComputedStyle(document.body).backgroundColor,
                  codeColor:getComputedStyle(document.querySelector('#content code')).color,parentColor:getComputedStyle(document.body).color,
                  toolbarBackground:getComputedStyle(document.querySelector('.toolbar')).backgroundColor,mainDark:matchMedia('(prefers-color-scheme: dark)').matches};
                await window.quicklook.render({...state.payload,resourceToken:state.resourceToken},state.requestID,{});
                return {host,mainDark:matchMedia('(prefers-color-scheme: dark)').matches,parentBackground:getComputedStyle(document.body).backgroundColor,cases,source};
                """, arguments: ["host": host], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
            hosts.append(evidence)
        }
        restoreAppearance()
        let restored = try await view.callAsyncJavaScript("""
            for(let i=0;i<100;i++){
              if(matchMedia('(prefers-color-scheme: dark)').matches===originalDark)return true;
              await new Promise(resolve=>setTimeout(resolve,20));
            }return false;
            """, arguments: ["originalDark": originalDark], in: nil, contentWorld: .page) as? Bool ?? false
        return ["hosts": hosts, "originalAppearanceRestored": restored,
                "policy": "Opaque light browser canvas by default; author later/inline CSS may override scheme, foreground and background. Shell/source retain host system appearance."]
    }

    private static func whitespaceCopy(view: WKWebView) async throws -> Any? {
        try await view.callAsyncJavaScript("""
            const body=window.quicklook.getBodyView(),child=body.document,section=child.createElement('section');
            section.style.cssText='display:block;width:700px';child.body.append(section);
            const cases=[
              {name:'pre-line',tag:'p',parent:'pre-line',text:preLineSample,expected:preLineExpected,mode:'pre-line',lines:true,cells:3},
              {name:'pre-normal',tag:'pre',parent:'normal',text:sample,expected:'AA BB CC',mode:'normal',lines:false,cells:3},
              {name:'pre-child-normal',tag:'pre',parent:'pre',child:'normal',text:sample,expected:'AA BB CC',mode:'normal',lines:false,cells:3},
              {name:'pre-child-nowrap',tag:'pre',parent:'pre',child:'nowrap',text:sample,expected:'AA BB CC',mode:'nowrap',lines:false,cells:3},
              {name:'inherited-pre',tag:'pre',parent:'pre',child:'',text:sample,expected:sample,mode:'pre',lines:true,cells:4},
              {name:'inherited-pre-wrap',tag:'div',parent:'pre-wrap',child:'',text:sample,expected:sample,mode:'pre-wrap',lines:true,cells:4},
              {name:'inherited-break-spaces',tag:'div',parent:'break-spaces',child:'',text:sample,expected:sample,mode:'break-spaces',lines:true,cells:4}];
            try{return cases.map(test=>{
              const wrapper=child.createElement(test.tag);
              wrapper.style.cssText='font-family:monospace;font-size:20px;line-height:30px;width:600px;margin:0;padding:0;white-space:'+test.parent;
              let target=wrapper;
              if('child' in test){target=child.createElement('span');if(test.child)target.style.whiteSpace=test.child;wrapper.append(target);}
              const node=child.createTextNode(test.text);target.append(node);section.append(wrapper);
              function rect(index){const range=child.createRange();range.setStart(node,index);range.setEnd(node,index+1);const r=range.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width};}
              const a=rect(0),next=rect(1),b=rect(test.text.indexOf('BB')),c=rect(test.text.indexOf('CC')),advance=next.x-a.x;
              const range=child.createRange();range.selectNodeContents(target);const selection=child.getSelection();selection.removeAllRanges();selection.addRange(range);
              const style=child.defaultView.getComputedStyle(target);
              return {name:test.name,source:test.text,expectedCopy:test.expected,copy:body.selectedPlainText(),nativeSelection:selection.toString(),
                computedWhiteSpace:style.whiteSpace,computedCollapse:style.whiteSpaceCollapse,computedWrapMode:style.textWrapMode,
                expectedWhiteSpace:test.mode,expectedNewline:test.lines,expectedSpaceAdvances:test.cells,
                characterAdvance:advance,spaceAdvances:(b.x-a.x)/advance,lineDelta:c.y-a.y,lineHeight:parseFloat(style.lineHeight),
                nextLineOffsetAdvances:(c.x-a.x)/advance,
                lineEdgeSpaceWidths:test.name==='pre-line'?[rect(test.text.indexOf('\\n')-1).width,rect(test.text.indexOf('\\n')+1).width]:[]};
            });}finally{section.remove();child.getSelection().removeAllRanges();}
            """, arguments: ["sample": "AA  BB\nCC", "preLineSample": "AA \t BB \n \t CC", "preLineExpected": "AA BB\nCC"], in: nil, contentWorld: .page)
    }

    private static func whitespaceBoundaryCopy(view: WKWebView) async throws -> Any? {
        try await view.callAsyncJavaScript("""
            const body=window.quicklook.getBodyView(),child=body.document,section=child.createElement('section');child.body.append(section);
            try{return ['newline-before-inline','newline-after-inline'].map(name=>{
              const wrapper=child.createElement('p'),span=child.createElement('span');
              wrapper.style.cssText='font:20px/30px monospace;width:600px;margin:0;padding:0;white-space:pre-line';
              const before=name==='newline-before-inline';
              const first=child.createTextNode(before?firstBefore:firstAfter),second=child.createTextNode(before?secondBefore:secondAfter);
              if(before){wrapper.append(first);span.append(second);wrapper.append(span);}else{span.append(first);wrapper.append(span,second);}
              section.append(wrapper);
              function rect(node,index){const range=child.createRange();range.setStart(node,index);range.setEnd(node,index+1);const r=range.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width};}
              function select(from,start,to,end){const range=child.createRange();range.setStart(from,start);range.setEnd(to,end);const selection=child.getSelection();selection.removeAllRanges();selection.addRange(range);}
              const a=rect(first,0),next=rect(first,1),c=rect(second,second.length-2),advance=next.x-a.x;
              const trailing=rect(first,2),leading=rect(second,before?0:1);
              select(first,0,second,second.length);const copy=body.selectedPlainText(),nativeSelection=child.getSelection().toString();
              select(first,1,second,second.length-1);const partial=body.selectedPlainText();
              select(second,before?0:1,second,second.length);const withoutPrecedingNewline=body.selectedPlainText();
              select(first,0,first,3);const withoutFollowingNewline=body.selectedPlainText();
              const walker=child.createTreeWalker(wrapper,NodeFilter.SHOW_TEXT);let textNodeCount=0;while(walker.nextNode())textNodeCount++;
              return {name,parts:[first.data,second.data],textNodeCount,copy,nativeSelection,partial,withoutPrecedingNewline,withoutFollowingNewline,
                computedModes:[child.defaultView.getComputedStyle(first.parentElement).whiteSpace,child.defaultView.getComputedStyle(second.parentElement).whiteSpace],
                characterAdvance:advance,lineDelta:c.y-a.y,nextLineOffsetAdvances:(c.x-a.x)/advance,lineEdgeSpaceWidths:[trailing.width,leading.width]};
            });}finally{section.remove();child.getSelection().removeAllRanges();}
            """, arguments: ["firstBefore": "AA \n", "secondBefore": " CC", "firstAfter": "AA ", "secondAfter": "\n CC"], in: nil, contentWorld: .page)
    }

    private static func resourceCapabilities(probe: RenderProbe) async throws -> Any? {
        try await probe.controller.webView.callAsyncJavaScript("""
            const token=window.__containerProbe.resourceToken;
            async function image(src){const img=document.createElement('img');img.hidden=true;document.body.append(img);img.src=src;
              const deadline=Date.now()+600;while(!img.complete&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,15));
              const result={loaded:img.naturalWidth>0,complete:img.complete};img.remove();return result;}
            const authorized=await image('quicklook-resource://local/'+token+'/assets/local-swatch.png');
            const tokenless=await image('quicklook-resource://local/assets/local-swatch.png');
            const wrongToken=await image('quicklook-resource://local/00000000-0000-0000-0000-000000000000/assets/local-swatch.png');
            return {authorized,tokenless,wrongToken};
            """, arguments: [:], in: nil, contentWorld: .page)
    }

    private static func lifecycle(probe: RenderProbe) async throws -> [String: Any] {
        let view = probe.controller.webView
        let old = try await view.callAsyncJavaScript("return window.__containerProbe", arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
        probe.window.orderOut(nil)
        try await Task.sleep(for: .milliseconds(40))
        let hidden = try await view.callAsyncJavaScript("""
            const reply=await window.webkit.messageHandlers.quicklookHTML.postMessage({action:'prepareHTML',requestID:oldRequest,html:'hidden must fail'});
            const img=document.createElement('img');img.hidden=true;document.body.append(img);img.src='quicklook-resource://local/'+oldToken+'/assets/%6cocal-swatch.png';
            for(let i=0;i<30&&!img.complete;i++)await new Promise(resolve=>setTimeout(resolve,10));
            const loaded=img.naturalWidth>0;img.remove();return {bridgeRejected:reply.ok===false,oldImageLoaded:loaded};
            """, arguments: ["oldRequest": old["requestID"] ?? "", "oldToken": old["resourceToken"] ?? ""], in: nil, contentWorld: .page)
        let before = probe.renderCount
        probe.window.orderBack(nil)
        for _ in 0..<100 where probe.renderCount == before { try await Task.sleep(for: .milliseconds(20)) }
        let resumed = try await view.callAsyncJavaScript("""
            const body=window.quicklook.getBodyView();return {requestID:window.__containerProbe.requestID,token:window.__containerProbe.resourceToken,
              kind:body?.kind,loadedImages:[...body.document.images].filter(img=>img.naturalWidth>0).length};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
        let miniRequest = resumed["requestID"] as? String ?? ""
        let miniCount = probe.renderCount
        probe.window.miniaturize(nil)
        for _ in 0..<30 where !probe.window.isMiniaturized { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(40))
        let miniRejected = try await view.callAsyncJavaScript("""
            const reply=await window.webkit.messageHandlers.quicklookHTML.postMessage({action:'prepareHTML',requestID:requestID,html:'minimized must fail'});return reply.ok===false;
            """, arguments: ["requestID": miniRequest], in: nil, contentWorld: .page) as? Bool ?? false
        probe.window.deminiaturize(nil)
        for _ in 0..<100 where probe.renderCount == miniCount { try await Task.sleep(for: .milliseconds(20)) }
        let miniResumed = try await view.callAsyncJavaScript("""
            const body=window.quicklook.getBodyView();return body?.kind==='html' && window.__containerProbe.requestID!==oldRequest && [...body.document.images].some(img=>img.naturalWidth>0);
            """, arguments: ["oldRequest": miniRequest], in: nil, contentWorld: .page) as? Bool ?? false
        // Queue a resume, then immediately issue a different file. The explicit
        // request must win before the deferred appearance callback runs.
        probe.window.orderOut(nil)
        try await Task.sleep(for: .milliseconds(20))
        probe.window.orderBack(nil)
        let replacement = probe.fileURL.deletingLastPathComponent().appendingPathComponent("preview.xhtml")
        try await probe.controller.showFile(replacement)
        let replacementCount = probe.renderCount
        for _ in 0..<100 where probe.renderCount == replacementCount { try await Task.sleep(for: .milliseconds(20)) }
        let replacementTitle = try await view.callAsyncJavaScript("return document.title", arguments: [:], in: nil, contentWorld: .page) as? String ?? ""
        try await probe.controller.showFile(probe.fileURL)
        let restoreCount = probe.renderCount
        for _ in 0..<100 where probe.renderCount == restoreCount { try await Task.sleep(for: .milliseconds(20)) }
        // Closing clears any resume ticket. Reordering this same closed window
        // cannot let an old appearance callback restart a request.
        probe.window.close()
        let closedCount = probe.renderCount
        probe.window.orderBack(nil)
        try await Task.sleep(for: .milliseconds(100))
        let closeReply = try await view.callAsyncJavaScript("""
            return await window.webkit.messageHandlers.quicklookHTML.postMessage({action:'prepareHTML',requestID:window.__containerProbe.requestID,html:'closed must fail'});
            """, arguments: [:], in: nil, contentWorld: .page)
        return ["hidden": hidden ?? NSNull(), "resumed": resumed,
                "newRequestAfterReappear": resumed["requestID"] as? String != old["requestID"] as? String,
                "newTokenAfterReappear": resumed["token"] as? String != old["resourceToken"] as? String,
                "minimizeRevokedBridge": miniRejected, "deminiaturizeResumedWithFreshUsableRequest": miniResumed,
                "newFileWonScheduledResume": replacementTitle == "preview.xhtml · OrbisPeek",
                "closeRejectedBridge": (closeReply as? [String: Any])?["ok"] as? Bool == false,
                "closeDidNotAutoResume": probe.renderCount == closedCount,
                "resumeStateLimit": "Reload resets display mode and query; hardware/Finder visibility lifecycle remains separate"]
    }

    private static func keyEquivalents(probe: RenderProbe, pasteboard: NSPasteboard) async throws -> [String: Any] {
        let view = probe.controller.webView
        func event(_ key: String, flags: NSEvent.ModifierFlags = .command) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: probe.window.windowNumber,
                context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: ["a": UInt16(0), "c": 8, "f": 3][key.lowercased()]!)!
        }
        _ = try await view.callAsyncJavaScript("""
            window.__keyOriginal=window.quicklook.commands.executeNative;window.__nativeKeyCalls=[];
            window.quicklook.commands.executeNative=(...args)=>{window.__nativeKeyCalls.push(args[0]);return window.__keyOriginal(...args);};
            window.quicklook.getBodyView().focus();return true;
            """, arguments: [:], in: nil, contentWorld: .page)
        try await Task.sleep(for: .milliseconds(30))
        probe.window.makeFirstResponder(view)
        let selectedAllHandled = view.performKeyEquivalent(with: event("a"))
        try await Task.sleep(for: .milliseconds(60))
        let selected = try await view.callAsyncJavaScript("return {text:window.quicklook.getBodyView().selectedPlainText(),calls:window.__nativeKeyCalls}", arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
        let selectedText = selected["text"] as? String ?? ""
        _ = try await view.callAsyncJavaScript("window.__nativeKeyCalls=[];return true", arguments: [:], in: nil, contentWorld: .page)
        pasteboard.clearContents();pasteboard.setString("key copy unchanged", forType: .string)
        let copyHandled = view.performKeyEquivalent(with: event("c"))
        for _ in 0..<30 where pasteboard.string(forType: .string) != selectedText { try await Task.sleep(for: .milliseconds(15)) }
        let copyMatches = !selectedText.isEmpty && pasteboard.string(forType: .string) == selectedText
        let copyCalls = try await view.callAsyncJavaScript("return window.__nativeKeyCalls", arguments: [:], in: nil, contentWorld: .page)
        _ = try await view.callAsyncJavaScript("window.__nativeKeyCalls=[];return true", arguments: [:], in: nil, contentWorld: .page)
        let findHandled = view.performKeyEquivalent(with: event("f"))
        try await Task.sleep(for: .milliseconds(60))
        let find = try await view.callAsyncJavaScript("return {calls:window.__nativeKeyCalls,open:!!document.querySelector('#search-bar'),focused:document.activeElement.id==='probe-editor'}", arguments: [:], in: nil, contentWorld: .page)
        _ = try await view.callAsyncJavaScript("window.quicklook.getBodyView().focus();window.__nativeKeyCalls=[];return true", arguments: [:], in: nil, contentWorld: .page)
        try await Task.sleep(for: .milliseconds(30))
        let capsHandled = view.performKeyEquivalent(with: event("F", flags: [.command, .capsLock]))
        try await Task.sleep(for: .milliseconds(60))
        let caps = try await view.callAsyncJavaScript("return {calls:window.__nativeKeyCalls,open:!!document.querySelector('#search-bar')}", arguments: [:], in: nil, contentWorld: .page)
        var unsupported: [[String: Any]] = []
        for (name, flags) in [("shift", NSEvent.ModifierFlags([.command, .shift])), ("option", [.command, .option]), ("control", [.command, .control]), ("function", [.command, .function])] {
            _ = try await view.callAsyncJavaScript("window.quicklook.getBodyView().focus();window.__nativeKeyCalls=[];return true", arguments: [:], in: nil, contentWorld: .page)
            try await Task.sleep(for: .milliseconds(20))
            let handled = view.performKeyEquivalent(with: event("f", flags: flags))
            try await Task.sleep(for: .milliseconds(30))
            let calls = try await view.callAsyncJavaScript("return window.__nativeKeyCalls", arguments: [:], in: nil, contentWorld: .page)
            unsupported.append(["modifier": name, "handled": handled, "calls": calls ?? NSNull()])
        }
        _ = try await view.callAsyncJavaScript("const q=document.getElementById('probe-editor')||Object.assign(document.body.appendChild(document.createElement('input')),{id:'probe-editor'});q.value='key query editing';q.focus();q.setSelectionRange(0,0);window.__nativeKeyCalls=[];return true", arguments: [:], in: nil, contentWorld: .page)
        try await Task.sleep(for: .milliseconds(30))
        let querySelectHandled = view.performKeyEquivalent(with: event("a"))
        try await Task.sleep(for: .milliseconds(40))
        let directQuerySelect = try await view.callAsyncJavaScript("const q=document.getElementById('probe-editor')||Object.assign(document.body.appendChild(document.createElement('input')),{id:'probe-editor'});return {start:q.selectionStart,end:q.selectionEnd,length:q.value.length}", arguments: [:], in: nil, contentWorld: .page)
        // The offscreen WebKit key-equivalent implementation may report handled
        // without editing. Check standard action fallback separately and report
        // both observations, without claiming a physical event pipeline.
        NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: view, from: nil)
        try await Task.sleep(for: .milliseconds(40))
        let querySelect = try await view.callAsyncJavaScript("const q=document.getElementById('probe-editor')||Object.assign(document.body.appendChild(document.createElement('input')),{id:'probe-editor'});return {start:q.selectionStart,end:q.selectionEnd,length:q.value.length}", arguments: [:], in: nil, contentWorld: .page)
        pasteboard.clearContents();pasteboard.setString("query key unchanged", forType: .string)
        let queryCopyHandled = view.performKeyEquivalent(with: event("c"))
        NSApp.sendAction(#selector(NSText.copy(_:)), to: view, from: nil)
        for _ in 0..<30 where pasteboard.string(forType: .string) != "key query editing" { try await Task.sleep(for: .milliseconds(15)) }
        let queryCopied = pasteboard.string(forType: .string) == "key query editing"
        let queryCalls = try await view.callAsyncJavaScript("return window.__nativeKeyCalls", arguments: [:], in: nil, contentWorld: .page)
        let queryInheritedTarget = NSApp.target(forAction: #selector(NSText.copy(_:)), to: nil, from: nil) as AnyObject? === view
        let client = view.inputContext?.client
        client?.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(30))
        let marked = client?.hasMarkedText() == true
        _ = try await view.callAsyncJavaScript("document.getElementById('probe-editor').dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true}));window.__nativeKeyCalls=[];return true", arguments: [:], in: nil, contentWorld: .page)
        let markedHandled = view.performKeyEquivalent(with: event("f"))
        try await Task.sleep(for: .milliseconds(30))
        let markedCalls = try await view.callAsyncJavaScript("return window.__nativeKeyCalls", arguments: [:], in: nil, contentWorld: .page)
        client?.unmarkText()
        _ = try await view.callAsyncJavaScript("document.getElementById('probe-editor').dispatchEvent(new CompositionEvent('compositionend',{bubbles:true}));window.quicklook.commands.executeNative=window.__keyOriginal;return true", arguments: [:], in: nil, contentWorld: .page)
        return ["bodySelectAll": ["handled": selectedAllHandled, "calls": selected["calls"] ?? NSNull(), "hasSelection": !selectedText.isEmpty],
                "bodyCopy": ["handled": copyHandled, "calls": copyCalls ?? NSNull(), "copiedCurrentSelection": copyMatches],
                "bodyFind": ["handled": findHandled, "effect": find ?? NSNull()],
                "capsLockFind": ["handled": capsHandled, "effect": caps ?? NSNull()], "unsupportedModifiers": unsupported,
                "query": ["selectHandled": querySelectHandled, "copyHandled": queryCopyHandled, "directSelectionObservation": directQuerySelect ?? NSNull(), "standardActionSelection": querySelect ?? NSNull(), "copiedNativeEditor": queryCopied, "inheritedCopyTarget": queryInheritedTarget, "calls": queryCalls ?? NSNull()],
                "markedText": ["nativeMarkedStateEstablished": marked, "compositionHintTested": true, "handled": markedHandled, "calls": markedCalls ?? NSNull(), "limit": marked ? "Public native marked-text state established; no physical IME claim" : "Offscreen inputContext did not establish native marked text; composition hint guard tested separately"],
                "scope": "Direct public NSEvent performKeyEquivalent calls prove adapter routing only. WebKit query key-equivalents can report handled without editing offscreen; separate standard native actions prove inherited editor fallback. No physical event delivery claim."]
    }

    private static func commands(probe: RenderProbe) async throws -> [String: Any] {
        let view = probe.controller.webView
        let pasteboard = NSPasteboard.general
        // Preserve every representation of every existing item in memory only.
        let saved = pasteboard.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
        var didRestore = false
        func restore() {
            pasteboard.clearContents()
            let restored = saved.map { representations in
                let item = NSPasteboardItem()
                for (type, data) in representations { item.setData(data, forType: type) }
                return item
            }
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
            didRestore = true
        }
        defer { if !didRestore { restore() } }
        _ = try await view.callAsyncJavaScript("""
            window.quicklook.getBodyView().focus();return true;
            """, arguments: [:], in: nil, contentWorld: .page)
        try await Task.sleep(for: .milliseconds(50))
        probe.window.makeFirstResponder(view)
        NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: view, from: nil)
        try await Task.sleep(for: .milliseconds(100))
        let selected = try await view.callAsyncJavaScript("return window.quicklook.getBodyView().selectedPlainText()", arguments: [:], in: nil, contentWorld: .page) as? String ?? ""
        let menu = NSMenu(title: "Synthetic standard commands")
        let item = menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        item.target = nil
        menu.update()
        let bodyTarget = NSApp.target(forAction: #selector(NSText.copy(_:)), to: nil, from: item)
        pasteboard.clearContents(); pasteboard.setString("synthetic unchanged sentinel", forType: .string)
        menu.performActionForItem(at: 0)
        for _ in 0..<30 where pasteboard.string(forType: .string) != selected { try await Task.sleep(for: .milliseconds(20)) }
        let bodyCopied = !selected.isEmpty && pasteboard.string(forType: .string) == selected
        // Deliberately invoke immediately after JS focus. If the cached body
        // hint races, the trusted DOM reply must fall back to inherited WK Copy.
        _ = try await view.callAsyncJavaScript("""
            const q=document.getElementById('probe-editor')||Object.assign(document.body.appendChild(document.createElement('input')),{id:'probe-editor'});q.value='query editing sentinel';q.focus();q.setSelectionRange(6,13);return true;
            """, arguments: [:], in: nil, contentWorld: .page)
        probe.controller.performPreviewCommand("copy")
        for _ in 0..<30 where pasteboard.string(forType: .string) != "editing" { try await Task.sleep(for: .milliseconds(20)) }
        let immediateEditorCopy = pasteboard.string(forType: .string) == "editing"
        let editorTarget = NSApp.target(forAction: #selector(NSText.copy(_:)), to: nil, from: item)
        NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: view, from: nil)
        try await Task.sleep(for: .milliseconds(50))
        let editorSelection = try await view.callAsyncJavaScript("const q=document.getElementById('probe-editor')||Object.assign(document.body.appendChild(document.createElement('input')),{id:'probe-editor'});return {start:q.selectionStart,end:q.selectionEnd,length:q.value.length}", arguments: [:], in: nil, contentWorld: .page)
        pasteboard.clearContents(); pasteboard.setString("synthetic paste", forType: .string)
        NSApp.sendAction(#selector(NSText.paste(_:)), to: view, from: nil)
        try await Task.sleep(for: .milliseconds(100))
        let pasted = try await view.callAsyncJavaScript("return document.getElementById('probe-editor').value", arguments: [:], in: nil, contentWorld: .page) as? String
        let findUnavailable = !view.responds(to: #selector(NSResponder.performTextFinderAction(_:)))
        view.performTextFinderAction(nil)
        let noFindUI = try await view.callAsyncJavaScript("return !document.querySelector('#find-button,#search-bar,#search-input')", arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        let keys = try await keyEquivalents(probe: probe, pasteboard: pasteboard)
        restore()
        let after = pasteboard.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
        let restoredExactly = saved.count == after.count && zip(saved, after).allSatisfy { left, right in
            left.count == right.count && zip(left, right).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }
        return ["clipboardAllItemsAndTypesRestoredExactly": restoredExactly,
                "clipboardScope": "All item/type Data representations saved in memory, restored, compared without printing user contents",
                "keyEquivalents": keys,
                "bodyMenuEnabled": item.isEnabled, "bodyCopyUsesSupplementalTarget": bodyTarget != nil && bodyTarget as AnyObject? !== view,
                "bodyCopyMatchesCurrentSelection": bodyCopied, "bodySelection": selected,
                "queryCopyUsesInheritedWebKitTarget": editorTarget as AnyObject? === view,
                "immediateQueryCopyUsesNativeEditor": immediateEditorCopy, "querySelectAll": editorSelection ?? NSNull(),
                "queryPasteUsesNativeEditor": pasted == "synthetic paste", "nativeFindUnavailable": findUnavailable, "noFindUI": noFindUI]
    }
}
