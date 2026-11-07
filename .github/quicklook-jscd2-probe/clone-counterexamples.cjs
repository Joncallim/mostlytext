// Hosted-only counterexamples of the verbatim copied host function, not a replacement implementation.
const fs = require('node:fs'), vm = require('node:vm'), crypto = require('node:crypto');
const source = fs.readFileSync(process.argv[2], 'utf8');
const begin = source.indexOf('  function clone(value) {');
const end = source.indexOf('  let workers = 0;', begin);
if (begin < 0 || end < 0 || source.indexOf('  function clone(value) {', begin + 1) !== -1) throw Error('Unknown actual clone boundary');
const actual = source.slice(begin, end);
const program = actual + `
const constructors = [Int8Array, Uint8Array, Uint8ClampedArray, Int16Array, Uint16Array,
  Int32Array, Uint32Array, Float32Array, Float64Array, BigInt64Array, BigUint64Array, DataView];
const results = constructors.map(Constructor => {
  const buffer = new ArrayBuffer(24);
  new Uint8Array(buffer).set([0,128,255,127,85,170,1,0,255,127,128,0,85,170,17,238,1,2,3,4,5,6,7,8]);
  const value = Constructor === DataView ? new DataView(buffer, 8, 8) : new Constructor(buffer, 8, 1);
  const expectedBytes = Array.from(new Uint8Array(buffer, value.byteOffset, value.byteLength));
  const copied = clone(value);
  const copiedKind = Object.prototype.toString.call(copied).slice(8,-1);
  const copiedBytes = ArrayBuffer.isView(copied)
    ? Array.from(new Uint8Array(copied.buffer, copied.byteOffset, copied.byteLength)) : null;
  return {kind: Constructor.name, copiedKind, expectedBytes, copiedBytes,
    passed: copied.constructor === Constructor && JSON.stringify(copiedBytes) === JSON.stringify(expectedBytes)};
});
JSON.stringify(results);`;
const results = JSON.parse(vm.runInNewContext(program, {}, {timeout: 1000}));
process.stdout.write(JSON.stringify({actual_function_sha256: crypto.createHash('sha256').update(actual).digest('hex'),
  cases: results, passed: results.filter(x=>x.passed).length, failed: results.filter(x=>!x.passed).length,
  scope: 'Tiny actual-host clone counterexamples only; not renderer or native acceptance'}));
