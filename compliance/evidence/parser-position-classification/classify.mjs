// Audit-only recipe: use an explicit integrity-verified Acorn module, never app code.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';

const sha = b => createHash('sha256').update(b).digest('hex');
const [parserPath, parserSHA, indexPath, membersPath, outputPath] = process.argv.slice(2);
assert.equal(process.version, 'v24.16.0');
assert.equal(parserSHA, '76254fc76529713b4dfd2532972d17a991ffd9aafeebb1f977445b5506b9fb0b');
assert.equal(sha(readFileSync(parserPath)), parserSHA, 'Acorn module identity');
const { parse, version } = await import(pathToFileURL(path.resolve(parserPath)).href);
assert.equal(version, '8.19.0');

function analyze(code) {
  const tokens = [], comments = [];
  const tree = parse(code, {ecmaVersion: 2025, sourceType: 'module', locations: true,
    onToken: tokens, onComment: comments});
  const regions = [], stack = [{node: tree, parent: null}];
  while (stack.length) {
    const {node, parent} = stack.pop();
    let category;
    if (node.type === 'ImportDeclaration') category = 'import-declaration';
    if (node.type === 'ExpressionStatement' && node.expression.type === 'CallExpression') {
      const call = node.expression;
      if (call.callee.type === 'Identifier' && call.callee.name === '__export'
          && call.arguments.length === 2 && call.arguments[0].type === 'Identifier'
          && call.arguments[1].type === 'ObjectExpression'
          && call.arguments[1].properties.length > 0
          && call.arguments[1].properties.every(p => p.type === 'Property' && !p.computed
            && p.kind === 'init' && !p.method && p.key.type === 'Identifier'
            && p.value.type === 'ArrowFunctionExpression' && !p.value.async
            && p.value.params.length === 0 && p.value.body.type === 'Identifier')) {
        category = 'namespace-export-bindings';
      }
      if (parent?.type === 'StaticBlock' && parent.body.length === 1
          && call.callee.type === 'Identifier' && call.callee.name === '__name'
          && call.arguments.length === 2 && call.arguments[0].type === 'ThisExpression'
          && call.arguments[1].type === 'Literal' && typeof call.arguments[1].value === 'string'
          && /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(call.arguments[1].value)) {
        category = 'static-name-retention-call';
      }
    }
    if (category) regions.push({start:node.start, end:node.end, category});
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) {
        for (const child of value) if (child && typeof child.type === 'string') stack.push({node:child,parent:node});
      } else if (value && typeof value.type === 'string') stack.push({node:value,parent:node});
    }
  }
  const lines = code.split('\n'), starts = [0];
  for (let i=0; i<code.length; i++) if (code[i] === '\n') starts.push(i+1);
  const covering = new Map();
  for (const token of [...tokens,...comments]) {
    if (token.start === token.end) continue; // EOF contains no source characters.
    const lastLine = token.loc.end.line - (token.loc.end.column === 0 ? 1 : 0);
    for (let line=token.loc.start.line; line<=lastLine; line++) {
      if (!covering.has(line)) covering.set(line, []);
      covering.get(line).push(token);
    }
  }
  const punctuation = new Set(['{','}','(',')','[',']',',',';']);
  return (line, column) => {
    assert(Number.isInteger(line) && Number.isInteger(column) && line > 0 && column > 0);
    assert(line <= lines.length && column <= lines[line-1].length+1, 'UTF-16 coordinate bounds');
    const offset = starts[line-1] + column-1;
    const region = regions.find(r => r.start <= offset && offset < r.end);
    if (region) return region.category;
    const onLine = covering.get(line) || [];
    if (/^[\s{}\[\](),;]+$/.test(lines[line-1]) && onLine.length > 0
        && onLine.every(t => t.type && punctuation.has(t.type.label))) return 'syntax-only-line';
    return 'unclassified';
  };
}

// Actual parser controls, including lookalikes that a line regex would misclassify.
const controls = [
  ['import {x} from "./x.mjs";',1,1,'import-declaration'],
  ['__export(out, { x: () => x });',1,1,'namespace-export-bindings'],
  ['__export(out, { x: () => sideEffect() });',1,1,'unclassified'],
  ['class C { static { __name(this, "C"); } }',1,20,'static-name-retention-call'],
  ['class C { static { __name(this, getName()); } }',1,20,'unclassified'],
  ['class C { static { __name(this, "C"); sideEffect(); } }',1,20,'unclassified'],
  ['const x = {\n};',2,1,'syntax-only-line'],
  ['const x = `\n});\n`;',2,1,'unclassified'],
  ['/*\n});\n*/',2,1,'unclassified'],
  ['const x = "😀"; __export(out, { x: () => x });',1,17,'namespace-export-bindings'],
  ['const x = "😀"; sideEffect();',1,17,'unclassified'],
];
for (const [code,line,column,wanted] of controls) assert.equal(analyze(code)(line,column),wanted,code);

const rawIndex = readFileSync(indexPath), index = JSON.parse(rawIndex);
assert.equal(sha(rawIndex), '4137239965a49864f71dc3ecbce8dfc04833731c0e92a55cd2dd44b6a9958ec3', 'Original review index identity');
const cache = new Map(), categories = {}, positions = [];
for (const [original_row_index,row] of index.positions.entries()) {
  if (row.classification !== 'requires-independent-review') continue;
  assert(row.parser_member.startsWith('dist/') && !row.parser_member.split('/').includes('..'));
  if (!cache.has(row.parser_member)) {
    const body = readFileSync(path.join(membersPath,row.parser_member));
    assert.equal(sha(body),row.parser_member_sha256,'published/reproduced member');
    cache.set(row.parser_member,analyze(body.toString('utf8')));
  }
  const category = cache.get(row.parser_member)(row.parser_line,row.parser_utf16_column);
  categories[category] = (categories[category] || 0) + row.outer_reference_count;
  const canonical = Object.fromEntries(Object.keys(row).sort().map(k => [k,row[k]]));
  positions.push({original_row_index, original_row_sha256:sha(JSON.stringify(canonical)),
    technical_category:category});
}
const result = {schema:1, scope:'Syntax classification only; all original positions retain independent review requirements',
  original_index_sha256:sha(rawIndex), parser:'acorn@8.19.0', parser_module_sha256:parserSHA,
  node:process.version, parser_controls:controls.length, independent_review_required:true,
  total_references:index.remaining_review_required_references, categories, positions};
writeFileSync(outputPath,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({positions:positions.length,categories,parserControls:controls.length}));
