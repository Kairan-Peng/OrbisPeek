import AppKit
import Foundation
import WebKit

/// Actual production WebKit failures and the trusted parent affordance. The
/// probe intercepts only its own open action before any button is clicked;
/// it never opens an application or accesses the system pasteboard.
@MainActor
enum ImageAccessPromptChecks {
    static func run(probe: RenderProbe) async throws -> [String: Any] {
        let result = try await probe.controller.webView.callAsyncJavaScript("""
            const q=window.quicklook,context=window.__containerProbe;
            if(!context?.requestID||q.getBodyView()?.kind!=='rendered')throw new Error('Use the missing-image Markdown fixture');
            const handlers=window.webkit.messageHandlers,nativeHandler=handlers.quicklookState;
            const original=nativeHandler.postMessage;
            const captured=[],forwarded=[];
            const capture=function(message){
              if(message?.action==='openImageAccess'){
                captured.push(JSON.parse(JSON.stringify(message)));return;
              }
              const result=original.call(nativeHandler,message);
              if(message?.action==='commandState')forwarded.push(JSON.parse(JSON.stringify(message)));
              return result;
            };
            // WebKit host objects need not permit assignment on every version.
            // Never click unless a fresh lookup proves the capture is installed.
            try{nativeHandler.postMessage=capture;}catch{}
            if(handlers.quicklookState.postMessage!==capture){
              try{Object.defineProperty(handlers,'quicklookState',{value:{postMessage:capture},configurable:true});}catch{}
            }
            const interception=()=>window.webkit.messageHandlers.quicklookState.postMessage===capture;
            if(!interception())throw new Error('Cannot safely intercept the native host-open action');
            handlers.quicklookState.postMessage({action:'openImageAccess',requestID:'probe-interception-sentinel',viewGeneration:-1});
            if(captured.length!==1)throw new Error('Host-open capture positive control failed');
            captured.length=0;
            const checks={bridgeInterceptionVerifiedBeforeAnyClick:true};
            const generation=()=>{q.commands.publishState();return forwarded.at(-1)?.viewGeneration;};
            const click=button=>{
              if(!interception())throw new Error('Capture was replaced; refusing button click');
              if(!button)throw new Error('Expected the current parent access button');button.click();
            };
            async function failedImages(){
              for(const image of q.getBodyView().root.querySelectorAll('img'))image.scrollIntoView({block:'center'});
              const deadline=Date.now()+1800;
              while(q.report().failedImages<2&&Date.now()<deadline)await new Promise(r=>setTimeout(r,20));
              window.scrollTo(0,0);
            }
            const noFind=()=>!document.querySelector('#find-button,#search-bar,#search-input,#copy-button');
            await failedImages();
            const firstGeneration=generation(),firstButton=document.getElementById('image-access-button');
            checks.realMarkdownFailuresHaveTwoPlaceholders=q.report().failedImages===2&&document.querySelectorAll('#content .blocked-image').length===2;
            checks.oneQuietParentNotice=document.querySelectorAll('.image-access-notice').length===1&&document.getElementById('notices').classList.contains('image-access-only');
            checks.noAutomaticHostOpen=captured.length===0;
            checks.liveRecheckRequiresCurrentRequestAndGeneration=q.canOpenImageAccess(context.requestID,firstGeneration)&&!q.canOpenImageAccess('stale-request',firstGeneration)&&!q.canOpenImageAccess(context.requestID,firstGeneration-1);
            q.getBodyView().selectAll();
            checks.markdownSelectionExcludesPermissionUI=q.getBodyView().selectedPlainText()==='正文 中文加粗 与 inline_code。';
            click(firstButton);
            checks.parentMessageUsesCurrentNativeRequest=captured.length===1&&captured[0].requestID===context.requestID&&captured[0].viewGeneration===firstGeneration&&Object.keys(captured[0]).sort().join(',')==='action,requestID,viewGeneration';
            document.getElementById('source-toggle').click();await q.whenIdle();
            q.getBodyView().selectAll();
            checks.markdownSourceRemovesActionAndPreservesFile=q.getBodyView().kind==='source'&&!document.getElementById('image-access-button')&&q.getBodyView().selectedPlainText()===context.payload.text&&!q.canOpenImageAccess(context.requestID,firstGeneration);
            click(firstButton);
            checks.staleMarkdownButtonCannotSend=captured.length===1;
            document.getElementById('source-toggle').click();await q.whenIdle();await failedImages();
            checks.markdownRenderReturnRestoresOneAction=document.querySelectorAll('#image-access-button').length===1;
            const html='<p>HTML 正文</p><img src="image-access-probe-missing-a-1210.png" alt="one"><img src="image-access-probe-missing-b-1210.png" alt="two">';
            await q.render({...context.payload,text:html,mode:'html',language:'html',fileName:'image-access.html'},context.requestID);
            const htmlGeneration=generation(),htmlButton=document.getElementById('image-access-button'),child=q.getBodyView().document;
            checks.htmlFailuresUseOnlyTrustedParentAction=q.report().failedImages===2&&document.querySelectorAll('#image-access-button').length===1&&!!htmlButton&&htmlButton.ownerDocument===document&&!child.querySelector('#image-access-button,button')&&child.querySelectorAll('[data-quicklook-owned="failed-image"]').length===2;
            q.getBodyView().selectAll();
            checks.htmlSelectedTextExcludesPermissionUI=q.getBodyView().selectedPlainText()==='HTML 正文';
            click(htmlButton);
            checks.htmlParentMessageUsesCurrentNativeGeneration=captured.length===2&&captured[1].requestID===context.requestID&&captured[1].viewGeneration===htmlGeneration;
            document.getElementById('source-toggle').click();await q.whenIdle();
            const htmlSource=!document.getElementById('image-access-button')&&!q.canOpenImageAccess(context.requestID,htmlGeneration);
            document.getElementById('source-toggle').click();await q.whenIdle();
            checks.htmlSourceReturnRestoresOneParentAction=htmlSource&&document.querySelectorAll('#image-access-button').length===1;
            const oldButton=document.getElementById('image-access-button');
            await q.render({...context.payload,text:'# New document'},'new-probe-request');
            click(oldButton);
            checks.newDocumentRevokesOldAction=captured.length===2&&!document.getElementById('image-access-button')&&!q.canOpenImageAccess(context.requestID,htmlGeneration);
            checks.findAndCopyControlsRemainAbsent=noFind()&&[...document.querySelectorAll('.actions button')].map(x=>x.id).join(',')==='source-toggle,wrap-toggle';
            checks.otherCommandStatesStillUseNativeBridge=forwarded.length>4;
            await q.render(context.payload,context.requestID);await failedImages();
            const failureGeneration=generation(),failedOpenButton=document.getElementById('image-access-button');
            const accepted=q.imageAccessOpenFailed(context.requestID,failureGeneration);
            click(failedOpenButton);
            checks.openFailureShowsManualPathAndRemovesAction=accepted&&!document.getElementById('image-access-button')&&!q.canOpenImageAccess(context.requestID,failureGeneration)&&document.getElementById('notices').innerText.includes('“应用程序”中打开 OrbisPeek')&&captured.length===2;
            await q.render({...context.payload,text:'# New completion target'},'new-completion-request');
            checks.oldFailureCompletionCannotChangeNewDocument=q.imageAccessOpenFailed(context.requestID,failureGeneration)===false&&document.getElementById('notices').hidden&&q.getBodyView().root.innerText.trim()==='New completion target';
            await q.render(context.payload,context.requestID);await failedImages();
            const finalGeneration=generation();
            q.imageAccessOpenFailed(context.requestID,finalGeneration);
            const range=document.createRange();range.selectNodeContents(document.body);
            document.getSelection().removeAllRanges();document.getSelection().addRange(range);
            const projection=q.commands.executeNative('copy',context.requestID,finalGeneration);
            checks.manualInstructionsStayOutOfPlainTextProjection=projection.handled===true&&projection.text==='正文 中文加粗 与 inline_code。'&&captured.length===2;
            q.getBodyView().document.getSelection().removeAllRanges();
            return {checks,capturedMessages:captured,forwardedNativeStateCount:forwarded.length,notice:document.getElementById('notices').innerText};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
        var checks = result["checks"] as? [String: Bool] ?? [:]
        let resources = probe.controller.resourceDiagnostics()
        checks["missingImageFailuresRecordedByNativeResourceHandler"] = resources.filter {
            $0["status"] == "blocked" && $0["path"]?.hasPrefix("image-access-probe-missing-") == true
        }.count >= 2
        guard checks.count == 21, checks.values.allSatisfy({ $0 }) else {
            throw NSError(domain: "ImageAccessPromptProbe", code: 1, userInfo: [NSLocalizedDescriptionKey:
                checks.filter { !$0.value }.keys.sorted().joined(separator: ", ") + " checks: \(checks.count); result: \(result); resources: \(resources)"])
        }
        return ["passed": true, "checks": checks, "capturedMessages": result["capturedMessages"] ?? [],
                "forwardedNativeStateCount": result["forwardedNativeStateCount"] ?? 0,
                "notice": result["notice"] ?? "",
                "scope": "Offscreen production WebKit and native resource failures, including current/stale public host-open failure feedback and selected copy text projection. Only the explicit openImageAccess bridge action is intercepted after a verified positive control; other command states use the native handler. No app launch or system pasteboard access; actual Finder handoff/completion is separate."]
    }
}
