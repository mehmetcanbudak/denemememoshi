import Foundation
import WebKit

/// Sources for the review lab's isolated automation world and its offline lab page.
///
/// The library is injected at document start into every frame, inside its own content world, so
/// page scripts can neither see nor replace it. Native code calls it only through
/// `callAsyncJavaScript` with data arguments; no script is ever assembled from strings.
public enum BrowserAutomationScript {
  /// Stable review-lab label; callers must use `world` itself to select WebKit execution.
  public static let worldName = "memoshi.automation"
  /// Native script-message handler name used by isolated-world subframe registration callbacks.
  public static let frameMessageName = "memoshiFrame"
  /// The offline fixture is never counted as a real site.
  public static let labPageHost = "lab.memoshi.invalid"
  /// Base URL for the bundled offline HTML fixture, not a fetched site or qualification sample.
  public static let labPageURL = URL(string: "https://lab.memoshi.invalid/")

  /// Shared isolated realm with JavaScript-handle creation enabled for native frame targeting.
  @MainActor public static let world: WKContentWorld = {
    let configuration = WKContentWorld.Configuration()
    configuration.jsHandleCreationEnabled = true
    return WKContentWorld(configuration: configuration)
  }()

  /// The single call body. `command` selects a frozen library function; `input` is plain data.
  public static let dispatchBody = #"""
    const api = globalThis.__memoshiAutomation;
    if (!api) { return JSON.stringify({ error: "automation_unavailable" }); }
    if (!Object.prototype.hasOwnProperty.call(api, command) || typeof api[command] !== "function") {
      return JSON.stringify({ error: "unknown_command" });
    }
    return JSON.stringify(api[command](input));
    """#

  /// The isolated-world library: bounded visible-element snapshots with refs, validated element
  /// targeting, DOM input, a passive input observer that records only event types and
  /// `isTrusted`, a timer probe and frame registration.
  public static let library = #"""
    (() => {
      "use strict";
      if (globalThis.__memoshiAutomation) { return; }

      const maxEvents = 200;
      const maxName = 120;
      const maxValue = 200;
      const maxOptions = 50;
      const maxElements = 500;
      const hiddenCharacters =
        /[\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180B-\u180F\u200B-\u200F\u202A-\u202E\u2060-\u206F\u3164\uFE00-\uFE0F\uFEFF\uFFA0]/g;
      const textTypes = new Set(["text", "search", "email", "url", "tel", "number", "password"]);
      const pickerTypes = new Set(["file", "color", "date", "datetime-local", "month", "week", "time"]);
      const credentialAutocomplete =
        /\b(current-password|new-password|one-time-code|cc-number|cc-csc|cc-exp(-month|-year)?)\b/;
      const inputRoles = new Map([
        ["button", "button"], ["submit", "button"], ["reset", "button"], ["image", "button"],
        ["checkbox", "checkbox"], ["radio", "radio"], ["range", "slider"], ["number", "spinbutton"],
        ["search", "searchbox"], ["file", "button"], ["color", "button"]
      ]);
      const interactiveSelector = [
        "a[href]", "area[href]", "button", "input:not([type='hidden'])", "select", "textarea",
        "summary", "[contenteditable='']", "[contenteditable='true']",
        "[contenteditable='plaintext-only']", "[role='button']", "[role='link']",
        "[role='checkbox']", "[role='radio']", "[role='switch']", "[role='tab']",
        "[role='menuitem']", "[role='menuitemcheckbox']", "[role='menuitemradio']",
        "[role='option']", "[role='textbox']", "[role='searchbox']", "[role='combobox']",
        "[role='slider']", "[role='spinbutton']", "[tabindex]:not([tabindex='-1'])"
      ].join(",");
      const contextSelector = [
        "h1", "h2", "h3", "h4", "h5", "h6", "img[alt]", "[role='heading']", "label", "legend",
        "th", "caption"
      ].join(",");
      // A click belongs to the nearest of these: interactive content handles its own clicks, and
      // a label forwards them to its control.
      const clickOwners = [
        "a[href]", "audio[controls]", "button", "details", "embed", "iframe", "img[usemap]",
        "input", "label", "select", "textarea", "video[controls]"
      ].join(",");
      const observedTypes = [
        "pointerdown", "pointerup", "mousedown", "mouseup", "click", "keydown", "keyup",
        "beforeinput", "input", "change"
      ];

      const docId = (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function")
        ? crypto.randomUUID()
        : Date.now().toString(36) + "-" + Math.random().toString(36).slice(2);
      const state = {
        snapshotKey: -1, refs: new Map(), events: [], eventSeq: 0, markTarget: null, ticks: 0,
        timer: 0, fileActivation: null, filled: new WeakSet(), protectedValues: []
      };

      function clean(text, limit) {
        if (typeof text !== "string") { return ""; }
        let value = text;
        for (const secret of state.protectedValues) { value = value.split(secret).join("[redacted]"); }
        value = value.replace(hiddenCharacters, "").replace(/\s+/g, " ").trim();
        return value.length > limit ? value.slice(0, limit - 1) + "\u2026" : value;
      }

      function clampInteger(value, lower, upper, fallback) {
        const number = Number(value);
        if (!Number.isFinite(number)) { return fallback; }
        return Math.min(upper, Math.max(lower, Math.trunc(number)));
      }

      function inputType(element) {
        return element instanceof HTMLInputElement ? (element.type || "text").toLowerCase() : "";
      }

      function activationOwner(element) {
        const owner = element.closest(clickOwners) || element;
        // Labels activate their associated controls, including external for= labels.
        return owner instanceof HTMLLabelElement ? (owner.control || owner) : owner;
      }

      function textOf(node) {
        return node ? (node.innerText || node.textContent || "") : "";
      }

      function isVisible(element) {
        if (!(element instanceof Element) || !element.isConnected) { return false; }
        if (element.closest("[aria-hidden='true'],[inert]")) { return false; }
        if (typeof element.checkVisibility === "function" && !element.checkVisibility({
          checkOpacity: true, checkVisibilityCSS: true, opacityProperty: true,
          visibilityProperty: true
        })) { return false; }
        const style = getComputedStyle(element);
        if (style.display === "none" || style.visibility !== "visible") { return false; }
        if (Number(style.opacity) === 0) { return false; }
        const rect = element.getBoundingClientRect();
        if (rect.width < 1 || rect.height < 1) { return false; }
        const root = document.scrollingElement || document.documentElement;
        const width = Math.max(root ? root.scrollWidth : 0, innerWidth);
        const height = Math.max(root ? root.scrollHeight : 0, innerHeight);
        const left = rect.left + scrollX;
        const top = rect.top + scrollY;
        if (left + rect.width <= 0 || top + rect.height <= 0) { return false; }
        if (left >= width || top >= height) { return false; }
        const fontSize = parseFloat(style.fontSize);
        const isControl = element instanceof HTMLInputElement || element instanceof HTMLSelectElement;
        return !(Number.isFinite(fontSize) && fontSize < 4 && !isControl);
      }

      function roleOf(element) {
        const explicit = (element.getAttribute("role") || "").trim().split(/\s+/)[0];
        if (explicit) { return clean(explicit, 32); }
        const tag = element.tagName.toLowerCase();
        if (tag === "a" || tag === "area") {
          return element.hasAttribute("href") ? "link" : "generic";
        }
        if (tag === "button" || tag === "summary") { return "button"; }
        if (tag === "select") {
          return element.multiple || element.size > 1 ? "listbox" : "combobox";
        }
        if (tag === "textarea") { return "textbox"; }
        if (tag === "img") { return "img"; }
        if (/^h[1-6]$/.test(tag)) { return "heading"; }
        if (tag === "input") { return inputRoles.get(inputType(element)) || "textbox"; }
        if (tag === "label" || tag === "legend" || tag === "caption") { return tag; }
        if (tag === "th") { return "columnheader"; }
        return element.isContentEditable ? "textbox" : "generic";
      }

      function nameOf(element) {
        const label = element.getAttribute("aria-label");
        if (label && label.trim()) { return clean(label, maxName); }
        const labelledBy = element.getAttribute("aria-labelledby");
        if (labelledBy) {
          const text = labelledBy.split(/\s+/)
            .map((id) => id ? textOf(document.getElementById(id)) : "")
            .join(" ");
          if (text.trim()) { return clean(text, maxName); }
        }
        if (element.labels && element.labels.length > 0) {
          const text = Array.from(element.labels).map(textOf).join(" ");
          if (text.trim()) { return clean(text, maxName); }
        }
        const tag = element.tagName.toLowerCase();
        const type = inputType(element);
        if (tag === "img" || type === "image") {
          return clean(element.getAttribute("alt") || element.getAttribute("title") || "", maxName);
        }
        if (type === "submit" || type === "reset" || type === "button") {
          return clean(element.value || type, maxName);
        }
        if (tag !== "input" && tag !== "textarea" && tag !== "select") {
          const text = textOf(element);
          if (text.trim()) { return clean(text, maxName); }
        }
        const fallback = element.getAttribute("title") || element.getAttribute("placeholder") || "";
        return clean(fallback, maxName);
      }

      // Password fields, fields with a credential autocomplete token and fields a sign-in Card
      // filled. Lists count too: card expiry fields are often selects.
      function isSensitive(element) {
        const isField = element instanceof HTMLInputElement
          || element instanceof HTMLTextAreaElement || element instanceof HTMLSelectElement;
        if (!isField) { return false; }
        if (state.filled.has(element)) { return true; }
        if (inputType(element) === "password") { return true; }
        return credentialAutocomplete.test((element.getAttribute("autocomplete") || "").toLowerCase());
      }

      // Whether a click on `element` reaches a credential field, directly or through a label.
      function reachesCredential(element) {
        if (isSensitive(element)) { return true; }
        const owner = element.closest(clickOwners);
        return owner instanceof HTMLLabelElement && owner.control !== null
          && isSensitive(owner.control);
      }

      function valueOf(element) {
        if (isSensitive(element)) { return { value: null, masked: true }; }
        if (element instanceof HTMLSelectElement) {
          const labels = Array.from(element.selectedOptions).map((option) => option.label || option.text);
          return { value: clean(labels.join(", "), maxValue), masked: false };
        }
        if (element instanceof HTMLInputElement) {
          const skipped = ["checkbox", "radio", "submit", "reset", "button", "image", "file", "hidden",
            "color", "range"];
          if (skipped.includes(inputType(element))) { return null; }
          return { value: clean(element.value, maxValue), masked: false };
        }
        if (element instanceof HTMLTextAreaElement) {
          return { value: clean(element.value, maxValue), masked: false };
        }
        if (element.isContentEditable) { return { value: clean(textOf(element), maxValue), masked: false }; }
        return null;
      }

      // `:disabled` also covers controls inside a disabled fieldset.
      function isDisabled(element) {
        if (element.getAttribute("aria-disabled") === "true") { return true; }
        return typeof element.matches === "function" && element.matches(":disabled");
      }

      function statesOf(element) {
        const states = [];
        const attribute = (name) => element.getAttribute(name);
        if (isDisabled(element)) { states.push("disabled"); }
        if (element.checked === true || attribute("aria-checked") === "true") { states.push("checked"); }
        if (element.indeterminate === true || attribute("aria-checked") === "mixed") { states.push("mixed"); }
        if (attribute("aria-expanded") === "true") { states.push("expanded"); }
        if (attribute("aria-expanded") === "false") { states.push("collapsed"); }
        if (attribute("aria-selected") === "true") { states.push("selected"); }
        if (attribute("aria-pressed") === "true") { states.push("pressed"); }
        if (element.required === true || attribute("aria-required") === "true") { states.push("required"); }
        if (element.readOnly === true || attribute("aria-readonly") === "true") { states.push("readonly"); }
        if (document.activeElement === element) { states.push("focused"); }
        const level = /^h([1-6])$/i.exec(element.tagName);
        if (level) { states.push("level " + level[1]); }
        return states;
      }

      function isEditable(element) {
        if (isDisabled(element)) { return false; }
        if (element instanceof HTMLTextAreaElement) { return !element.readOnly; }
        if (element instanceof HTMLInputElement) {
          return textTypes.has(inputType(element)) && !element.readOnly;
        }
        return element.isContentEditable === true;
      }

      function isSubmitControl(element) {
        if (element instanceof HTMLButtonElement) { return element.type === "submit" && element.form !== null; }
        if (element instanceof HTMLInputElement) {
          const type = inputType(element);
          return (type === "submit" || type === "image") && element.form !== null;
        }
        return false;
      }

      function opensPicker(element) {
        if (element instanceof HTMLSelectElement) { return true; }
        return element instanceof HTMLInputElement && pickerTypes.has(inputType(element));
      }

      function optionsOf(element) {
        // A credential list's options would reveal its selection.
        if (!(element instanceof HTMLSelectElement) || isSensitive(element)) { return null; }
        return Array.from(element.options).slice(0, maxOptions).map((option) => ({
          label: clean(option.label || option.text, maxName),
          disabled: option.disabled,
          selected: option.selected
        }));
      }

      function snapshot(input) {
        const snapshotKey = clampInteger(input && input.snapshotId, 0, Number.MAX_SAFE_INTEGER, -1);
        const limit = clampInteger(input && input.maxElements, 1, maxElements, 150);
        const full = input && input.mode === "full";
        const selector = full ? interactiveSelector + "," + contextSelector : interactiveSelector;
        const refs = new Map();
        const elements = [];
        let total = 0;
        for (const element of document.querySelectorAll(selector)) {
          if (!isVisible(element)) { continue; }
          total += 1;
          if (elements.length >= limit) { continue; }
          const ref = "e" + (elements.length + 1);
          refs.set(ref, new WeakRef(element));
          const value = valueOf(element);
          elements.push({
            ref,
            role: roleOf(element),
            name: nameOf(element),
            value: value ? value.value : null,
            masked: value ? value.masked : false,
            states: statesOf(element),
            editable: isEditable(element),
            sensitive: isSensitive(element),
            submit: isSubmitControl(element),
            selectable: element instanceof HTMLSelectElement && !isDisabled(element),
            picker: opensPicker(element),
            options: optionsOf(element)
          });
        }
        // Background measurements must not invalidate the refs of the snapshot a person is using.
        if (!(input && input.measureOnly === true)) {
          state.refs = refs;
          state.snapshotKey = snapshotKey;
          state.fileActivation = null;
        }
        return {
          docId,
          url: clean(String(location.href), 2048),
          title: clean(document.title || "", 200),
          elements,
          total,
          truncated: total > elements.length
        };
      }

      function lookup(input) {
        const key = clampInteger(input && input.snapshotId, 0, Number.MAX_SAFE_INTEGER, -2);
        if (key !== state.snapshotKey) { return { error: "stale_snapshot" }; }
        const reference = state.refs.get(String(input.ref));
        if (!reference) { return { error: "unknown_ref" }; }
        const element = reference.deref();
        if (!element || !element.isConnected) { return { error: "element_gone" }; }
        return { element };
      }

      function actionInfo(input) {
        const found = lookup(input);
        if (found.error) { return found; }
        const element = found.element;
        const owner = activationOwner(element);
        const form = owner.form || null;
        const submit = isSubmitControl(owner);
        const destination = submit && form
          ? (owner.getAttribute("formaction") ? owner.formAction : form.action)
          : ((owner instanceof HTMLAnchorElement || owner instanceof HTMLAreaElement) ? owner.href : null);
        const method = submit && form
          ? (owner.getAttribute("formmethod") || form.method || "get").toUpperCase() : null;
        return {
          docId, origin: String(location.origin), destination, method,
          label: nameOf(owner),
          payment: !!(form && form.querySelector("[autocomplete~='cc-number'],[autocomplete~='cc-csc']")),
          link: owner instanceof HTMLAnchorElement || owner instanceof HTMLAreaElement,
          file: inputType(owner) === "file"
        };
      }

      function pickerTarget(input) {
        const activation = state.fileActivation;
        state.fileActivation = null;
        const found = lookup(input);
        if (found.error) { return found; }
        return { matches: inputType(found.element) === "file" && activation === found.element,
          docId, origin: String(location.origin) };
      }

      function documentId() {
        return { docId };
      }

      // "instant" ignores a page's smooth-scroll CSS, so geometry read right after is final.
      function scrollIntoViewNow(element, inline) {
        try {
          element.scrollIntoView({ block: "center", inline, behavior: "instant" });
        } catch (error) {
          element.scrollIntoView({ block: "center", inline });
        }
      }

      function scrollRootNow(root, dx, dy) {
        try {
          root.scrollBy({ left: dx, top: dy, behavior: "instant" });
        } catch (error) {
          root.scrollBy(dx, dy);
        }
      }

      function target(input) {
        const found = lookup(input);
        if (found.error) { return found; }
        const element = found.element;
        if (!isVisible(element)) { return { error: "not_visible" }; }
        if (isDisabled(element)) { return { error: "disabled" }; }
        scrollIntoViewNow(element, "center");
        const rect = element.getBoundingClientRect();
        const x = rect.left + rect.width / 2;
        const y = rect.top + rect.height / 2;
        if (x < 0 || y < 0 || x >= innerWidth || y >= innerHeight) {
          return { error: "outside_viewport" };
        }
        const hit = document.elementFromPoint(x, y);
        const labels = element.labels ? Array.from(element.labels) : [];
        const onTarget = hit !== null && (hit === element || element.contains(hit)
          || labels.some((label) => label === hit || label.contains(hit)));
        if (!onTarget) { return { error: "obscured" }; }
        // Native events go to the point, which can lie on a credential field inside the element.
        const sensitive = reachesCredential(element) || reachesCredential(hit);
        return {
          x, y, viewportWidth: innerWidth, viewportHeight: innerHeight,
          editable: isEditable(element), sensitive,
          submit: isSubmitControl(element), picker: opensPicker(element), file: inputType(element) === "file"
        };
      }

      function recordEvent(event) {
        const markTarget = state.markTarget;
        const eventTarget = event.target;
        const onTarget = markTarget !== null && eventTarget instanceof Node
          && (markTarget === eventTarget || markTarget.contains(eventTarget));
        // Focus neither identifies a native chooser nor proves a trusted activation.
        // Any intervening observed event invalidates this single marked-control activation.
        state.fileActivation = event.type === "click" && event.isTrusted === true
          && inputType(markTarget) === "file" && eventTarget instanceof Element
          && activationOwner(eventTarget) === markTarget ? markTarget : null;
        state.eventSeq += 1;
        state.events.push({
          seq: state.eventSeq, type: event.type, trusted: event.isTrusted === true, onTarget
        });
        if (state.events.length > maxEvents) {
          state.events.splice(0, state.events.length - maxEvents);
        }
      }

      function mark(input) {
        let markTarget = null;
        if (input && typeof input.ref === "string") {
          const found = lookup(input);
          if (found.error) { return found; }
          markTarget = found.element;
        }
        state.markTarget = markTarget;
        state.fileActivation = null;
        return { mark: state.eventSeq };
      }

      function observed(input) {
        const since = clampInteger(input && input.since, 0, Number.MAX_SAFE_INTEGER, 0);
        const events = state.events.filter((entry) => entry.seq > since)
          .map((entry) => ({ type: entry.type, trusted: entry.trusted, onTarget: entry.onTarget }));
        return { events };
      }

      function focusState(input) {
        const found = lookup(input);
        if (found.error) { return found; }
        const active = document.activeElement;
        const focused = active !== null && (active === found.element || found.element.contains(active));
        return { focused };
      }

      function currentText(element) {
        if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
          return element.value;
        }
        return element.innerText || element.textContent || "";
      }

      // Values of credential fields, filled ones included, are never read back.
      function verifyText(input) {
        const found = lookup(input);
        if (found.error) { return found; }
        if (isSensitive(found.element)) { return { error: "credential_field" }; }
        const text = String(input.text);
        const current = currentText(found.element);
        return { matches: input.replace === true ? current === text : current.endsWith(text) };
      }

      function selectContents(element, collapseToEnd) {
        if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
          if (!collapseToEnd) {
            element.select();
            return;
          }
          try {
            const end = element.value.length;
            element.setSelectionRange(end, end);
          } catch (error) {
            // Some input types (email, number) have no selection API; the caret stays put.
          }
          return;
        }
        const selection = getSelection();
        if (!selection) { return; }
        const range = document.createRange();
        range.selectNodeContents(element);
        if (collapseToEnd) { range.collapse(false); }
        selection.removeAllRanges();
        selection.addRange(range);
      }

      function caretToEnd(input) {
        const found = lookup(input);
        if (found.error) { return found; }
        selectContents(found.element, true);
        return { ok: true };
      }

      function setFieldValue(element, value) {
        const prototype = element instanceof HTMLTextAreaElement
          ? HTMLTextAreaElement.prototype
          : HTMLInputElement.prototype;
        const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
        if (descriptor && descriptor.set) {
          descriptor.set.call(element, value);
        } else {
          element.value = value;
        }
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
      }

      function scriptType(input) {
        const found = lookup(input);
        if (found.error) { return found; }
        const element = found.element;
        if (!isEditable(element)) { return { error: "not_editable" }; }
        if (isSensitive(element)) { return { error: "credential_field" }; }
        const text = String(input.text);
        const replace = input.replace === true;
        element.focus();
        selectContents(element, !replace);
        let inserted = false;
        try {
          inserted = document.execCommand("insertText", false, text);
        } catch (error) {
          inserted = false;
        }
        if (!inserted) {
          if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
            setFieldValue(element, replace ? text : element.value + text);
          } else {
            if (replace) {
              element.textContent = text;
            } else {
              element.append(document.createTextNode(text));
            }
            element.dispatchEvent(new Event("input", { bubbles: true }));
          }
        }
        return verifyText(input);
      }

      function scriptClick(input) {
        const found = lookup(input);
        if (found.error) { return found; }
        const element = found.element;
        if (!isVisible(element)) { return { error: "not_visible" }; }
        if (isDisabled(element)) { return { error: "disabled" }; }
        if (isSubmitControl(element) && !(input && input.allowSubmit === true)) {
          return { error: "submit_control" };
        }
        if (reachesCredential(element)) { return { error: "credential_field" }; }
        if (inputType(element) === "file") { element.focus(); }
        scrollIntoViewNow(element, "center");
        if (typeof element.click === "function") {
          element.click();
        } else {
          element.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
        }
        return { ok: true };
      }

      function scriptSelect(input) {
        const found = lookup(input);
        if (found.error) { return found; }
        const element = found.element;
        if (!(element instanceof HTMLSelectElement)) { return { error: "not_selectable" }; }
        if (isDisabled(element)) { return { error: "disabled" }; }
        if (isSensitive(element)) { return { error: "credential_field" }; }
        const index = clampInteger(input.index, 0, maxOptions - 1, -1);
        const option = index >= 0 ? element.options[index] : undefined;
        if (!option || option.disabled) { return { error: "option_unavailable" }; }
        if (clean(option.label || option.text, maxName) !== String(input.label)) {
          return { error: "option_changed" };
        }
        element.focus();
        if (element.multiple) {
          for (const candidate of element.options) { candidate.selected = candidate === option; }
        } else {
          element.selectedIndex = index;
        }
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        return { matches: option.selected === true };
      }

      function scrollBy(input) {
        const root = document.scrollingElement || document.documentElement;
        if (!root) { return { error: "not_scrollable" }; }
        const dx = clampInteger(input && input.dx, -20000, 20000, 0);
        const dy = clampInteger(input && input.dy, -20000, 20000, 0);
        const beforeX = root.scrollLeft;
        const beforeY = root.scrollTop;
        scrollRootNow(root, dx, dy);
        return { moved: Math.hypot(root.scrollLeft - beforeX, root.scrollTop - beforeY) };
      }

      function scrollTo(input) {
        const found = lookup(input);
        if (found.error) { return found; }
        const root = document.scrollingElement || document.documentElement;
        const beforeX = root ? root.scrollLeft : 0;
        const beforeY = root ? root.scrollTop : 0;
        scrollIntoViewNow(found.element, "nearest");
        const moved = root ? Math.hypot(root.scrollLeft - beforeX, root.scrollTop - beforeY) : 0;
        return { moved };
      }

      function timerStart(input) {
        const interval = clampInteger(input && input.intervalMs, 10, 10000, 100);
        if (state.timer) { clearInterval(state.timer); }
        state.ticks = 0;
        state.timer = setInterval(() => { state.ticks += 1; }, interval);
        return { docId, ticks: 0, running: true, visibility: document.visibilityState };
      }

      function timerRead() {
        return {
          docId, ticks: state.ticks, running: state.timer !== 0,
          visibility: document.visibilityState
        };
      }

      function timerStop() {
        if (state.timer) { clearInterval(state.timer); }
        state.timer = 0;
        return { docId, ticks: state.ticks, running: false, visibility: document.visibilityState };
      }

      // A login pair: exactly one visible, enabled current-password field and the user-name field
      // before it in the same form (an autocomplete-tagged one, else the nearest text field).
      function loginPairIn(form) {
        const fields = Array.from(form.elements).filter((element) =>
          element instanceof HTMLInputElement && isVisible(element) && !isDisabled(element)
          && !element.readOnly);
        const passwords = fields.filter((element) => inputType(element) === "password"
          && !/\bnew-password\b/.test((element.getAttribute("autocomplete") || "").toLowerCase()));
        if (passwords.length !== 1) { return null; }
        const password = passwords[0];
        const before = fields.slice(0, fields.indexOf(password))
          .filter((element) => ["text", "email"].includes(inputType(element)));
        const tagged = before.find((element) =>
          /\b(username|email)\b/.test((element.getAttribute("autocomplete") || "").toLowerCase()));
        const username = tagged || before[before.length - 1];
        return username ? { username, password } : null;
      }

      function refOf(element) {
        for (const [ref, reference] of state.refs) {
          if (reference.deref() === element) { return ref; }
        }
        return null;
      }

      // The first login form whose two fields are in the given snapshot, as refs.
      function signInForm(input) {
        const key = clampInteger(input && input.snapshotId, 0, Number.MAX_SAFE_INTEGER, -2);
        if (key !== state.snapshotKey) { return { error: "stale_snapshot" }; }
        for (const form of Array.from(document.forms)) {
          const pair = loginPairIn(form);
          if (!pair) { continue; }
          const usernameRef = refOf(pair.username);
          const passwordRef = refOf(pair.password);
          if (usernameRef && passwordRef) {
            return { usernameRef, passwordRef, origin: String(location.origin) };
          }
        }
        return { error: "no_signin_form" };
      }

      // Fills a sign-in Card's credential only if this document still has the Card's origin and
      // login pair. Both fields then count as credential fields: snapshots mask them and lab
      // actions refuse them. Only booleans come back, never a value.
      function fillCredential(input) {
        if (input && input.expectedDocument && input.expectedDocument !== docId) { return { error: "stale_snapshot" }; }
        if (String(location.origin) !== String(input && input.origin)) {
          return { error: "origin_mismatch" };
        }
        const user = lookup({ snapshotId: input.snapshotId, ref: input.usernameRef });
        const pass = lookup({ snapshotId: input.snapshotId, ref: input.passwordRef });
        if (user.error || pass.error) { return { error: "fields_changed" }; }
        const pair = pass.element.form ? loginPairIn(pass.element.form) : null;
        if (!pair || pair.username !== user.element || pair.password !== pass.element) {
          return { error: "fields_changed" };
        }
        const username = String(input.username);
        const password = String(input.password);
        state.protectedValues = Array.from(new Set([...state.protectedValues, ...[username, password].flatMap((value) =>
          [value, encodeURIComponent(value), encodeURI(value)])])).filter(Boolean)
          .sort((a, b) => b.length - a.length);
        state.filled.add(pair.username);
        state.filled.add(pair.password);
        setFieldValue(pair.username, username);
        setFieldValue(pair.password, password);
        const masked = [pair.username, pair.password]
          .filter((element) => { const value = valueOf(element); return value && value.masked; })
          .length;
        return {
          usernameMatches: pair.username.value === username,
          passwordMatches: pair.password.value === password,
          masked
        };
      }

      // Lab-page instrument: the digests and counts the lab page's own script recorded.
      function labSignInReceipt() {
        const receipt = document.getElementById("lab-signin-receipt");
        if (!receipt) { return { error: "no_signin_form" }; }
        const data = receipt.dataset;
        return {
          digests: data.digests === "true",
          usernameDigest: String(data.userDigest || "").slice(0, 64),
          passwordDigest: String(data.passwordDigest || "").slice(0, 64),
          inputEvents: clampInteger(data.inputEvents, 0, 1000000, 0)
        };
      }

      const api = Object.freeze({
        documentId, snapshot, target, mark, observed, focusState, caretToEnd, verifyText,
        actionInfo, pickerTarget, scriptType, scriptClick, scriptSelect, scrollBy, scrollTo,
        timerStart, timerRead, timerStop, signInForm, fillCredential, labSignInReceipt
      });
      Object.defineProperty(globalThis, "__memoshiAutomation", {
        value: api, writable: false, configurable: false, enumerable: false
      });

      for (const type of observedTypes) {
        addEventListener(type, recordEvent, { capture: true, passive: true });
      }

      try {
        const handlers = globalThis.webkit && globalThis.webkit.messageHandlers;
        const handler = handlers ? handlers.memoshiFrame : undefined;
        if (handler) { handler.postMessage({ kind: "frame", docId,
          handle: globalThis.webkit.createJSHandle(window) }); }
      } catch (error) {
        // Registration is best-effort; snapshots count frames that never registered as absent.
      }
    })();
    """#

  /// An offline fixture loaded with `loadHTMLString`: inputs, a list, a blocked form, a login
  /// form whose page-world script digests what it receives, a page-world timer and an
  /// opaque-origin frame. It contains no subresources and never submits anything.
  public static let labPageHTML = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Memoshi S3 Lab Page</title>
    <style>
      :root { color-scheme: light dark; font: 15px -apple-system, system-ui, sans-serif; }
      body { margin: 0 auto; max-width: 760px; padding: 24px; line-height: 1.45; }
      section {
        margin: 0 0 24px; padding: 16px; border-radius: 12px;
        border: 1px solid color-mix(in srgb, currentColor 18%, transparent);
      }
      label { display: block; margin: 8px 0 4px; }
      input, textarea, select, button { font: inherit; }
      output { font-variant-numeric: tabular-nums; }
      iframe {
        width: 100%; height: 140px; border-radius: 8px;
        border: 1px dashed color-mix(in srgb, currentColor 30%, transparent);
      }
      #tall { height: 1600px; }
    </style>
    </head>
    <body>
    <h1>Memoshi S3 lab page</h1>
    <p>An offline fixture loaded by the app. It makes no network requests.</p>
    <section aria-labelledby="inputs-heading">
      <h2 id="inputs-heading">Inputs</h2>
      <label for="lab-text">Lab text</label>
      <input id="lab-text" type="text" autocomplete="off">
      <label for="lab-notes">Lab notes</label>
      <textarea id="lab-notes" rows="3"></textarea>
      <label for="lab-choice">Lab choice</label>
      <select id="lab-choice">
        <option>First option</option>
        <option>Second option</option>
        <option disabled>Unavailable option</option>
        <option>Fourth option</option>
      </select>
      <label><input id="lab-check" type="checkbox"> Lab checkbox</label>
      <label for="lab-password">Lab password (lab actions refuse it)</label>
      <input id="lab-password" type="password" autocomplete="off">
      <p>
        <button id="lab-count" type="button">Count clicks</button>
        <output id="lab-count-value">0</output>
      </p>
    </section>
    <section aria-labelledby="events-heading">
      <h2 id="events-heading">Page-world view</h2>
      <p>Last event seen by the page: <output id="lab-last-event">none</output></p>
      <p>
        Page timer ticks (10 Hz target): <output id="lab-ticks">0</output>;
        visibility: <output id="lab-visibility">unknown</output>
      </p>
    </section>
    <section aria-labelledby="form-heading">
      <h2 id="form-heading">Form gate</h2>
      <form method="post" action="https://lab.memoshi.invalid/submit">
        <label for="lab-form-field">Form field</label>
        <input id="lab-form-field" name="field" type="text">
        <button type="submit">Submit form (blocked)</button>
      </form>
    </section>
    <section aria-labelledby="signin-heading">
      <h2 id="signin-heading">Sign-in Card</h2>
      <p>A login form for the development sign-in Card's canary. It is never submitted.</p>
      <form id="lab-signin" method="post" action="https://lab.memoshi.invalid/session">
        <label for="lab-username">Lab user name</label>
        <input id="lab-username" name="username" type="text" autocomplete="username"
          autocapitalize="off" autocorrect="off" spellcheck="false">
        <label for="lab-signin-password">Lab sign-in password</label>
        <input id="lab-signin-password" name="password" type="password"
          autocomplete="current-password">
        <button type="submit">Sign in (blocked)</button>
      </form>
      <p>Page-world receipt: <output id="lab-signin-receipt">nothing received</output></p>
    </section>
    <section aria-labelledby="frame-heading">
      <h2 id="frame-heading">Opaque-origin frame</h2>
      <div id="frame-slot"></div>
    </section>
    <section aria-labelledby="scroll-heading">
      <h2 id="scroll-heading">Scroll area</h2>
      <div id="tall"></div>
      <p><a href="#inputs-heading">Back to inputs</a></p>
    </section>
    <script>
      (() => {
        const last = document.getElementById("lab-last-event");
        const count = document.getElementById("lab-count-value");
        const ticks = document.getElementById("lab-ticks");
        const visibility = document.getElementById("lab-visibility");
        let clicks = 0;
        let tickCount = 0;
        document.getElementById("lab-count").addEventListener("click", () => {
          clicks += 1;
          count.textContent = String(clicks);
        });
        for (const type of ["click", "keydown", "input", "change"]) {
          document.addEventListener(type, (event) => {
            last.textContent = event.type + (event.isTrusted ? " (trusted)" : " (untrusted)");
          }, true);
        }
        setInterval(() => {
          tickCount += 1;
          ticks.textContent = String(tickCount);
          visibility.textContent = document.visibilityState;
        }, 100);
        const frame = document.createElement("iframe");
        frame.title = "Lab frame";
        frame.src = "data:text/html;charset=utf-8," + encodeURIComponent(
          "<!doctype html><meta charset=utf-8><title>Lab frame</title>"
          + "<body style='font:15px -apple-system,system-ui,sans-serif'>"
          + "<p>Opaque-origin frame</p><label>Frame text <input></label> "
          + "<button type=button>Frame button</button> <output>0</output>"
          + "<script>let n=0;document.querySelector('button').addEventListener('click',"
          + "()=>{n+=1;document.querySelector('output').textContent=String(n)})<\/script>");
        document.getElementById("frame-slot").append(frame);
        // The page's own view of its login form: SHA-256 digests and lengths of what it
        // received, never the values themselves.
        const signIn = document.getElementById("lab-signin");
        const signInUser = document.getElementById("lab-username");
        const signInPassword = document.getElementById("lab-signin-password");
        const receipt = document.getElementById("lab-signin-receipt");
        const canDigest = Boolean(globalThis.crypto && crypto.subtle && globalThis.TextEncoder);
        let receiptEvents = 0;
        let receiptSequence = 0;
        const digest = async (text) => {
          const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
          return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0"))
            .join("");
        };
        const updateReceipt = async () => {
          receiptEvents += 1;
          receiptSequence += 1;
          const sequence = receiptSequence;
          const user = signInUser.value;
          const password = signInPassword.value;
          const digests = canDigest
            ? await Promise.all([digest(user), digest(password)]) : ["", ""];
          if (sequence !== receiptSequence) { return; }
          receipt.dataset.digests = String(canDigest);
          receipt.dataset.userDigest = digests[0];
          receipt.dataset.passwordDigest = digests[1];
          receipt.dataset.inputEvents = String(receiptEvents);
          receipt.textContent = user || password
            ? "received a user name of " + user.length + " characters and a password of "
              + password.length + " characters"
            : "nothing received";
        };
        signIn.addEventListener("input", updateReceipt);
        signIn.addEventListener("change", updateReceipt);
      })();
    </script>
    </body>
    </html>
    """#
}
