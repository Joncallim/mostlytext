// Run: node tests/route.test.cjs (no extra test dependencies).
// Checks src/route.ts and the inline head script in index.html, which must agree
// on which view a URL asks for (the script hides mismatched prerendered HTML).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');

const compiled = ts.transpileModule(fs.readFileSync('src/route.ts', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const routeAt = href => {
  const moduleOutput = { exports: {} };
  const window = href === null ? undefined : { location: new URL(href, 'https://mostlytext.app') };
  vm.runInNewContext(compiled, { exports: moduleOutput.exports, URLSearchParams, window });
  return moduleOutput.exports;
};
const headScript = /<script>(\(function \(l, d\)[\s\S]*?)<\/script>/.exec(fs.readFileSync('index.html', 'utf8'))[1];
const pendingFor = (href, prerenderedView) => {
  const classes = new Set();
  const d = { getAttribute: () => prerenderedView, classList: { add: c => classes.add(c) } };
  vm.runInNewContext(headScript, { location: new URL(href, 'https://mostlytext.app'), document: { documentElement: d } });
  return classes.has('prerender-pending');
};

// [URL, expected route, expected view]; unknown or malformed stages fall back to "To 1.0".
const cases = [
  ['/', '', 'home'], ['/#faq', '#faq', 'home'],
  ['/#/roadmap', '#/roadmap', '#/roadmap'], ['/#/roadmap/', '#/roadmap', '#/roadmap'],
  ['/#/roadmap/after-1', '#/roadmap/after-1', '#/roadmap/after-1'], ['/#/roadmap/after-1/', '#/roadmap/after-1', '#/roadmap/after-1'],
  ['/#/roadmap/bogus', '#/roadmap', '#/roadmap'], ['/#/roadmapafter-1', '#/roadmap', '#/roadmap'],
  ['/roadmap/', '#/roadmap', '#/roadmap'], ['/roadmap/?stage=after-1', '#/roadmap/after-1', '#/roadmap/after-1'],
  ['/roadmap/?stage=after-1&utm_source=x', '#/roadmap/after-1', '#/roadmap/after-1'],
  ['/roadmap/?utm_source=x&stage=after-1', '#/roadmap/after-1', '#/roadmap/after-1'],
  ['/roadmap/?stage=bogus', '#/roadmap', '#/roadmap'], ['/roadmap/?stage=', '#/roadmap', '#/roadmap'],
  ['/roadmap/?stage=AFTER-1', '#/roadmap', '#/roadmap'],
  ['/roadmap/?stage=after-1#/roadmap', '#/roadmap', '#/roadmap'],
  ['/roadmap/#/roadmap/after-1', '#/roadmap/after-1', '#/roadmap/after-1'],
  ['/roadmap/#main-content', '#/roadmap', '#/roadmap'],
  // Detail pages: one path segment of lower-case letters, digits and hyphens.
  ['/roadmap/write-find-and-organise/', '#/roadmap/detail/write-find-and-organise', '#/roadmap/detail/write-find-and-organise'],
  ['/roadmap/1-10', '#/roadmap/detail/1-10', '#/roadmap/detail/1-10'],
  ['/roadmap/later/?stage=after-1', '#/roadmap/detail/later', '#/roadmap/detail/later'],
  ['/roadmap/later/#work', '#/roadmap/detail/later', '#/roadmap/detail/later'],
  ['/roadmap/index.html', '#/roadmap', '#/roadmap'],
  ['/roadmap/Later/', '#/roadmap', '#/roadmap'],
  ['/roadmap/a/b/', '#/roadmap', '#/roadmap'],
  ['/roadmap/1-1/#/roadmap/after-1', '#/roadmap/after-1', '#/roadmap/after-1'],
  // The hash form of a detail page (the legacy hash view and single-page previews).
  ['/#/roadmap/detail/1-1', '#/roadmap/detail/1-1', '#/roadmap/detail/1-1'],
  ['/roadmap/#/roadmap/detail/later', '#/roadmap/detail/later', '#/roadmap/detail/later'],
  ['/#/roadmap/detail/Bad', '#/roadmap', '#/roadmap'],
];
let count = 0;
for (const [href, route, view] of cases) {
  const r = routeAt(href);
  assert.equal(r.routeFromLocation(), route, `route for ${href}`);
  assert.equal(r.viewOf(r.routeFromLocation()), view, `view for ${href}`);
  for (const prerendered of ['home', '#/roadmap', '#/roadmap/detail/later']) {
    assert.equal(pendingFor(href, prerendered), view !== prerendered, `head script for ${href} on the ${prerendered} page`);
  }
  count += 5;
}
const r = routeAt('/');
for (const [args, href] of [[['', true], '/roadmap/'], [['after-1', true], '/roadmap/?stage=after-1'], [['', false], '#/roadmap'], [['after-1', false], '#/roadmap/after-1']]) {
  assert.equal(r.stageHref(...args), href); count++;
}
for (const stage of ['', ...r.ROADMAP_STAGES]) {
  // Every link the site renders resolves back to the stage it names.
  assert.equal(routeAt(r.stageHref(stage, true)).routeFromLocation(), r.roadmapRoute(stage));
  assert.equal(routeAt('/' + r.stageHref(stage, false)).routeFromLocation(), r.roadmapRoute(stage));
  count += 2;
}
for (const name of ['write-find-and-organise', '1-0-x', '1-10', 'later']) {
  // A detail link resolves to its own detail route and view.
  const at = routeAt(r.detailHref(name));
  assert.equal(at.routeFromLocation(), r.detailRoute(name)); assert.equal(at.detailOf(at.routeFromLocation()), name);
  count += 2;
}
assert.equal(r.detailOf('#/roadmap'), ''); assert.equal(r.detailOf('#/roadmap/after-1'), ''); count += 2;
assert.equal(routeAt(null).routeFromLocation(), ''); assert.equal(routeAt(null).isRoadmapPage(), false);
assert.equal(routeAt('/roadmap/').isRoadmapPage(), true); assert.equal(routeAt('/#/roadmap').isRoadmapPage(), false);
count += 4;
console.log(`PASS: ${count} route and head-script assertions (${cases.length} URLs, stages: ${r.ROADMAP_STAGES.join(', ')}).`);
