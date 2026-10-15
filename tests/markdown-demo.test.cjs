// Run: node tests/markdown-demo.test.cjs (no extra test dependencies).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const compiled = ts.transpileModule(fs.readFileSync('src/MarkdownDemo.tsx', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2022 },
}).outputText;
const moduleOutput = { exports: {} };
vm.runInNewContext(compiled, { exports: moduleOutput.exports, require });
const { MarkdownPreview, DEMO_LIMIT } = moduleOutput.exports;
const render = source => renderToStaticMarkup(React.createElement(MarkdownPreview, { source }));
assert.match(render('# Heading'), /<h1>Heading<\/h1>/);
assert.match(render('**bold** *em* `code`'), /<strong>bold<\/strong> <em>em<\/em> <code>code<\/code>/);
assert.equal(render('**bold**'), '<p><strong>bold</strong></p>');
assert.equal((render('- first\n- second').match(/<li>/g)||[]).length, 2);
assert.match(render('1. first\n2. second'), /^<ol>/);
assert.match(render('> quote\n> continues'), /<blockquote>quote continues<\/blockquote>/);
assert.match(render('```html\n<img src=x>\n```'), /<pre><code>&lt;img src=x&gt;<\/code><\/pre>/);
assert.match(render(''), /Your preview starts/);
assert.match(render('## Windows\r\n\r\nParagraph'), /<h2>Windows<\/h2><p>Paragraph<\/p>/);
const attacks = [
 '<script>alert(1)</script>',
 '<img src="https://attacker.invalid/leak" onerror="alert(1)">',
 '<svg onload="alert(1)"></svg>',
 '<iframe srcdoc="<script>alert(1)</script>"></iframe>',
 '<style>body{background:url(https://attacker.invalid/css)}</style>',
 '<form action="https://attacker.invalid"><input autofocus></form>',
 '[JS](javascript:alert(1))', '[encoded](java&#x73;cript:alert(1))',
 '[data](data:text/html,evil)', '[file](file:///private)',
 '[proto](//attacker.invalid/path)', '[https](https://attacker.invalid/path)',
 '![track](https://attacker.invalid/leak)', '![svg](data:image/svg+xml,bad)',
 '<a href="javascript:alert(1)">x</a>',
 '[reference][track]\n\n[track]: https://attacker.invalid',
 '<https://attacker.invalid/auto>',
];
for (const attack of attacks) {
 const html = render(attack);
 assert.doesNotMatch(html, /<(?:script|img|svg|iframe|style|form|input|a|object|embed)\b/i, attack);
 // Escaped raw HTML can include attribute text, but no rendered tag can.
 assert.doesNotMatch(html, /<[^>]*\s(?:href|src|srcdoc|onerror|onload|style)=/i, attack);
}
assert.equal(render('a'.repeat(DEMO_LIMIT + 1)), '<p>'+'a'.repeat(DEMO_LIMIT)+'</p>');
const started = performance.now();
for (const length of [1000, 6000, DEMO_LIMIT]) {
  for (const source of ['['.repeat(length), '!['.repeat(Math.floor(length / 2)), '[label]('.repeat(Math.floor(length / 8)), '[x]('.repeat(Math.floor(length / 4)) + '**bold**', '[['.repeat(Math.floor(length / 2)) + '[x](unterminated']) render(source);
}
for (const source of ['*'.repeat(DEMO_LIMIT), '\\'.repeat(DEMO_LIMIT), '`'.repeat(DEMO_LIMIT), '\n'.repeat(DEMO_LIMIT), '# x\n'.repeat(DEMO_LIMIT/4), '# \n## \n>\n- \n1. \n```\n'.repeat(500)]) render(source);
assert(performance.now() - started < 5000, 'Bounded adversarial inputs exceeded five seconds');
console.log(`PASS: Markdown blocks/inlines, empty/CRLF, ${attacks.length} adversarial HTML/URL/image cases, ${DEMO_LIMIT}-character cap, bounded parser stress (${Math.round(performance.now()-started)} ms).`);
