#if os(iOS)
  import Foundation

  /// Supplemental isolated-world guard. It never constructs an input event, changes isTrusted,
  /// executes page-provided code, or promises containment of arbitrary page JavaScript effects.
  /// UIKit is noninteractive except during a short, person-approved single-target handoff.
  enum MobileBrowserReviewInput {
    static let library = #"""
      (() => {
        'use strict';
        if (globalThis.__memoshiMobileGuard) return;
        let permit = null;
        function cancel(event) {
          event.preventDefault(); event.stopImmediatePropagation();
        }
        function valid() {
          if (!permit || performance.now() >= permit.until || !permit.node.isConnected) return false;
          const api = globalThis.__memoshiAutomation;
          if (api.documentId().docId !== permit.document) return false;
          const now = api.actionInfo(permit.input);
          return !now.error && now.docId === permit.document && now.origin === permit.origin
            && now.destination === permit.destination && now.method === permit.method
            && now.label === permit.label && now.payment === false && now.file === permit.file;
        }
        function intercept(event) {
          if (!event.isTrusted) return;
          if (!valid()) { cancel(event); return; }
          const node = event.target;
          const target = permit.node;
          if (event.type === 'submit') {
            // Form navigation additionally needs the native delegate's exact one-use permit.
            if (!permit.submit || event.target !== target.form) cancel(event);
            return;
          }
          const onTarget = node === target || (node instanceof Node && target.contains(node))
            || (node instanceof Element && node.closest('label')?.control === target);
          if (!onTarget || event.type === 'contextmenu' || event.type === 'dragstart'
            || (event.type === 'keydown' && (['Enter','Tab'].includes(event.key) || event.metaKey || event.ctrlKey))) {
            cancel(event); return;
          }
          if (event.type === 'click' && !permit.editable && !permit.file && !permit.selectable) {
            // One native click, not an open-ended takeover. Leave submit's synchronous default
            // action alive until the end of this dispatch; delegates independently recheck it.
            const used = permit;
            queueMicrotask(() => { if (permit === used) permit = null; });
          }
        }
        for (const type of ['pointerdown','pointerup','mousedown','mouseup','click','keydown','keyup',
          'beforeinput','input','change','touchstart','touchend','touchmove','contextmenu','dragstart','submit']) {
          addEventListener(type, intercept, {capture:true, passive:false});
        }
        const api = Object.freeze({
          arm(input) {
            const automation = globalThis.__memoshiAutomation;
            const info = automation.actionInfo(input);
            if (info.error || info.docId !== input.expectedDocument || info.origin !== input.origin
              || info.label !== input.label || info.destination !== input.destination
              || info.method !== input.method || info.payment) return {error:'stale_document'};
            const geometry = automation.target(input);
            if (geometry.error || geometry.sensitive) return {error:'unsupported_target'};
            let node = document.elementFromPoint(geometry.x, geometry.y);
            node = node?.closest('input,textarea,select,button,a,summary,label,[contenteditable],[role]');
            if (node instanceof HTMLLabelElement && node.control) node = node.control;
            if (!node || (geometry.picker && !geometry.file && !(node instanceof HTMLSelectElement))) {
              return {error:'unsupported_target'};
            }
            permit = {node, input, document:info.docId, origin:info.origin, label:info.label,
              destination:info.destination, method:info.method, file:info.file,
              editable:geometry.editable, selectable:node instanceof HTMLSelectElement,
              submit:geometry.submit, until:performance.now()+30000};
            return {ok:true};
          },
          frame(input) {
            if (globalThis.__memoshiAutomation.documentId().docId !== input.expectedDocument) {
              return {error:'stale_document'};
            }
            const node = Array.from(document.querySelectorAll('iframe,frame'))
              .find(node => node.isConnected && node.contentWindow === input.child);
            if (!node) return {error:'detached_frame'};
            if (input.scroll) node.scrollIntoView({block:'center',inline:'center',behavior:'instant'});
            return {ok:true};
          },
          disarm() { permit = null; document.activeElement?.blur(); return {ok:true}; }
        });
        Object.defineProperty(globalThis,'__memoshiMobileGuard',{value:api,writable:false,configurable:false});
      })();
      """#
  }
#endif
