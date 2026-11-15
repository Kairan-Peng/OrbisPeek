import AppKit
import Foundation
import WebKit

func validLoopbackOrigin(_ text: String) -> Bool {
    guard let url = URLComponents(string: text) else { return false }
    return url.scheme == "http" && url.host == "127.0.0.1" && url.port != nil
        && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
        && url.path.isEmpty
}

/// Synthetic probe code only. Production never receives this policy or markup option.
@MainActor
enum HTMLContainerChecks {
    static func run(probe: RenderProbe, loopbackOrigin: String?) async throws -> [String: Any] {
        let view = probe.controller.webView
        let origin = loopbackOrigin ?? "http://127.0.0.1:9"
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="refresh" content="1;url=\(origin)/refresh">
        <link rel="stylesheet" href="\(origin)/stylesheet">
        <style>@import url('\(origin)/import');
        @font-face{font-family:ProbeRemote;src:url('\(origin)/font')}
        body{color:rgb(18,52,86);background-image:url('\(origin)/background');font-family:ProbeRemote,serif}
        #child-marker{font-size:31px}#file-basename{color:rgb(255,0,0)!important}</style>
        </head><body style="padding-left:13px"><h1 id="child-marker">Child HTML marker</h1>
        <p id="selectable">Alpha needle beta 你好</p><p style="height:1600px">Scroll marker</p>
        <p id="bottom-marker">Omega needle bottom</p><img id="remote-image" src="\(origin)/image" onerror="parent.__untrustedEventRan=true">
        <img id="stale-image" src="quicklook-resource://local/\(UUID().uuidString)/missing.png" onerror="parent.__untrustedEventRan=true">
        <video src="\(origin)/video" poster="\(origin)/poster"></video><audio src="\(origin)/audio"></audio>
        <iframe src="\(origin)/frame"></iframe><object data="\(origin)/object"></object>
        <a id="child-link" href="\(origin)/link">Test link</a>
        <form id="child-form" action="\(origin)/form" method="post"><input name="synthetic" value="fixture"></form>
        <script>window.__childScriptRan=true;parent.__untrustedScriptRan=true;</script></body></html>
        """
        let setup = try await view.callAsyncJavaScript("""
            const state=window.__containerProbe;
            if(!state?.requestID || !state.resourceToken) throw new Error('Default native render was not observed');
            const bridge=window.webkit.messageHandlers.quicklookHTML;
            const prepare=html=>bridge.postMessage({action:'prepareHTML',requestID:state.requestID,html});
            const stale=await bridge.postMessage({action:'prepareHTML',requestID:staleRequest,html:'stale'});
            const first=await prepare('<p>superseded</p>');
            const oversized=await prepare('x'.repeat(2*1024*1024+1));
            const response=await prepare(html);
            if(!response.ok) throw new Error(JSON.stringify(response));
            window.__containerProbeChildURL=response.url;
            window.__untrustedScriptRan=false;window.__untrustedEventRan=false;
            const parentColor=getComputedStyle(document.getElementById('file-basename')).color;
            const frame=document.createElement('iframe');frame.id='container-probe-frame';
            frame.setAttribute('sandbox','allow-same-origin');frame.width='760';frame.height='300';
            document.getElementById('content').replaceChildren(frame);frame.src=response.url;
            for(let i=0;i<100;i++) {
              if(frame.contentDocument?.URL===response.url && frame.contentDocument.getElementById('bottom-marker')) break;
              await new Promise(resolve=>setTimeout(resolve,25));
            }
            const child=frame.contentDocument;
            if(child?.URL!==response.url || !child.getElementById('selectable')) throw new Error('Prepared child did not load');
            const selection=frame.contentWindow.getSelection(),range=child.createRange();
            range.selectNodeContents(child.getElementById('selectable'));selection.removeAllRanges();selection.addRange(range);
            const walker=child.createTreeWalker(child.body,NodeFilter.SHOW_TEXT);
            let node;const matches=[];while((node=walker.nextNode())) if(!['SCRIPT','STYLE'].includes(node.parentElement?.tagName)&&node.data.includes('needle')) matches.push(node.data);
            frame.contentWindow.scrollTo(0,100);
            const counts={click:0,keydown:0,copy:0};const prevented={};
            for(const name of Object.keys(counts)) {
              child.addEventListener(name,event=>{counts[name]++;event.preventDefault();});
              const event=name==='keydown'?new frame.contentWindow.KeyboardEvent(name,{key:'f',metaKey:true,bubbles:true,cancelable:true}):new frame.contentWindow.Event(name,{bubbles:true,cancelable:true});
              child.dispatchEvent(event);prevented[name]=event.defaultPrevented;
            }
            let positiveCount=0;const positive=event=>{positiveCount++;event.preventDefault();};
            document.addEventListener('container-positive',positive);
            const event=new Event('container-positive',{cancelable:true});document.dispatchEvent(event);document.removeEventListener('container-positive',positive);
            child.getElementById('stale-image').dispatchEvent(new frame.contentWindow.Event('error'));
            let childBridge;
            try{childBridge=await frame.contentWindow.webkit.messageHandlers.quicklookHTML.postMessage({action:'prepareHTML',requestID:state.requestID,html:'child must fail'});}catch(error){childBridge={error:String(error)};}
            try{child.getElementById('child-form').requestSubmit();}catch{}
            return {requestID:state.requestID,resourceToken:state.resourceToken,childURL:response.url,previousURL:first.url,
              staleRequestRejected:stale.ok===false,oversizeRejected:oversized.ok===false,handshake:response,
              shellURL:location.href,shellOrigin:location.origin,childOrigin:frame.contentWindow.location.origin,
              sandbox:frame.getAttribute('sandbox'),contentDocument:!!child,selection:selection.toString(),range:range.toString(),treeWalkerMatches:matches,scrollY:frame.contentWindow.scrollY,
              childColor:frame.contentWindow.getComputedStyle(child.body).color,childInlinePadding:frame.contentWindow.getComputedStyle(child.body).paddingLeft,
              childHeadingSize:frame.contentWindow.getComputedStyle(child.getElementById('child-marker')).fontSize,
              parentColorBefore:parentColor,parentColorAfter:getComputedStyle(document.getElementById('file-basename')).color,
              pageChildCallbacks:{counts,prevented},mainEventPositive:{count:positiveCount,prevented:event.defaultPrevented},childBridge};
            """, arguments: ["html": html, "staleRequest": UUID().uuidString], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
        var result = setup
        for _ in 0..<10 where probe.childFrame == nil { try await Task.sleep(for: .milliseconds(50)) }
        if let childFrame = probe.childFrame {
            let script = """
                const counts={click:0,keydown:0,copy:0},prevented={};
                for(const name of Object.keys(counts)){
                  document.addEventListener(name,event=>{counts[name]++;event.preventDefault();});
                  const event=name==='keydown'?new KeyboardEvent(name,{key:'f',metaKey:true,bubbles:true,cancelable:true}):new Event(name,{bubbles:true,cancelable:true});
                  document.dispatchEvent(event);prevented[name]=event.defaultPrevented;
                }
                return {url:location.href,counts,prevented};
                """
            result["defaultClientChildCallbacks"] = try await view.callAsyncJavaScript(script, arguments: [:], in: childFrame, contentWorld: .defaultClient)
            do {
                result["directChildPageExecution"] = try await view.callAsyncJavaScript(script, arguments: [:], in: childFrame, contentWorld: .page)
            } catch {
                result["directChildPageExecutionError"] = ["domain": (error as NSError).domain, "code": (error as NSError).code, "description": error.localizedDescription]
            }
        } else { result["childFrameError"] = "No trusted native frame observation" }
        // An explicit native command enters the trusted main frame. No child listener is used.
        let url = setup["childURL"] as? String ?? ""
        var commands: [String: Any] = [:]
        for command in ["readSelection", "selectAll", "markAndScroll", "focusParentEditor"] {
            commands[command] = try await nativeCommand(command, childURL: url, view: view)
        }
        result["nativeMainCommands"] = commands
        try await Task.sleep(for: .milliseconds(1300))
        result["finalDocument"] = try await view.callAsyncJavaScript("""
            const frame=document.getElementById('container-probe-frame'),child=frame.contentDocument;
            return {childURL:child?.URL,childScriptRan:!!frame.contentWindow.__childScriptRan,
              parentUntrustedScriptRan:window.__untrustedScriptRan,parentUntrustedEventRan:window.__untrustedEventRan,
              remoteImage:{complete:child.getElementById('remote-image').complete,naturalWidth:child.getElementById('remote-image').naturalWidth},
              staleImage:{complete:child.getElementById('stale-image').complete,naturalWidth:child.getElementById('stale-image').naturalWidth}};
            """, arguments: [:], in: nil, contentWorld: .page)
        result["resourceEvidence"] = probe.controller.resourceDiagnostics()
        result["staleDocumentNavigation"] = try await view.callAsyncJavaScript("""
            const frame=document.getElementById('container-probe-frame');frame.src=previousURL;
            await new Promise(resolve=>setTimeout(resolve,200));
            return {attemptedURL:previousURL,actualURL:frame.contentDocument?.URL??null,staleContentVisible:frame.contentDocument?.body?.textContent==='superseded'};
            """, arguments: ["previousURL": setup["previousURL"] ?? ""], in: nil, contentWorld: .page)
        // Keep the WKWebView alive after whole-window dismissal and test the real reply gate.
        probe.window.close()
        result["afterWindowClose"] = try await view.callAsyncJavaScript("""
            return await window.webkit.messageHandlers.quicklookHTML.postMessage({action:'prepareHTML',requestID:window.__containerProbe.requestID,html:'closed'});
            """, arguments: [:], in: nil, contentWorld: .page)
        result["loopbackOrigin"] = loopbackOrigin ?? NSNull()
        result["limitations"] = [
            "Synthetic fixture in an offscreen standalone WKWebView; production file classification and sanitization belong to later work.",
            "Child click, keydown and copy callbacks are observed suppressed by the no-script sandbox in tested content worlds.",
            "Native explicit commands demonstrate DOM operations only; no physical keyboard, responder integration, IME, clipboard or Finder acceptance is proved.",
        ]
        return result
    }

    private static func nativeCommand(_ command: String, childURL: String, view: WKWebView) async throws -> Any? {
        try await view.callAsyncJavaScript("""
            const frame=document.getElementById('container-probe-frame'),child=frame.contentDocument;
            if(child?.URL!==expectedURL) throw new Error('Inactive document capability');
            const selection=frame.contentWindow.getSelection();
            if(command==='readSelection')return {text:selection.toString()};
            if(command==='selectAll'){
              const range=child.createRange();range.selectNodeContents(child.body);selection.removeAllRanges();selection.addRange(range);
              return {text:selection.toString(),includesParent:selection.toString().includes(document.getElementById('file-basename').textContent)};
            }
            if(command==='markAndScroll'){
              const walker=child.createTreeWalker(child.body,NodeFilter.SHOW_TEXT,{acceptNode:node=>node.data==='Omega needle bottom'?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT});
              const node=walker.nextNode(),range=child.createRange(),mark=child.createElement('mark');
              range.selectNodeContents(node);range.surroundContents(mark);mark.scrollIntoView({block:'center'});
              return {marks:child.querySelectorAll('mark').length,text:mark.textContent,scrollY:frame.contentWindow.scrollY};
            }
            if(command==='focusParentEditor'){
              const query=document.body.appendChild(document.createElement('input'));query.id='probe-editor';query.value='needle';query.focus();
              return {activeElement:document.activeElement?.id,value:query.value,documentHasFocus:document.hasFocus()};
            }
            throw new Error('Unsupported synthetic command');
            """, arguments: ["command": command, "expectedURL": childURL], in: nil, contentWorld: .page)
    }
}

/// Separate probe-only profile. Its sole network permission is one explicit loopback image origin.
@MainActor
final class LoopbackImageControl: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
    private let origin: String
    private let output: URL?
    private var view: WKWebView!
    private var finished = false
    private let parseRenderer: Data?
    private var customResourceRequests = 0
    private var positiveCustomResourceRequests = 0
    private let shell = "quicklook-app://bundle/index.html"
    private let child = "quicklook-app://bundle/document/00000000-0000-0000-0000-000000000001/content.html"

    init(origin: String, output: URL?, parseRenderer: Data? = nil) {
        self.parseRenderer = parseRenderer
        self.origin = origin
        self.output = output
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(self, forURLScheme: "quicklook-app")
        if parseRenderer != nil { configuration.setURLSchemeHandler(self, forURLScheme: "quicklook-resource") }
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        view.navigationDelegate = self
        view.load(URLRequest(url: URL(string: shell)!))
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.complete(["error": "Positive control timed out"], status: 1) }
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        if url.scheme == "quicklook-resource" {
            if url.path.hasSuffix("/parse-positive.png") {
                positiveCustomResourceRequests += 1
                let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
                task.didReceive(URLResponse(url: url, mimeType: "image/png", expectedContentLength: pixel.count, textEncodingName: nil)); task.didReceive(pixel); task.didFinish()
            } else { customResourceRequests += 1; task.didFailWithError(URLError(.resourceUnavailable)) }
            return
        }
        if url.absoluteString == "quicklook-app://bundle/renderer.js", let parseRenderer {
            task.didReceive(URLResponse(url: url, mimeType: "application/javascript", expectedContentLength: parseRenderer.count, textEncodingName: "utf-8"))
            task.didReceive(parseRenderer); task.didFinish(); return
        }
        let html: String
        let policy: String
        if url.absoluteString == shell, parseRenderer != nil {
            html = """
                <!doctype html><html><body><main id="content"></main><button id="source-toggle"><i class="source-icon"></i><i class="preview-icon"></i></button>
                <button id="wrap-toggle"></button>
                <script src="quicklook-app://bundle/renderer.js"></script></body></html>
                """
            policy = "default-src 'none'; script-src 'unsafe-inline' quicklook-app://bundle/; style-src 'none'; img-src \(origin) quicklook-resource:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
        } else if url.absoluteString == shell {
            html = "<!doctype html><iframe id='control' sandbox='allow-same-origin' src='\(child)'></iframe>"
            policy = "default-src 'none'; script-src 'none'; frame-src quicklook-app://bundle/document/; style-src 'none'; img-src 'none'; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
        } else if url.absoluteString == child {
            html = "<!doctype html><img id='positive-image' src='\(origin)/image'>"
            policy = "default-src 'none'; script-src 'none'; style-src 'none'; img-src \(origin); connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
        } else { task.didFailWithError(URLError(.resourceUnavailable)); return }
        let data = Data(html.utf8)
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": policy, "Cache-Control": "no-store"])!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                if parseRenderer != nil {
                    let result = try await view.callAsyncJavaScript("""
                        const nonce=crypto.randomUUID();
                        // Deliberately disconnected but LIVE-document owned: src alone fetches.
                        const positive=document.createElement('img');window.__parsePositive=positive;
                        positive.src=origin+'/parse-positive.png?'+nonce;
                        for(let i=0;i<100&&!positive.complete;i++)await new Promise(resolve=>setTimeout(resolve,30));
                        if(positive.naturalWidth!==1)throw new Error('Disconnected active-owned positive did not decode');
                        const token='D74B9B4A-7C26-4A98-8A67-30E256E963DE';
                        const customPositive=document.createElement('img');window.__customPositive=customPositive;
                        customPositive.src='quicklook-resource://local/'+token+'/parse-positive.png';
                        for(let i=0;i<100&&!customPositive.complete;i++)await new Promise(resolve=>setTimeout(resolve,30));
                        if(customPositive.naturalWidth!==1)throw new Error('Custom scheme active-owned positive did not decode');
                        const scriptControl=document.createElement('script');scriptControl.textContent='window.__activeParseControl=true';document.body.append(scriptControl);scriptControl.remove();
                        window.__inertParseRan=false;
                        const source='<!doctype html><html class="parse-root" lang="zh" dir="rtl" style="font-size:19px"><head><script>window.__inertParseRan=true</script></head><body><img src="'+origin+'/parse-inert.png?'+nonce+'" srcset="'+origin+'/parse-srcset.png?'+nonce+' 2x">'+
                          '<img src="quicklook-resource://local/'+token+'/forged.png"><img src="assets/local.png">'+
                          '<picture><source srcset="'+origin+'/parse-picture.png?'+nonce+'"><img src="'+origin+'/parse-nested.png?'+nonce+'"></picture></body></html>';
                        const result=window.quicklook.sanitizeHTML(source,token);
                        const reparsed=document.createElement('template');reparsed.innerHTML=result.html;
                        await new Promise(resolve=>setTimeout(resolve,500));
                        return {activeOwnedDisconnectedPositive:{naturalWidth:positive.naturalWidth,complete:positive.complete,connected:positive.isConnected,src:positive.src},
                          activeOwnedCustomPositive:{naturalWidth:customPositive.naturalWidth,connected:customPositive.isConnected},
                          actualProductionSanitizer:true,inertSerialization:result.html,localImages:result.localImages,blockedImages:result.blockedImages,
                          parserDocumentHasNoView:result.parserDocumentHasNoView,reconstructionDocumentHasNoView:result.reconstructionDocumentHasNoView,
                          activeScriptControlRan:window.__activeParseControl===true,inactiveParseScriptRan:window.__inertParseRan,
                          rootAttributeSerialized:result.html.includes('class="parse-root"'),
                          reparsedImages:[...reparsed.content.querySelectorAll('img')].map(img=>img.getAttribute('src')),
                          policyAllowsLoopbackImages:true,policyAllowsCustomImages:true,claimScope:'Image src/srcset parse and reconstruction only; no CSS/font positive control'};
                        """, arguments: ["origin": origin], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
                    var evidence = result
                    evidence["customResourceRequests"] = customResourceRequests
                    evidence["positiveCustomResourceRequests"] = positiveCustomResourceRequests
                    complete(evidence, status: 0)
                    return
                }
                let result = try await view.callAsyncJavaScript("""
                    for(let i=0;i<100;i++){
                      const frame=document.getElementById('control'),image=frame.contentDocument?.getElementById('positive-image');
                      if(image?.complete&&image.naturalWidth>0)return {naturalWidth:image.naturalWidth,complete:image.complete,src:image.src,sandbox:frame.getAttribute('sandbox'),actualWebKitImage:true};
                      await new Promise(resolve=>setTimeout(resolve,50));
                    }
                    throw new Error('WebKit loopback image did not decode');
                    """, arguments: [:], in: nil, contentWorld: .page)
                complete(["webKitPositive": result ?? NSNull(), "origin": origin], status: 0)
            } catch { complete(["error": error.localizedDescription, "details": String(describing: (error as NSError).userInfo)], status: 1) }
        }
    }

    private func complete(_ result: [String: Any], status: Int32) {
        guard !finished else { return }
        finished = true
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            if let output { try data.write(to: output) }
            FileHandle.standardOutput.write(data)
            print("")
        } catch { fputs("\(error)\n", stderr) }
        exit(status)
    }
}
