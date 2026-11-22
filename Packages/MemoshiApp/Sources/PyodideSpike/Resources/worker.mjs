import { loadPyodide } from "./Runtime/pyodide.mjs";

// The only host channel exists before any interpreter or cell code runs. Its port, bound send
// and event reader are captured now, and the page ignores the public worker bus once this
// connects, so cell code can neither read nor post control messages. Cell code still shares this
// realm's intrinsics and Pyodide's own runner, so it can still make this worker report a cell
// early: native session limits, not this channel, bound how long cell code can run.
const hostChannel = new MessageChannel();
const hostPort = hostChannel.port1;
const sendToHost = MessagePort.prototype.postMessage.bind(hostPort);
const messageData = Function.prototype.call.bind(
  Object.getOwnPropertyDescriptor(MessageEvent.prototype, "data").get);
// Structured clone copies own data only, so an inherited toJSON or getter planted by an earlier
// cell cannot rewrite a control message. The page serializes and size-checks it for native.
const post = message => sendToHost(message);
const apply = Reflect.apply;
// Cell code can replace `Map` and the methods on its prototype. The records that decide network
// admission and reply delivery use the constructor and methods captured here, before any
// interpreter or cell code runs, so a replacement neither sees those records nor answers for them.
const NativeMap = Map;
const mapHas = Function.prototype.call.bind(Map.prototype.has);
const mapGet = Function.prototype.call.bind(Map.prototype.get);
const mapSet = Function.prototype.call.bind(Map.prototype.set);
const mapDelete = Function.prototype.call.bind(Map.prototype.delete);
const mapForEach = Function.prototype.call.bind(Map.prototype.forEach);
const mapSize = Function.prototype.call.bind(
  Object.getOwnPropertyDescriptor(Map.prototype, "size").get);
// Each cell gets its own output decoders. A cell that replaces the global constructor must not
// make a later cell fail before it starts.
const NativeTextDecoder = TextDecoder;
// Timers a cell starts end with that cell. This is hygiene for accidental leftovers, not
// containment: message ports and other callbacks can still run code after a cell returns.
const nativeSetTimeout = globalThis.setTimeout;
const nativeSetInterval = globalThis.setInterval;
const nativeClearTimeout = globalThis.clearTimeout;
let cellTimers;
globalThis.setTimeout = function setTimeout(handler, timeout, ...rest) {
  const owner = cellTimers;
  if (!owner || typeof handler !== "function") {
    return apply(nativeSetTimeout, globalThis, [handler, timeout, ...rest]);
  }
  const id = apply(nativeSetTimeout, globalThis, [function () {
    owner.delete(id);
    return apply(handler, this, arguments);
  }, timeout, ...rest]);
  owner.add(id);
  return id;
};
globalThis.setInterval = function setInterval(handler, timeout, ...rest) {
  const id = apply(nativeSetInterval, globalThis, [handler, timeout, ...rest]);
  cellTimers?.add(id);
  return id;
};
// Nested workers are refused, not tracked. A worker started by cell code would be its own realm,
// outside every cell-end cleanup, so it could keep computing and messaging this realm after the
// cell returns. Deleting the interface objects before any interpreter code runs leaves cell code
// no constructor to reach: no worker instance exists in this realm to recover one from.
for (const name of ["Worker", "SharedWorker"]) delete globalThis[name];
if (typeof globalThis.Worker !== "undefined" || typeof globalThis.SharedWorker !== "undefined") {
  throw new Error("nested workers remain constructible");
}
const roots = ["numpy", "pandas", "scipy", "matplotlib"];
const textLimit = 256 * 1024;
const fileLimit = 16 * 1024 * 1024;
const totalFileLimit = 32 * 1024 * 1024;
// Emscripten O_WRONLY | O_CREAT | O_EXCL. The pinned runtime rejects the newer "wx" string mode.
const exclusiveInputFlags = 0o1 | 0o100 | 0o200;
let runtime;
let helpers;
let running = false;
let output;
let allowedPackages;
let activeCell;
let networkSequence = 0;
const pendingNetwork = new NativeMap();
const requestBodyLimit = 1024 * 1024;
const sealedFetch = globalThis.fetch.bind(globalThis);
const networkMetadata = new WeakMap();
const responseClone = Response.prototype.clone;
const networkFailure = () => new TypeError("Network request failed");
const abortFailure = () => new DOMException("Network request aborted", "AbortError");
// Network admission belongs to the cell whose own asyncio tasks make the request, not to
// whichever cell happens to be live. A cell's root task, and every task created while one of its
// tasks is executing, is recorded here, outside Python's reach; the record ends with the cell.
// A request is admitted only while a recorded task is the interpreter's current task and its
// coroutine is actually executing. Each check calls builtins, C descriptors and `Map` methods
// captured before any cell code ran, never a Python value a cell can find and reuse (a task's
// context, a context variable, a patched class or helper) or a collection method it can
// replace. So work an earlier cell left behind, JavaScript callbacks, and tasks they create
// cannot borrow a live cell's admission, even by entering its context or naming its task as
// current. Code that writes the interpreter's own memory, which Pyodide exposes to Python, can
// still forge both facts; native limits bound that.
const cellTaskSource = [
  "import _asyncio, asyncio, types",
  "from pyodide.code import eval_code_async",
  "loop = asyncio.get_event_loop()",
  "create = loop.create_task",
  "current_task = _asyncio.current_task",
  "task_coroutine = _asyncio.Task.get_coro",
  "coroutine_type = types.CoroutineType",
  "coroutine_running = types.CoroutineType.cr_running.__get__",
  "type_of = type",
  "identity = id",
  "def start(source, scope):",
  "    return create(eval_code_async(source, scope))",
  "def install(record):",
  "    def create_task(coro, *, name=None, context=None, eager_start=None):",
  "        extra = {} if eager_start is None else {'eager_start': eager_start}",
  "        task = create(coro, name=name, context=context, **extra)",
  "        record(task)",
  "        return task",
  "    loop.create_task = create_task",
].join("\n");
let startCell;
let pyLoop;
let currentTask;
let taskCoroutine;
let coroutineRunning;
let typeOf;
let identity;
let coroutineTypeID;
// Python id -> retained task proxy for the live cell; undefined between cells. Retaining each
// proxy keeps its task alive, so an id here cannot be reused by another object.
let cellTasks;

function cellTaskExecuting() {
  if (!cellTasks) return false;
  let task;
  let coroutine;
  let kind;
  try {
    task = currentTask(pyLoop);
    if (task === undefined || !mapHas(cellTasks, identity(task))) return false;
    coroutine = taskCoroutine(task);
    kind = typeOf(coroutine);
    return identity(kind) === coroutineTypeID && coroutineRunning(coroutine) === true;
  } catch {
    return false;
  } finally {
    // No iteration protocol here: a cell can replace the array iterator.
    if (typeof task?.destroy === "function") task.destroy();
    if (typeof coroutine?.destroy === "function") coroutine.destroy();
    if (typeof kind?.destroy === "function") kind.destroy();
  }
}

// Called by the loop's create_task. A task is recorded only if one of the live cell's tasks is
// executing the call; anything else may create tasks, but they carry no admission.
function recordCellTask(task) {
  if (typeof task?.copy !== "function" || !cellTaskExecuting()) return;
  const kept = task.copy();
  const key = identity(kept);
  if (mapHas(cellTasks, key)) kept.destroy();
  else mapSet(cellTasks, key, kept);
}

function endCellTaskRecord() {
  const owned = cellTasks;
  cellTasks = undefined;
  if (!owned) return;
  mapForEach(owned, task => task.destroy());
}

function postNetwork(call) {
  post({kind: "network", call});
}

function nativeCall(cell, kind, fields = {}, signal) {
  if (kind === "send" && (activeCell !== cell || mapSize(pendingNetwork) >= 8)) {
    return Promise.reject(networkFailure());
  }
  if (signal?.aborted) return Promise.reject(abortFailure());
  const requestID = String(++networkSequence);
  return new Promise((resolve, reject) => {
    const finish = (response, failed) => {
      mapDelete(pendingNetwork, requestID);
      signal?.removeEventListener("abort", abort);
      if (signal?.aborted) reject(abortFailure());
      else if (failed) reject(networkFailure());
      else resolve(response);
    };
    const abort = () => {
      postNetwork({kind: "cancel", requestID, ...cell});
      finish(undefined, true);
    };
    mapSet(pendingNetwork, requestID, {cell, finish});
    signal?.addEventListener("abort", abort, {once: true});
    postNetwork({...fields, kind, requestID, ...cell});
  });
}

hostPort.onmessage = event => {
  const message = messageData(event);
  if (message?.kind === "execute") {
    void execute(message.request);
    return;
  }
  if (message?.kind !== "networkReply") return;
  const pending = mapGet(pendingNetwork, message.requestID);
  if (!pending || message.cellID !== pending.cell.cellID ||
      message.generation !== pending.cell.generation) return;
  pending.finish(message.response, message.failed !== false);
};

async function boundedRequestBody(request) {
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks = [];
  let count = 0;
  const abort = () => { void reader.cancel().catch(() => {}); };
  request.signal.addEventListener("abort", abort, {once: true});
  try {
    for (;;) {
      if (request.signal.aborted) throw abortFailure();
      const {value, done} = await reader.read();
      if (request.signal.aborted) throw abortFailure();
      if (done) break;
      count += value.byteLength;
      if (count > requestBodyLimit) {
        await reader.cancel();
        throw networkFailure();
      }
      chunks.push(value);
    }
  } finally {
    request.signal.removeEventListener("abort", abort);
    reader.releaseLock();
  }
  if (chunks.length === 1) return chunks[0];
  const bytes = new Uint8Array(count);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

// Genuine Response slots retain bodyUsed, headers and normal consumption. URL/redirect metadata
// are constructor-inaccessible. Native-buffered bodies also retain the request's abort signal.
function withNetworkMetadata(response, metadata, cloneBody) {
  networkMetadata.set(response, metadata);
  Object.defineProperties(response, {
    url: {get: function () { return networkMetadata.get(this).url; }},
    redirected: {get: function () { return networkMetadata.get(this).redirected; }},
    type: {get: function () { return networkMetadata.get(this).type; }},
    clone: {value: function () {
      if (cloneBody) {
        if (this !== response || this.bodyUsed || this.body?.locked) {
          throw new TypeError("Response body is unavailable");
        }
        return cloneBody(this);
      }
      return withNetworkMetadata(responseClone.call(this), networkMetadata.get(this));
    }},
  });
  return response;
}

function networkResponse(bytes, init, metadata, signal) {
  const body = bytes === null ? null : new ReadableStream({
    start(controller) {
      this.abort = () => controller.error(abortFailure());
      if (signal.aborted) {
        controller.error(abortFailure());
        return;
      }
      signal.addEventListener("abort", this.abort, {once: true});
      // One queued chunk prevents speculative pull from finishing the body before it is read.
      // Once consumed, the normal pull closes the stream and releases the signal listener.
      controller.enqueue(bytes);
    },
    pull(controller) {
      signal.removeEventListener("abort", this.abort);
      controller.close();
    },
    cancel() {
      signal.removeEventListener("abort", this.abort);
    },
  });
  return withNetworkMetadata(new Response(body, init), metadata, original =>
    networkResponse(bytes?.slice() ?? null, {
      status: original.status, statusText: original.statusText, headers: original.headers,
    }, metadata, signal));
}

function networkURL(value, base) {
  const url = new URL(value, base);
  if (!["https:", "http:"].includes(url.protocol) || url.username || url.password ||
      new TextEncoder().encode(url.href).length > 8192) throw networkFailure();
  url.hash = "";
  return url;
}

async function nativeFetch(input, init) {
  let request;
  try {
    request = new Request(input, init);
    // The runtime's sealed assets never traverse the native network seam.
    if (new URL(request.url).protocol === "memoshi-pyodide:") return await sealedFetch(request);
    const cell = activeCell;
    if (!cell || !cellTaskExecuting() || request.mode === "no-cors" ||
        request.mode === "same-origin" || request.integrity) throw networkFailure();
    let url = networkURL(request.url);
    let method = request.method;
    const headers = new Headers(request.headers);
    let body = await boundedRequestBody(request);
    for (let hop = 0; hop < 10; hop++) {
      if (activeCell !== cell) throw networkFailure();
      if (request.signal.aborted) throw abortFailure();
      const response = await nativeCall(cell, "send", {
        url: url.href, method, headers: Object.fromEntries(headers), body: toBase64(body),
      }, request.signal);
      if (activeCell !== cell) throw networkFailure();
      if (request.signal.aborted) throw abortFailure();
      if (!response || !Number.isInteger(response.status) ||
          response.status < 200 || response.status > 599) throw networkFailure();
      const responseHeaders = new Headers(response.headers);
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        if (request.redirect === "error") throw networkFailure();
        if (request.redirect === "manual") {
          // Response.error supplies genuine status-0/null-body slots; this is the standard
          // unreadable manual-redirect result, never a fabricated successful HTTP response.
          return withNetworkMetadata(Response.error(), {url: "", redirected: false, type: "opaqueredirect"});
        }
        const location = responseHeaders.get("location");
        if (location !== null) {
          if (hop === 9) throw networkFailure();
          const next = networkURL(location, url);
          if (next.origin !== url.origin) headers.delete("authorization");
          if (([301, 302].includes(response.status) && method === "POST") ||
              (response.status === 303 && method !== "GET" && method !== "HEAD")) {
            method = "GET";
            body = new Uint8Array();
            for (const name of ["content-encoding", "content-language", "content-location", "content-type"]) {
              headers.delete(name);
            }
          }
          url = next;
          continue;
        }
      }
      const bytes = fromBase64(response.body);
      const noBody = method === "HEAD" || [204, 205, 304].includes(response.status);
      if (noBody && bytes.byteLength !== 0) throw networkFailure();
      return networkResponse(noBody ? null : bytes, {
        status: response.status, headers: responseHeaders,
      }, {url: url.href, redirected: hop > 0, type: "basic"}, request.signal);
    }
    throw networkFailure();
  } catch {
    if (request?.signal.aborted) throw abortFailure();
    throw networkFailure();
  }
}

function pathParts(path) {
  if (typeof path !== "string" || path.length === 0 || path.length > 1024 ||
      path.startsWith("/") || /[\\:\u0000-\u001f\u007f]/.test(path)) {
    throw new Error("unsafePath");
  }
  const parts = path.split("/");
  if (parts.length > 32 || parts.some(p => !p || p === "." || p === ".." || p.startsWith("~"))) {
    throw new Error("unsafePath");
  }
  return parts;
}

function fromBase64(text) {
  if (typeof text !== "string" || text.length > Math.ceil(fileLimit / 3) * 4) {
    throw new Error("outputLimit");
  }
  const raw = atob(text);
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}

function toBase64(bytes) {
  let result = "";
  for (let i = 0; i < bytes.length; i += 24576) {
    result += btoa(String.fromCharCode(...bytes.subarray(i, i + 24576)));
  }
  return result;
}

function removeTree(path) {
  for (const name of runtime.FS.readdir(path)) {
    if (name === "." || name === "..") continue;
    const child = path + "/" + name;
    const stat = runtime.FS.lstat(child);
    if (runtime.FS.isDir(stat.mode)) removeTree(child);
    else runtime.FS.unlink(child);
  }
  runtime.FS.rmdir(path);
}

function collectFile(work, relative) {
  let current = work;
  for (const component of pathParts(relative)) {
    current += "/" + component;
    const stat = runtime.FS.lstat(current);
    if (runtime.FS.isLink(stat.mode)) throw new Error("unsafePath");
  }
  const stat = runtime.FS.stat(current);
  if (!runtime.FS.isFile(stat.mode)) throw new Error("unsafePath");
  if (stat.size > fileLimit) throw new Error("outputLimit");
  return runtime.FS.readFile(current);
}

// Each cell decodes its own streams: bytes a cell leaves unfinished mid-character are flushed
// into that cell's result and never prefix a later cell's output.
function writer(kind) {
  return (bytes) => {
    if (!output) return bytes.length;
    output.byteCount += bytes.length;
    if (output.byteCount > textLimit) throw new Error("memoshi_output_limit");
    output[kind] += output.decoders[kind].decode(bytes, {stream: true});
    return bytes.length;
  };
}

// Cancels asyncio tasks a cell left pending and gives them one loop turn to observe it, in a
// scope the cell's globals cannot shadow. A task that suppresses cancellation is deliberate and
// is left to native limits.
const endCellSource = [
  "import asyncio",
  "_current = asyncio.current_task()",
  "_leftover = [t for t in asyncio.all_tasks() if t is not _current and not t.done()]",
  "for _task in _leftover:",
  "    _task.cancel()",
  "if _leftover:",
  "    await asyncio.sleep(0)",
].join("\n");

async function endCellTasks() {
  const scope = runtime.toPy({__name__: "_memoshi_cell_end"});
  try {
    await runtime.runPythonAsync(endCellSource, {globals: scope});
  } finally {
    scope.destroy();
  }
}

function clearCellTimers() {
  const owned = cellTimers;
  cellTimers = undefined;
  if (!owned) return;
  for (const id of owned) apply(nativeClearTimeout, globalThis, [id]);
}

async function boot() {
  const started = performance.now();
  const indexURL = new URL("./Runtime/", import.meta.url).href;
  const manifest = await (await fetch(indexURL + "manifest.json")).json();
  allowedPackages = new Set(manifest.packages.map(p => p.name));
  const lock = await (await fetch(indexURL + "pyodide-lock.json")).json();
  // No unbundled lock entry can trigger an implicit package download or CDN fallback.
  lock.packages = Object.fromEntries(Object.entries(lock.packages).filter(([name]) => allowedPackages.has(name)));
  helpers = await (await fetch(new URL("./cell-helpers.py", import.meta.url))).text();
  runtime = await loadPyodide({
    indexURL, packageBaseUrl: indexURL, lockFileContents: lock,
    stdLibURL: indexURL + "python_stdlib.zip", enableRunUntilComplete: false,
    // Documented loadPyodide jsglobals injection precedes any pyodide.http import. Inherited
    // globals preserve js.self access; its original fetch/XHR/imports remain CSP-confined.
    // https://pyodide.org/en/314.0.7/usage/api/js-api.html#exports.PyodideConfig.jsglobals
    jsglobals: Object.create(globalThis, {
      fetch: {value: nativeFetch, enumerable: true},
      // WorkerGlobalScope's self accessor requires a genuine receiver, not the inherited object.
      self: {value: globalThis, enumerable: true},
    }),
    env: {HOME: "/home/pyodide", MPLBACKEND: "Agg"},
  });
  const taskScope = runtime.toPy({__name__: "_memoshi_cell_tasks"});
  try {
    runtime.runPython(cellTaskSource, {globals: taskScope});
    startCell = taskScope.get("start");
    pyLoop = taskScope.get("loop");
    currentTask = taskScope.get("current_task");
    taskCoroutine = taskScope.get("task_coroutine");
    coroutineRunning = taskScope.get("coroutine_running");
    typeOf = taskScope.get("type_of");
    identity = taskScope.get("identity");
    const coroutineType = taskScope.get("coroutine_type");
    coroutineTypeID = identity(coroutineType);
    coroutineType.destroy();
    const install = taskScope.get("install");
    install(recordCellTask);
    install.destroy();
  } finally {
    taskScope.destroy();
  }
  const coreSeconds = (performance.now() - started) / 1000;
  post({kind: "coreReady", coreSeconds});
  const scientificStarted = performance.now();
  // Swift hashes every sealed resource against the pinned manifest before this realm exists.
  // Use that single authority; custom schemes need not expose secure-context crypto.subtle.
  await runtime.loadPackage(roots, {checkIntegrity: false});
  runtime.runPython("import numpy, pandas, scipy, matplotlib\nmatplotlib.use('Agg', force=True)");
  runtime.setStdout({write: writer("stdout")});
  runtime.setStderr({write: writer("stderr")});
  post({kind: "ready", coreSeconds,
    scientificStackSeconds: (performance.now() - scientificStarted) / 1000,
    versions: Object.fromEntries(manifest.packages.map(p => [p.name, p.version]))});
}

async function execute(request) {
  const id = request.id;
  if (running || !runtime) {
    post({kind: "failure", id, generation: request.generation, failure: "busy"});
    return;
  }
  running = true;
  cellTimers = new Set();
  const cell = {cellID: id, generation: request.generation};
  activeCell = cell;
  output = {stdout: "", stderr: "", byteCount: 0,
    decoders: {stdout: new NativeTextDecoder(), stderr: new NativeTextDecoder()}};
  const started = performance.now();
  const work = "/home/pyodide/cell-" + id;
  let globals;
  let result;
  try {
    runtime.FS.mkdir(work);
    runtime.FS.chdir(work);
    let inputBytes = 0;
    for (const input of request.inputs) {
      const parts = pathParts(input.path);
      const bytes = fromBase64(input.bytes);
      inputBytes += bytes.length;
      if (inputBytes > totalFileLimit) throw new Error("outputLimit");
      let directory = work;
      for (const part of parts.slice(0, -1)) {
        directory += "/" + part;
        if (!runtime.FS.analyzePath(directory).exists) runtime.FS.mkdir(directory);
        if (!runtime.FS.isDir(runtime.FS.lstat(directory).mode)) throw new Error("unsafePath");
      }
      runtime.FS.writeFile(work + "/" + input.path, bytes, {flags: exclusiveInputFlags});
    }
    globals = runtime.toPy({__name__: "__main__"});
    runtime.runPython(helpers, {globals});
    post({kind: "executing", id, generation: cell.generation});
    cellTasks = new NativeMap();
    const task = startCell(request.code, globals);
    mapSet(cellTasks, identity(task), task.copy());
    let returned;
    try {
      returned = await task;
    } finally {
      task.destroy();
    }
    if (returned && typeof returned.destroy === "function") returned.destroy();
    const scientific = JSON.parse(runtime.runPython("_memoshi_results()", {globals}));
    let outputBytes = 0;
    const files = request.outputs.map(path => {
      const bytes = collectFile(work, path);
      outputBytes += bytes.length;
      if (outputBytes > totalFileLimit) throw new Error("outputLimit");
      return {path, bytes: toBase64(bytes)};
    });
    result = {kind: "result", id, stdout: output.stdout + output.decoders.stdout.decode(),
      stderr: output.stderr + output.decoders.stderr.decode(),
      tables: scientific.tables, figures: scientific.figures, files,
      elapsedSeconds: (performance.now() - started) / 1000};
  } catch (error) {
    const message = String(error);
    const failure = message.includes("memoshi_output_limit") || message.includes("outputLimit") ? "outputLimit" :
      message.includes("unsafePath") ? "unsafePath" : "scriptFailed";
    // No source, file contents, exception body or network credentials in native failure state.
    result = {kind: "failure", id, failure};
  } finally {
    try {
      // Failing this hygiene fails the cell, so native discards the realm instead of keeping
      // unknown leftovers alive.
      await endCellTasks();
    } catch {
      result = {kind: "failure", id, failure: "scriptFailed"};
    }
    clearCellTimers();
    endCellTaskRecord();
    activeCell = undefined;
    try {
      // Native also retires on result reception, so bypassing this adapter cannot leave a send
      // alive after cell completion. Await this drain on the ordinary worker path as well.
      await nativeCall(cell, "end");
    } catch {
      result = {kind: "failure", id, failure: "scriptFailed"};
    }
    try {
      // Avoid cold-importing matplotlib.pyplot in cleanup (~0.5–2.6 s on the first cell when a
      // cell never imported pyplot, so no figures can be open).
      runtime.runPython(
        "import sys as _sys\n_p = _sys.modules.get('matplotlib.pyplot')\nif _p is not None:\n    _p.close('all')");
      globals?.destroy();
      runtime.FS.chdir("/home/pyodide");
      removeTree(work);
    } catch {
      result = {kind: "failure", id, failure: "scriptFailed"};
    }
    running = false;
    output = undefined;
  }
  post({...result, generation: cell.generation});
}

// Native supplies structured arguments, never an interpolated JavaScript source program. The
// connection precedes every interpreter message; control then flows only through hostPort.
self.postMessage({kind: "connect"}, [hostChannel.port2]);
void boot().catch(() => post({kind: "failure", failure: "startupFailed"}));
