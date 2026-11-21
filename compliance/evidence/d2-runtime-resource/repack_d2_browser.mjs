import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { brotliDecompressSync } from 'node:zlib';

const [input, browserOutput, wasmOutput] = process.argv.slice(2);
if (!input || !browserOutput || !wasmOutput) {
  throw new Error('usage: node repack_d2_browser.mjs ORIGINAL_BROWSER OUTPUT_BROWSER OUTPUT_WASM');
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

const original = readFileSync(input);
if (sha256(original) !== 'ef6d450712e4356ccdd5e9e3a732c4b9a761ac69ab7a71407012ad36dcf49fd0') {
  throw new Error('input is not the reviewed font-replacement browser resource');
}
const source = original.toString('utf8');
const start = source.indexOf('fw="') + 4;
const end = source.indexOf('";function Bf()', start);
if (start < 4 || end < start || source.indexOf('";function Bf()', end + 1) !== -1) {
  throw new Error('compressed WASM literal is not unique');
}
const compressed = Buffer.from(source.slice(start, end), 'base64');
if (sha256(compressed) !== '4527d5ef715dd3212b6a717daa336755d8b8e1d717280b004c46f1994257d085') {
  throw new Error('compressed WASM differs from the reviewed build');
}
const wasm = brotliDecompressSync(compressed);
if (sha256(wasm) !== '175e672a9a6c939a65363c50e4092c7c217add5f9a0fb91364e906a9b137586e') {
  throw new Error('extracted WASM differs from the reviewed build');
}

const loaderBefore = 'function Bf(){let r=Uint8Array.from(atob(fw),(K)=>K.charCodeAt(0));return $f(r)}';
const loaderAfter = 'async function Bf(){let r=await fetch("./d2.wasm");return new Uint8Array(await r.arrayBuffer())}';
if (source.split(loaderBefore).length !== 2) throw new Error('browser loader is not unique');
const browser = (source.slice(0, start) + source.slice(end)).replace(loaderBefore, loaderAfter);
writeFileSync(browserOutput, browser);
writeFileSync(wasmOutput, wasm);
console.log(`browser ${Buffer.byteLength(browser)} bytes sha256 ${sha256(Buffer.from(browser))}`);
console.log(`WASM ${wasm.length} bytes sha256 ${sha256(wasm)}`);
