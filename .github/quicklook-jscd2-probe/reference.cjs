// Guarded-host reference only. Never bundled as product code or executed locally.
const fs = require('node:fs'), vm = require('node:vm'), crypto = require('node:crypto');
const path = require('node:path');
const fixture = process.argv[2];
const transformed = [];
const phases = [];
const stage = name => {
  if (!/^[a-z0-9-]{1,48}$/.test(name) || phases.length >= 32) throw Error('Phase boundary');
  phases.push({phase: name, uptime_ms: performance.now()});
  fs.writeFileSync(path.join(fixture, '..', 'reference-phases.json'), JSON.stringify(phases, null, 2));
};
const context = vm.createContext({
  __hostStage: stage,
  __hostNow: () => performance.now() / 1000,
  __hostEncode: text => Array.from(Buffer.from(text, 'utf8')),
  __hostDecode: bytes => Buffer.from(bytes).toString('utf8'),
  __hostAtob: text => Buffer.from(text, 'base64').toString('latin1'),
  __hostBtoa: text => Buffer.from(text, 'latin1').toString('base64'),
  __hostRandom: count => Array.from(crypto.randomBytes(count)),
  __hostWorkerTransform: (original, changed) => transformed.push({
    original_sha256: crypto.createHash('sha256').update(original).digest('hex'),
    transformed_sha256: crypto.createHash('sha256').update(changed).digest('hex')
  })
}, {microtaskMode: 'afterEvaluate'});
const assets = {};
for (const name of ['host', 'd2-browser', 'control']) {
  const bytes = fs.readFileSync(path.join(fixture, 'Resources', name + '.js'));
  assets[name] = crypto.createHash('sha256').update(bytes).digest('hex');
  stage('asset-' + name + '-start');
  vm.runInContext(bytes.toString('utf8'), context, {timeout: 15000, filename: name + '.js'});
  stage('asset-' + name + '-end');
}
(async () => {
  const stop = performance.now() + 15000;
  while (!context.__d2Result && performance.now() < stop) {
    vm.runInContext('__hostTick()', context, {timeout: 15000});
    await new Promise(resolve => setImmediate(resolve));
  }
  const result = context.__d2Result;
  if (!result?.ok || transformed.length !== 1 || !result.controls.timer) throw Error(JSON.stringify(result));
  const svg = result.svg;
  if (Buffer.byteLength(svg) > 65536) throw Error('SVG byte boundary');
  process.stdout.write(JSON.stringify({engine: process.version, assets, worker_transform: transformed[0],
    svg_bytes: Buffer.byteLength(svg), svg_sha256: crypto.createHash('sha256').update(svg).digest('hex'),
    controls: result.controls, real_d2_svg: true, diagnostic_only: true, qualification_candidate: false}));
})().catch(error => {console.error(error.stack);process.exitCode = 1;});
