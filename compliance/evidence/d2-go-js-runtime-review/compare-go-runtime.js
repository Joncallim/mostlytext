const fs = require('fs');
const crypto = require('crypto');
const acorn = require('./js-tokenizer/node_modules/acorn');
const root = process.argv[2] || __dirname;
function sha(data) { return crypto.createHash('sha256').update(data).digest('hex'); }
function ast(file) {
  const raw = fs.readFileSync(root + '/' + file);
  return {raw, ast: acorn.parse(raw.toString('utf8'), {ecmaVersion: 2024, sourceType: 'script'})};
}
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
function differences(a, b, path = '$', found = []) {
  if (typeof a !== typeof b || a === null || b === null || typeof a !== 'object') {
    if (a !== b) found.push({path, d2: a, go: b});
    return found;
  }
  if (Array.isArray(a) !== Array.isArray(b)) { found.push({path, d2: a, go: b}); return found; }
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const key of keys) differences(a[key], b[key], path + '.' + key, found);
  return found;
}
function normalize(value) {
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === 'object') {
    const result = {};
    for (const [key, member] of Object.entries(value)) result[key] = normalize(member);
    if (result.type === 'Property' && result.computed === false && result.key?.type === 'Identifier') {
      result.key = {type: 'Literal', value: result.key.name};
    }
    return result;
  }
  return value;
}
const d2 = ast('d2-wasm_exec.js');
const go = ast('go1.24.6-wasm_exec.js');
const left = clean(d2.ast), right = clean(go.ast);
const rawDifferences = differences(left, right);
const normalizedLeft = JSON.stringify(normalize(left)), normalizedRight = JSON.stringify(normalize(right));
const report = {
  schema: 1,
  parser: 'acorn', parserVersion: require('./js-tokenizer/node_modules/acorn/package.json').version,
  parserNpmIntegrity: 'sha512-cl669nCJTZBsL97OF4kUQm5g5hC2uihk0NxY3WENAC0TYdILVkAyHymAntgxGkl7K+t0cXIrH5siy5S4XkFycA==',
  d2: {path: 'd2js/js/wasm/wasm_exec.js', sourceCommit: '581c91096b62d644fb5168313142c836b7e68e74', bytes: d2.raw.length, sha256: sha(d2.raw)},
  go: {path: 'go/lib/wasm/wasm_exec.js', version: 'go1.24.6', bytes: go.raw.length, sha256: sha(go.raw)},
  astWithoutLocationRawDifferences: rawDifferences,
  normalizedPropertyKeyAstSha256: sha(normalizedLeft),
  normalizedPropertyKeyAstEqual: normalizedLeft === normalizedRight,
  limits: 'AST equality is technical behavior evidence; it does not identify a unique historical copying event or cover generated source obligations.'
};
if (!report.normalizedPropertyKeyAstEqual) throw new Error('Go/D2 AST differs after key normalization');
console.log(JSON.stringify(report, null, 2));
