// Exercise the bundled browser glue at its actual return boundary without
// starting a WebKit page or loading the large third-party renderer binaries.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../Packages/MacDownKit/Sources');
const svg = '<svg>é😀</svg>';
const byteCount = Buffer.byteLength(svg);
const palette = { policyID: 'neutral-light-v1', text: '#000000', canvas: '#FFFFFF',
    stroke: '#000000', nodeFill: '#FFFFFF' };

function harness(relative, values) {
    const context = vm.createContext({ ...values });
    context.window = context;
    vm.runInContext(fs.readFileSync(path.join(root, relative), 'utf8'), context, { filename: relative });
    assert.equal(context.renderedUTF8ByteCount(svg), byteCount);
    assert.equal(context.renderedUTF8ByteCount('A\uD800'), Buffer.byteLength('A\uD800'));
    return context;
}

async function check(name, render) {
    const refused = await render(byteCount - 1);
    assert.equal(refused.ok, false, name);
    assert.equal(refused.outputTooLargeByteCount, byteCount, name);
    assert.equal(refused.svg, undefined, `${name}: refused SVG crossed the bridge`);
    const accepted = await render(byteCount);
    assert.equal(accepted.ok, true, name);
    assert.equal(accepted.svg, svg, name);
}

async function main() {
    let rasterized = 0;
    const mermaid = harness('DiagramRendering/Resources/render.js', {
        mermaid: {
            initialize() {},
            parse: async () => ({ config: {} }),
            render: async () => ({ svg }),
            mermaidAPI: { getConfig: () => ({ themeVariables: {} }) }
        },
        document: { getElementById: () => null }
    });
    mermaid.addOpaqueCanvas = () => ({ svg, width: 10, height: 10 });
    mermaid.rasterize = async () => { rasterized += 1; return 'png'; };
    await check('Mermaid', limit => mermaid.__macdownRenderMermaid('graph TD; A-->B;', palette, limit));
    assert.equal(rasterized, 1, 'only admitted Mermaid output may reach rasterization');

    const d2 = harness('D2Rendering/Resources/render.js', {
        D2: class {
            async compile() { return { diagram: {}, renderOptions: {} }; }
            async render() { return svg; }
        }
    });
    d2.opaqueD2Canvas = () => ({ svg, width: 10, height: 10 });
    await check('D2', limit => d2.__macdownRenderD2('a -> b', palette, limit));

    const graphviz = harness('GraphvizRendering/Resources/render.js', {});
    graphviz.getViz = async () => ({ renderString: () => svg });
    graphviz.getComparisonViz = graphviz.getViz;
    graphviz.normalizedGraphvizSVG = () => ({ svg, width: 10, height: 10 });
    await check('Graphviz', limit => graphviz.__macdownRenderGraphviz('digraph { a -> b }', palette, limit));
    console.log('PASS all three diagram outputs refuse over-limit UTF-8 before returning SVG');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
