// Fixed-input diagnostic host, not a production Worker or cancellation boundary.
(() => {
  'use strict';
  __hostStage('host-start');
  globalThis.window = globalThis;
  globalThis.performance = {now: () => __hostNow() * 1000};
  globalThis.console = {log() {}, warn() {}, error() {}};
  globalThis.atob = value => __hostAtob(String(value));
  globalThis.btoa = value => __hostBtoa(String(value));
  globalThis.TextEncoder = class {
    encode(value = '') { return Uint8Array.from(__hostEncode(String(value))); }
  };
  globalThis.TextDecoder = class {
    constructor(label = 'utf-8') {
      if (!['utf-8', 'utf8'].includes(label.toLowerCase())) throw Error('Unsupported encoding');
    }
    decode(value = new Uint8Array()) {
      const bytes = value instanceof ArrayBuffer ? new Uint8Array(value)
        : new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
      return __hostDecode(Array.from(bytes));
    }
  };
  globalThis.crypto = {getRandomValues(array) {
    if (!(array instanceof Uint8Array) || array.byteLength > 65536) throw Error('Random byte boundary');
    array.set(__hostRandom(array.byteLength)); return array;
  }};
  let nextTimer = 0;
  const timers = new Map();
  globalThis.setTimeout = (callback, delay = 0, ...args) => {
    if (typeof callback !== 'function' || timers.size >= 1024) throw Error('Timer boundary');
    const id = ++nextTimer;
    timers.set(id, {callback: () => callback(...args), due: __hostNow() + Math.max(0, Number(delay)) / 1000});
    return id;
  };
  globalThis.clearTimeout = id => timers.delete(id);
  globalThis.__hostTick = () => {
    const now = __hostNow();
    for (const [id, timer] of Array.from(timers)) {
      if (timer.due <= now && timers.delete(id)) timer.callback();
    }
  };
  const urls = new Map(); let nextURL = 0;
  globalThis.Blob = class {constructor(parts) {this.parts = parts;}};
  globalThis.URL = {createObjectURL(blob) {
    if (!(blob instanceof Blob) || urls.size >= 4) throw Error('Blob boundary');
    const key = 'fixed-diagnostic-blob:' + (++nextURL); urls.set(key, blob); return key;
  }};
  function clone(value) {
    if (value instanceof ArrayBuffer) return value.slice(0);
    if (value instanceof Uint8Array) return value.slice();
    if (Array.isArray(value)) return value.map(clone);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,clone(v)]));
    return value;
  }
  let workers = 0;
  globalThis.Worker = class {
    constructor(url, options) {
      if (++workers !== 1 || options?.type !== 'module') throw Error('One fixed module worker only');
      const blob = urls.get(url);
      if (!blob || blob.parts.length !== 2 || !blob.parts.every(p => typeof p === 'string')) throw Error('Unknown bundled worker');
      const [go, original] = blob.parts;
      const declarations = ['export let BrotliDecode =', 'export function setupMessageHandler('];
      if (!declarations.every(token => original.split(token).length === 2)) throw Error('Unknown worker module declarations');
      let transformed = original;
      for (const token of declarations) transformed = transformed.replace(token, token.slice(7));
      __hostWorkerTransform(original, transformed);
      this.endpoint = Object.create(globalThis);
      this.endpoint.postMessage = value => {
        const copied = clone(value);
        setTimeout(() => this.onmessage?.({data: copied}), 0);
      };
      __hostStage('worker-go-start');
      new Function('self', go).call(this.endpoint, this.endpoint);
      __hostStage('worker-go-end');
      __hostStage('worker-module-start');
      new Function('self', transformed).call(this.endpoint, this.endpoint);
      __hostStage('worker-module-end');
    }
    postMessage(value) {
      const copied = clone(value);
      setTimeout(() => {
        try {
          __hostStage('message-' + copied.type + '-start');
          this.endpoint.onmessage({data: copied});
          __hostStage('message-' + copied.type + '-return');
        }
        catch (error) { this.onerror?.(error); throw error; }
      }, 0);
    }
  };
  const roundtrip = 'ASCII π 😀\u0000';
  if (new TextDecoder().decode(new TextEncoder().encode(roundtrip)) !== roundtrip) throw Error('UTF8 control failed');
  if (atob(btoa('\u0000\u007f\u0080\u00ff')) !== '\u0000\u007f\u0080\u00ff') throw Error('Base64 control failed');
  const random = crypto.getRandomValues(new Uint8Array(32));
  if (random.length !== 32) throw Error('Random control failed');
  globalThis.__hostControls = {utf8: true, base64: true, randomBytes: random.length, timer: false};
  setTimeout(() => { __hostControls.timer = true; }, 0);
  __hostStage('host-end');
})();
