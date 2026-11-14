const fs = require('fs');
const crypto = require('crypto');
const acorn = require('../d2-go-js-runtime-review/js-tokenizer/node_modules/acorn');
const root = process.argv[2] || __dirname;
function sha(body) { return crypto.createHash('sha256').update(body).digest('hex'); }
function clean(value) {
  if (Array.isArray(value)) return value.map(clean);
  if (value && typeof value === 'object') {
    const result = {};
    for (const [key, member] of Object.entries(value)) {
      if (key === 'start' || key === 'end' || key === 'raw') continue;
      result[key] = clean(member);
    }
    return result;
  }
  return value;
}
function read(name, expected) {
  const raw = fs.readFileSync(root + '/' + name);
  if (sha(raw) !== expected) throw new Error('source digest changed: ' + name);
  return {raw, ast: clean(acorn.parse(raw.toString('utf8'), {ecmaVersion: 2024, sourceType: 'module'}))};
}
const d2 = read('d2-decode.min.js', '67de1ff9e3bf170ca99d317a6466cb107f288a1f565f3971cd7dd8dc9922f677');
const google = read('google-decode.min.js', '2055420568c3701fdd83a53f6bd0fb8d7f3352b571f3057eedaf555e750f8235');
const d2ast = JSON.stringify(d2.ast), googleast = JSON.stringify(google.ast);
const report = {
  schema: 1, parser: 'acorn', parserVersion: require('../d2-go-js-runtime-review/js-tokenizer/node_modules/acorn/package.json').version,
  parserNpmIntegrity: 'sha512-cl669nCJTZBsL97OF4kUQm5g5hC2uihk0NxY3WENAC0TYdILVkAyHymAntgxGkl7K+t0cXIrH5siy5S4XkFycA==',
  d2: {path: 'd2js/js/vendor/decode.min.js', sourceCommit: '581c91096b62d644fb5168313142c836b7e68e74', bytes: d2.raw.length, sha256: sha(d2.raw)},
  google: {path: 'js/decode.min.js', sourceCommit: '3efb30f96ba50389c4a2fcd9f884b7dbfbadebae', sourceTree: '98bf174cfe47330ba0ad0db0ad96224830ef1588', bytes: google.raw.length, sha256: sha(google.raw)},
  astSha256: sha(d2ast), astEqual: d2ast === googleast,
  limits: 'AST equality after removing location/raw fields is technical source correspondence, not byte equality, historical copying proof, a legal opinion, publisher build reproduction, or proof of all nested obligations.'
};
if (!report.astEqual) throw new Error('D2 and Google decoder ASTs differ');
console.log(JSON.stringify(report, null, 2));
