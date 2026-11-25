// Harness glue between GraphvizWebRenderer (Swift) and the bundled
// viz-js library (viz-global.js, unmodified — see NOTICE.txt for the
// real license situation: MIT wrapper, EPL-2.0 Graphviz core), loaded
// alongside this file into an offscreen, network-isolated WKWebView
// (epic-21-implementation.md §3.7, mirroring epic-20-implementation.md
// §10's Mermaid containment exactly).
//
// Unlike Mermaid, no raster PNG snapshot is produced here: a real spike
// (epic-21-implementation.md Slice 0 as-built note) confirmed
// Graphviz's native SVG output has no <foreignObject> and displays
// correctly via AppKit's own SVG decoder, so `svg` alone serves both
// Export and native on-screen Preview display.
//
// The Viz WASM instance is created once per page (this harness is
// reused across many renders by the pool, epic-21-implementation.md
// §3.1) rather than once per render call.
var __vizInstancePromise = null;
var __comparisonVizInstancePromise = null;

function getViz() {
    if (!__vizInstancePromise) {
        __vizInstancePromise = window.Viz.instance();
    }
    return __vizInstancePromise;
}

// A comparison render needs distinct command-line defaults, so it cannot share
// the primary Viz wrapper. Keep that second wrapper for the lifetime of the
// pooled page instead of constructing another WASM wrapper for every cache
// miss. Cache hits do not enter either render path.
function getComparisonViz() {
    if (!__comparisonVizInstancePromise) {
        __comparisonVizInstancePromise = window.Viz.instance();
    }
    return __comparisonVizInstancePromise;
}

const GENERATED_NODE_SENTINEL = "#010203";
const GENERATED_NODE_COMPARISON_SENTINEL = "#fdfcfb";
// Graphviz otherwise defaults to Times-Roman. Helvetica is bundled as a
// Graphviz-native PostScript font, so layout metrics and emitted SVG agree
// without applying a CSS-only substitution after layout.
const GENERATED_FONT_NAME = "Helvetica";

// Match Mermaid's SVG-only viewport ceiling before Graphviz's generated
// elements are rewritten or the SVG is copied into AppKit Preview/Export.
// Output-byte limits alone cannot bound the decoded canvas dimensions.
const GRAPHVIZ_VECTOR_VIEWPORT_LIMITS = Object.freeze({ maxSide: 65536, maxArea: 64 * 1024 * 1024 });

function checkedGraphvizVectorViewport(width, height) {
    if (width > GRAPHVIZ_VECTOR_VIEWPORT_LIMITS.maxSide ||
        height > GRAPHVIZ_VECTOR_VIEWPORT_LIMITS.maxSide ||
        width > GRAPHVIZ_VECTOR_VIEWPORT_LIMITS.maxArea / height) {
        throw new Error("diagram exceeds vector viewport limit");
    }
}

function normalizedGraphvizSVG(svg, comparisonSVG, fill, nodeFill, stroke) {
    const document = new DOMParser().parseFromString(svg, "image/svg+xml");
    const comparisonDocument = new DOMParser().parseFromString(comparisonSVG, "image/svg+xml");
    const root = document.documentElement;
    const comparisonRoot = comparisonDocument.documentElement;
    if (!root || root.localName !== "svg" || !comparisonRoot || comparisonRoot.localName !== "svg") {
        throw new Error("invalid Graphviz SVG root");
    }
    const values = (root.getAttribute("viewBox") || "").trim().split(/[\s,]+/).map(Number);
    if (values.length !== 4 || !values.every(Number.isFinite) || values[2] <= 0 || values[3] <= 0) {
        throw new Error("invalid Graphviz SVG dimensions");
    }
    checkedGraphvizVectorViewport(values[2], values[3]);

    const nodes = [...root.querySelectorAll("g.node")];
    const comparisonNodes = [...comparisonRoot.querySelectorAll("g.node")];
    if (nodes.length !== comparisonNodes.length) throw new Error("inconsistent Graphviz node output");
    for (let index = 0; index < nodes.length; index += 1) {
        const elements = [...nodes[index].querySelectorAll("[fill], [stroke]")];
        const comparisonElements = [...comparisonNodes[index].querySelectorAll("[fill], [stroke]")];
        if (elements.length !== comparisonElements.length) throw new Error("inconsistent Graphviz node paint output");
        for (let elementIndex = 0; elementIndex < elements.length; elementIndex += 1) {
            const element = elements[elementIndex];
            const comparisonElement = comparisonElements[elementIndex];
            if ((element.getAttribute("fill") || "").toLowerCase() === GENERATED_NODE_SENTINEL &&
                (comparisonElement.getAttribute("fill") || "").toLowerCase() === GENERATED_NODE_COMPARISON_SENTINEL) {
                element.setAttribute("fill", nodeFill);
            }
            if ((element.getAttribute("stroke") || "").toLowerCase() === GENERATED_NODE_SENTINEL &&
                (comparisonElement.getAttribute("stroke") || "").toLowerCase() === GENERATED_NODE_COMPARISON_SENTINEL) {
                element.setAttribute("stroke", stroke);
            }
        }
    }

    const canvas = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    canvas.setAttribute("x", String(values[0]));
    canvas.setAttribute("y", String(values[1]));
    canvas.setAttribute("width", String(values[2]));
    canvas.setAttribute("height", String(values[3]));
    canvas.setAttribute("fill", fill);
    root.insertBefore(canvas, root.firstChild);
    return { svg: new XMLSerializer().serializeToString(root), width: values[2], height: values[3] };
}

function graphvizOptions(theme, background, nodeColor) {
    const options = {
        format: "svg",
        graphAttributes: { bgcolor: background, fontcolor: theme.text, fontname: GENERATED_FONT_NAME },
        nodeAttributes: { color: nodeColor, fontcolor: theme.text, fontname: GENERATED_FONT_NAME }
    };
    // Native DOT defaults have lower precedence than authored graph, node, and
    // edge attributes. Node defaults use a private marker so postprocessing can
    // distinguish them from any authored Graphviz color without parsing DOT.
    Object.assign(options.graphAttributes, { color: theme.stroke, fillcolor: theme.canvas });
    options.edgeAttributes = { color: theme.stroke, fontcolor: theme.text, fontname: GENERATED_FONT_NAME };
    return options;
}

// Keep oversized generated SVG inside WebKit rather than copying it through
// the native callback. Count without allocating a second encoded buffer.
function renderedUTF8ByteCount(text) {
    let bytes = 0;
    for (let index = 0; index < text.length; index += 1) {
        const code = text.charCodeAt(index);
        if (code < 0x80) bytes += 1;
        else if (code < 0x800) bytes += 2;
        else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < text.length &&
                 text.charCodeAt(index + 1) >= 0xDC00 && text.charCodeAt(index + 1) <= 0xDFFF) {
            bytes += 4;
            index += 1;
        } else bytes += 3;
    }
    return bytes;
}

window.__macdownRenderGraphviz = async function (source, theme, maxOutputBytes = 2 * 1024 * 1024) {
    try {
        if (!theme || !["neutral-light-v1", "preview-context-v1"].includes(theme.policyID)) {
            throw new Error("unsupported diagram palette");
        }
        const viz = await getViz();
        const background = theme && theme.canvas ? theme.canvas : "#FFFFFF";
        const svg = viz.renderString(source, graphvizOptions(theme, background, GENERATED_NODE_SENTINEL));
        // Viz keeps command-line defaults on an instance. The retained second
        // wrapper gives the comparison render an independent node marker.
        const comparisonViz = await getComparisonViz();
        const comparisonSVG = comparisonViz.renderString(
            source, graphvizOptions(theme, background, GENERATED_NODE_COMPARISON_SENTINEL)
        );
        const canvas = normalizedGraphvizSVG(svg, comparisonSVG, background, theme.nodeFill, theme.stroke);
        const byteCount = renderedUTF8ByteCount(canvas.svg);
        if (byteCount > maxOutputBytes) {
            return { ok: false, outputTooLargeByteCount: byteCount,
                     message: "rendered output too large" };
        }
        return { ok: true, svg: canvas.svg, width: canvas.width, height: canvas.height };
    } catch (error) {
        const message = error && error.message ? error.message : String(error);
        return { ok: false, message: message };
    }
};
