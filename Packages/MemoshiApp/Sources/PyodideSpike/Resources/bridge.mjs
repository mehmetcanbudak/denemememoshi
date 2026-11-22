// The page is a fixed responsive controller, never a worker-selected program or Window API proxy.
const messageLimit = 48 * 1024 * 1024;
const networkMessageLimit = 2 * 1024 * 1024;
const controlKinds = ["coreReady", "ready", "executing", "result", "failure"];
const nativeSends = new Map();
let worker;
// The worker's private control port. Once it connects, the public worker bus carries nothing.
let port;
let workerSourceURL;
let activeRequest;

function fail(failure) {
  window.webkit.messageHandlers.memoshiPyodide.postMessage(JSON.stringify({
    kind: "failure", id: activeRequest?.cellID, generation: activeRequest?.generation, failure
  }));
}

function releaseWorkerSource() {
  if (!workerSourceURL) return;
  URL.revokeObjectURL(workerSourceURL);
  workerSourceURL = undefined;
}

// Installed before worker construction: an absent entrypoint means no worker has started yet.
window.memoshiPyodideTerminate = () => {
  const current = worker;
  worker = undefined;
  port?.close();
  port = undefined;
  activeRequest = undefined;
  current?.terminate();
  nativeSends.clear();
  releaseWorkerSource();
  return true;
};

window.memoshiPyodideExecute = request => {
  if (!worker || !port || activeRequest) throw new Error("closedInterpreter");
  activeRequest = {cellID: request.id, generation: request.generation, accepting: true};
  port.postMessage({kind: "execute", request});
};

function replyNetwork(current, cell, requestID, response, failed) {
  if (worker !== current || activeRequest !== cell) return;
  port.postMessage({kind: "networkReply", cellID: cell.cellID, generation: cell.generation,
    requestID, response, failed});
}

function handleNetwork(call, text) {
  const current = worker;
  const cell = activeRequest;
  if (!current || !cell || typeof call !== "object" || call === null ||
      call.cellID !== cell.cellID || call.generation !== cell.generation ||
      typeof call.requestID !== "string" || !call.requestID || call.requestID.length > 64) return;
  if (text.length > networkMessageLimit) {
    replyNetwork(current, cell, call.requestID, undefined, true);
    return;
  }
  const native = window.webkit.messageHandlers.memoshiPyodideNetwork;
  if (call.kind === "send") {
    if (!cell.accepting || nativeSends.size >= 8 || nativeSends.has(call.requestID)) {
      replyNetwork(current, cell, call.requestID, undefined, true);
      return;
    }
    const entry = {cell, cancelling: false};
    nativeSends.set(call.requestID, entry);
    native.postMessage(text).then(response => {
      replyNetwork(current, cell, call.requestID, response, false);
    }, () => {
      replyNetwork(current, cell, call.requestID, undefined, true);
    }).finally(() => {
      if (nativeSends.get(call.requestID) === entry) nativeSends.delete(call.requestID);
    });
  } else if (call.kind === "cancel") {
    const entry = nativeSends.get(call.requestID);
    if (!entry || entry.cell !== cell || entry.cancelling) return;
    entry.cancelling = true;
    // The original send receives its failure; cancellation acknowledgement is not another response.
    native.postMessage(text).catch(() => {});
  } else if (call.kind === "end" && cell.accepting) {
    cell.accepting = false;
    native.postMessage(text).then(() => {
      replyNetwork(current, cell, call.requestID, true, false);
    }, () => {
      replyNetwork(current, cell, call.requestID, undefined, true);
    });
  }
}

// Every worker message is structured data from its private port, serialized here for native in
// this page's own realm. An out-of-order or mismatched control message fails and discards the
// realm instead of being ignored.
function receive(current, message) {
  if (worker !== current) return;
  if (typeof message !== "object" || message === null) {
    fail("scriptFailed");
    return;
  }
  if (message.kind === "network") {
    let text;
    try { text = JSON.stringify(message.call); } catch { fail("scriptFailed"); return; }
    if (typeof text !== "string") { fail("scriptFailed"); return; }
    handleNetwork(message.call, text);
    return;
  }
  let text;
  try { text = JSON.stringify(message); } catch { fail("scriptFailed"); return; }
  if (text.length > messageLimit) {
    fail("outputLimit");
    return;
  }
  if (!controlKinds.includes(message.kind)) {
    fail("scriptFailed");
    return;
  }
  if (activeRequest) {
    if (message.id !== activeRequest.cellID || message.generation !== activeRequest.generation) {
      fail("scriptFailed");
      return;
    }
  } else if (message.kind === "executing" || message.kind === "result") {
    fail("scriptFailed");
    return;
  }
  if (message.kind === "result" || message.kind === "failure") {
    activeRequest = undefined;
  }
  window.webkit.messageHandlers.memoshiPyodide.postMessage(text);
}

try {
  // Blob workers inherit this page's sealed connect/script policy, including their descendants.
  // Imported module response CSP does not prohibit nested workers; worker.mjs removes the Worker
  // constructors before any interpreter code runs, and that refusal is what cell code meets.
  const entrypoint = new URL("./worker.mjs", import.meta.url).href;
  workerSourceURL = URL.createObjectURL(new Blob([
    `import(${JSON.stringify(entrypoint)}).catch(() => self.postMessage(JSON.stringify({kind: "failure", failure: "startupFailed"})));`
  ], {type: "text/javascript"}));
  const current = new Worker(workerSourceURL, {type: "module"});
  worker = current;
  current.addEventListener("message", event => {
    // Only the worker's first message, sent before any interpreter code, may connect. A failed
    // entrypoint import is the sole other message that can precede it.
    if (worker !== current || port) return;
    if (event.data?.kind === "connect" && event.ports.length === 1) {
      port = event.ports[0];
      port.onmessage = message => receive(current, message.data);
      return;
    }
    fail("startupFailed");
  });
  current.addEventListener("error", event => {
    if (worker !== current) return;
    releaseWorkerSource();
    event.preventDefault();
    // Never expose source, file contents or exception bodies through the native failure state.
    fail(activeRequest ? "scriptFailed" : "startupFailed");
  });
} catch {
  releaseWorkerSource();
  fail("startupFailed");
}
