// Offline source-level palette regressions. Run with Node; no app or WebKit is launched.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { Worker: Thread } = require('node:worker_threads');
const root = process.argv[2] || path.resolve(__dirname, '../Packages/MacDownKit');
const read = relative => fs.readFileSync(path.join(root, 'Sources', relative), 'utf8');
const blobs = new Map(); const workers = []; let blobID = 0;
global.window = global;
URL.createObjectURL = blob => { const key = `blob:${++blobID}`; blobs.set(key, blob); return key; };
// Execute the exact bundled browser D2 WASM through a local Node worker bridge.
global.Worker = class {
    constructor(url) {
        this.pending = [];
        blobs.get(url).text().then(source => {
            this.thread = new Thread(`import {parentPort} from 'node:worker_threads';
                globalThis.self = globalThis;
                self.postMessage = data => parentPort.postMessage(data);
                parentPort.on('message', data => self.onmessage({data}));\n` +
                source.replace('export function setupMessageHandler', 'function setupMessageHandler'), { eval: true });
            workers.push(this.thread);
            this.thread.on('message', data => this.onmessage({data}));
            this.thread.on('error', error => { throw error; });
            this.pending.forEach(data => this.thread.postMessage(data));
        });
    }
    postMessage(data) { this.thread ? this.thread.postMessage(data) : this.pending.push(data); }
};
const load = relative => vm.runInThisContext(read(relative), { filename: relative });
const light = { policyID: 'preview-context-v1', text: '#1A1A1A', stroke: '#1A1A1A', canvas: '#FFFFFF', nodeFill: '#FFFFFF', accent: '#1A1A1A' };
const dark = { ...light, text: '#EEDDCC', stroke: '#EEDDCC', canvas: '#112233', nodeFill: '#112233', accent: '#EEDDCC' };
const paper = { ...light, policyID: 'neutral-light-v1', nodeFill: '#F3F5F8' };
// These source tests inspect native engine options/output; DOM composition and
// raster/native image decoding remain the separate WebKit/native test gate.
function uncomposed(svg, fill) { return { svg, fill, width: 100, height: 100 }; }
async function main() {
    load('DiagramRendering/Resources/mermaid.min.js');
    load('DiagramRendering/Resources/render.js');
    const parse = mermaid.parse.bind(mermaid);
    const seen = [];
    mermaid.render = async (_id, source) => {
        await parse(source);
        seen.push(JSON.parse(JSON.stringify(mermaid.mermaidAPI.getConfig())));
        return { svg: '<svg/>' };
    };
    global.document = { getElementById: () => null };
    addOpaqueCanvas = (svg, fill) => ({ ...uncomposed(svg, fill), svg: fill });
    rasterize = async () => 'source-test';
    for (const palette of [light, dark, paper]) {
        const result = await __macdownRenderMermaid('graph TD; A-->B;', palette);
        assert.equal(result.ok, true, result.message);
        const config = seen.at(-1);
        assert.equal(config.themeVariables.primaryTextColor, palette.text);
        assert.equal(config.themeVariables.nodeBkg, palette.nodeFill);
        assert.equal(config.themeVariables.mainBkg, palette.nodeFill);
        assert.equal(config.themeVariables.textColor, palette.text);
        assert.equal(config.themeVariables.lineColor, palette.stroke);
        for (const key of ['secondaryBorderColor', 'tertiaryBorderColor', 'activationBorderColor',
            'pieStrokeColor', 'pieOuterStrokeColor', 'archGroupBorderColor']) {
            assert.equal(config.themeVariables[key], palette.stroke, key);
        }
        for (const key of ['attributeBackgroundColorOdd', 'attributeBackgroundColorEven',
            'altSectionBkgColor', 'doneTaskBkgColor', 'activeTaskBkgColor']) {
            assert.equal(config.themeVariables[key], palette.nodeFill, key);
        }
        assert.equal(result.svg, palette.canvas);
        assert.equal(config.securityLevel, 'strict');
    }
    const grayPie = { ...light, canvas: '#777777', text: '#000000', stroke: '#000000',
        nodeFill: '#777777', pie1: '#000000', pie12: '#060606' };
    const pieResult = await __macdownRenderMermaid('pie\n  "One" : 1\n  "Two" : 2', grayPie);
    assert.equal(pieResult.ok, true, pieResult.message);
    assert.equal(seen.at(-1).themeVariables.pieSectionTextColor, grayPie.canvas);
    assert.equal(seen.at(-1).themeVariables.pie12, grayPie.pie12);
    const architecture = 'architecture-beta\nservice a(server)[A]\nservice b(database)[B]\na:R --> L:b';
    for (const palette of [light, dark, paper]) {
        const result = await __macdownRenderMermaid(architecture, palette);
        assert.equal(result.ok, true, result.message);
        const config = seen.at(-1);
        assert.equal(config.themeVariables.archEdgeColor, palette.text, 'architecture edge default');
        assert.equal(config.themeVariables.archEdgeArrowColor, palette.text, 'architecture arrow default');
    }
    const authoredArchitecture = [
        '%%{init: {"themeVariables":{"archEdgeColor":"#123456","archEdgeArrowColor":"#ABCDEF"}}}%%\n',
        '---\nconfig:\n  themeVariables:\n    archEdgeColor: "#123456"\n    archEdgeArrowColor: "#ABCDEF"\n---\n'
    ];
    for (const prefix of authoredArchitecture) {
        const result = await __macdownRenderMermaid(prefix + architecture, dark);
        assert.equal(result.ok, true, result.message);
        const config = seen.at(-1);
        assert.equal(config.themeVariables.archEdgeColor, '#123456', 'authored architecture edge');
        assert.equal(config.themeVariables.archEdgeArrowColor, '#ABCDEF', 'authored architecture arrow');
        assert.equal(config.securityLevel, 'strict');
    }
    console.log('PASS Mermaid architecture-beta real parser: screen/light/print edge and arrow defaults; authored init/frontmatter colors');
    const sources = [
        '%%{init: {"themeVariables":{"primaryColor":"#123456","primaryTextColor":"#000000","lineColor":"#ABCDEF","background":"#654321"},"securityLevel":"loose","secure":[]}}%%\ngraph TD; A-->B;',
        '---\nconfig:\n  securityLevel: loose\n  themeVariables:\n    primaryColor: "#123456"\n    primaryTextColor: "#000000"\n    lineColor: "#ABCDEF"\n    background: "#654321"\n---\ngraph TD; A-->B;'
    ];
    for (const source of sources) {
        const result = await __macdownRenderMermaid(source, dark);
        assert.equal(result.ok, true, result.message);
        const config = seen.at(-1);
        assert.equal(config.themeVariables.primaryColor, '#123456');
        assert.equal(config.themeVariables.primaryTextColor, '#000000');
        assert.equal(config.themeVariables.nodeBkg, '#123456', 'derived flowchart fill');
        assert.equal(config.themeVariables.mainBkg, '#123456', 'derived primary fill');
        assert.equal(config.themeVariables.textColor, '#000000', 'derived label paint');
        assert.equal(config.themeVariables.defaultLinkColor, '#ABCDEF', 'derived edge paint');
        assert.equal(config.themeVariables.lineColor, '#ABCDEF');
        assert.equal(result.svg, '#654321');
        assert.equal(config.securityLevel, 'strict');
        assert.ok(config.secure.includes('securityLevel'));
    }
    const authoredAlias = '%%{init: {"themeVariables":{"primaryColor":"#123456","nodeBkg":"#112233","primaryTextColor":"#000000","textColor":"#ABCDEF"}}}%%\ngraph TD; A-->B;';
    assert.equal((await __macdownRenderMermaid(authoredAlias, dark)).ok, true);
    assert.equal(seen.at(-1).themeVariables.nodeBkg, '#112233', 'explicit alias wins over primary fill');
    assert.equal(seen.at(-1).themeVariables.textColor, '#ABCDEF', 'explicit text paint wins over primary text');
    for (const palette of [light, dark, light]) {
        assert.equal((await __macdownRenderMermaid('graph TD; A-->B;', palette)).ok, true);
        assert.equal(seen.at(-1).themeVariables.nodeBkg, palette.nodeFill, 'authored fill does not leak');
        assert.equal(seen.at(-1).themeVariables.textColor, palette.text, 'authored label paint does not leak');
    }
    console.log('PASS Mermaid real parser: screen/light/print defaults; authored init/frontmatter derived paints and explicit aliases; strict security');
    delete global.document;
    load('D2Rendering/Resources/d2-browser.js');
    load('D2Rendering/Resources/render.js');
    opaqueD2Canvas = uncomposed;
    for (const palette of [light, dark, paper]) {
        const result = await __macdownRenderD2('a -> b: label', palette);
        assert.equal(result.ok, true, result.message);
        const text = palette === paper ? '#0A0F25' : palette.text;
        const stroke = palette === paper ? '#0D32B2' : palette.stroke;
        assert.ok(result.svg.includes(`.fill-N1{fill:${text};}`));
        assert.ok(result.svg.includes(`.stroke-B1{stroke:${stroke};}`));
        const paints = d2ThemePaints(result.svg);
        assert.equal(paints.get('fill-N1'), text);
        assert.equal(paints.get('stroke-B1'), stroke);
        const generated = {
            classList: ['text-bold', 'fill-N1'], attributes: {},
            hasAttribute(name) { return Object.hasOwn(this.attributes, name); },
            setAttribute(name, value) { this.attributes[name] = value; }
        };
        const authored = { ...generated, attributes: { fill: 'black' } };
        makeD2ThemePaintLiteral({ querySelectorAll: () => [generated, authored] }, result.svg);
        assert.equal(generated.attributes.fill, text);
        assert.equal(authored.attributes.fill, 'black');
        const expectedCanvas = palette.canvas;
        assert.ok(result.svg.includes(`.fill-N7{fill:${expectedCanvas};}`));
        await workers.at(-1).terminate();
    }
    const d2Authored = await __macdownRenderD2('style.fill: "#654321"\na: {style.fill: "#123456"; style.font-color: black; style.stroke: black}\na -> b: edge {style.stroke: "#ABCDEF"; style.font-color: black}', dark);
    assert.equal(d2Authored.ok, true, d2Authored.message);
    for (const color of ['#654321', '#123456', '#ABCDEF', 'stroke="black"', 'fill="black"']) assert.ok(d2Authored.svg.includes(color), color);
    await workers.at(-1).terminate();
    const d2Overrides = await __macdownRenderD2('vars: {d2-config: {theme-overrides: {N1: "#123456"; N7: "#654321"}}}\na -> b', dark);
    assert.equal(d2Overrides.ok, true, d2Overrides.message);
    assert.ok(d2Overrides.svg.includes('.fill-N1{fill:#123456;}'));
    assert.ok(d2Overrides.svg.includes('.fill-N7{fill:#654321;}'));
    await workers.at(-1).terminate();
    console.log('PASS D2 real WASM: screen/light/print defaults; authored text/stroke/fill/background and theme overrides');
    global.Viz = require(path.resolve(root, 'Sources/GraphvizRendering/Resources/viz-global.js'));
    load('GraphvizRendering/Resources/render.js');
    opaqueGraphvizCanvas = uncomposed;
    for (const palette of [light, dark, paper]) {
        const result = await __macdownRenderGraphviz('digraph { node [style=filled]; subgraph cluster_a { label=group; style=filled; a -> b [label="Edge label"]; } }', palette);
        assert.equal(result.ok, true, result.message);
        assert.ok(result.svg.toLowerCase().includes(`fill="${palette.text.toLowerCase()}"`));
        assert.ok(result.svg.toLowerCase().includes(`fill="${palette.canvas.toLowerCase()}"`));
        const expectedStroke = palette === paper ? 'black' : palette.stroke.toLowerCase();
        assert.ok(result.svg.toLowerCase().includes(`stroke="${expectedStroke}"`));
        if (palette === dark) assert.ok(!result.svg.includes('stroke="black"'));
    }
    const graphAuthored = await __macdownRenderGraphviz('digraph { bgcolor="#654321"; node [style=filled, fillcolor="#123456", color=black, fontcolor=black]; a -> b [label="Edge label", color="#ABCDEF", fontcolor=black]; }', dark);
    assert.equal(graphAuthored.ok, true, graphAuthored.message);
    for (const paint of ['fill="#654321"', 'fill="#123456"', 'stroke="black"', 'stroke="#abcdef"']) assert.ok(graphAuthored.svg.toLowerCase().includes(paint.toLowerCase()), paint);
    assert.match(graphAuthored.svg, /<text(?![^>]*fill=)[^>]*>/);
    console.log('PASS Graphviz real WASM: screen/light/print defaults; authored text/stroke/fill/background');
}
main().then(async () => { await Promise.all(workers.map(worker => worker.terminate())); }).catch(async error => { console.error(error); await Promise.all(workers.map(worker => worker.terminate())); process.exitCode = 1; });
