import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  throw new Error('usage: node stream_d2_browser.mjs SPLIT_BROWSER OUTPUT_BROWSER');
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

const original = readFileSync(input);
if (sha256(original) !== '10d9bd5f664ee131783df6c39fc864452758ba8b7e39e05998fec81658426a1c') {
  throw new Error('input is not the reviewed split D2 browser resource');
}

let browser = original.toString('utf8');
const edits = [
  [
    'async function Bf(){let r=await fetch("./d2.wasm");return new Uint8Array(await r.arrayBuffer())}',
    'async function Bf(){return WebAssembly.compileStreaming(fetch("./d2.wasm"))}',
  ],
  [
    'go.run(result.instance);',
    'go.run(result.instance ?? result);',
  ],
];
for (const [before, after] of edits) {
  if (browser.split(before).length !== 2) {
    throw new Error(`expected one exact occurrence of ${before}`);
  }
  browser = browser.replace(before, after);
}
const bytes = Buffer.from(browser);
writeFileSync(output, bytes);
console.log(`browser ${bytes.length} bytes sha256 ${sha256(bytes)}`);
