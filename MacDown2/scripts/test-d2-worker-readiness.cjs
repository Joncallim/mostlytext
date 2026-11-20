// Exercise the shipped harness glue without starting WebKit or the app.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { Worker: Thread } = require('node:worker_threads');

const source = fs.readFileSync(path.resolve(__dirname,
    '../Packages/MacDownKit/Sources/D2Rendering/Resources/render.js'), 'utf8');

async function run(firstFails, secondFails) {
    const engines = [];
    const window = {};
    window.D2 = class {
        constructor() {
            this.number = engines.length;
            this.ready = Promise.resolve();
            this.worker = { terminated: false, terminate() { this.terminated = true; } };
            engines.push(this);
        }
        async version() {
            if ((this.number === 0 && firstFails) || (this.number === 1 && secondFails)) {
                throw new Error("undefined is not an object (evaluating 'd2.version')");
            }
            return '0.1.33';
        }
    };
    vm.runInNewContext(source, { window });
    const result = await window.__macdownPrepareD2();
    return { result, engines };
}

async function main() {
    const normal = await run(false, false);
    assert.equal(normal.result.ok, true);
    assert.equal(normal.engines.length, 1);
    assert.equal(normal.engines[0].worker.terminated, false);

    const recovered = await run(true, false);
    assert.equal(recovered.result.ok, true);
    assert.equal(recovered.engines.length, 2);
    assert.equal(recovered.engines[0].worker.terminated, true);
    assert.equal(recovered.engines[1].worker.terminated, false);

    const failed = await run(true, true);
    assert.equal(failed.result.ok, false);
    assert.equal(failed.engines.length, 2);
    assert.equal(failed.engines[0].worker.terminated, true);
    assert.equal(failed.engines[1].worker.terminated, true);

    // Also run the exact bundled worker and WASM through the Node bridge.
    // This proves that the additional readiness request is supported by the
    // pinned runtime, while the synthetic cases control the early-ready race.
    const blobs = new Map();
    const workers = [];
    let nextBlob = 0;
    global.window = global;
    URL.createObjectURL = blob => {
        const url = `blob:${++nextBlob}`;
        blobs.set(url, blob);
        return url;
    };
    global.Worker = class {
        constructor(url) {
            this.pending = [];
            blobs.get(url).text().then(workerSource => {
                this.thread = new Thread(`import {parentPort} from 'node:worker_threads';
                    globalThis.self = globalThis;
                    self.postMessage = data => parentPort.postMessage(data);
                    parentPort.on('message', data => self.onmessage({data}));\n` +
                    workerSource.replace('export function setupMessageHandler', 'function setupMessageHandler'),
                { eval: true });
                workers.push(this.thread);
                this.thread.on('message', data => this.onmessage({ data }));
                this.thread.on('error', error => { throw error; });
                this.pending.forEach(data => this.thread.postMessage(data));
            });
        }
        postMessage(data) { this.thread ? this.thread.postMessage(data) : this.pending.push(data); }
        terminate() { return this.thread?.terminate(); }
    };
    try {
        const browser = fs.readFileSync(path.resolve(__dirname,
            '../Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js'), 'utf8');
        vm.runInThisContext(browser, { filename: 'd2-browser.js' });
        vm.runInThisContext(source, { filename: 'render.js' });
        const ready = await Promise.race([
            __macdownPrepareD2(),
            new Promise((_, reject) => {
                const timer = setTimeout(() => reject(new Error('D2 preparation timed out')), 20000);
                timer.unref();
            })
        ]);
        assert.equal(ready.ok, true, ready.message);
    } finally {
        await Promise.all(workers.map(worker => worker.terminate()));
    }
    console.log('PASS D2 worker readiness and bounded recovery');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
