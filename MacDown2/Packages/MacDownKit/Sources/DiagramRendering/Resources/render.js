// Harness glue between MermaidWebRenderer (Swift) and the bundled Mermaid
// library, loaded alongside this file into an offscreen, network-isolated
// WKWebView (epic-20-implementation.md §10). `securityLevel: 'strict'`
// disables Mermaid's own `click` interaction directives and sanitizes HTML
// inside diagram labels — defense in depth alongside the page's own CSP and
// the containing WKWebView's lack of network access.
mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    // Mermaid applies init directives and frontmatter config through the
    // same config sanitizer. Protect security and the selected base theme,
    // while allowing explicitly authored themeVariables (including colors)
    // to override the application's defaults without rewriting source.
    secure: [
        "secure", "securityLevel", "startOnLoad", "maxTextSize",
        "suppressErrorRendering", "maxEdges", "theme", "themeCSS"
    ]
});

// Real WebKit-composited raster snapshot resolution multiplier for the
// `png` field below (see the long comment on that field for why this
// exists at all). 2x keeps small diagrams crisp on a Retina display
// without the cost of Math's own 3x (`MathImageRenderer.standardScale`) —
// diagrams are typically larger/more detailed than a single equation, so
// output byte size matters more here.
var PREVIEW_RASTER_SCALE = 2;
// Version this policy with the Mermaid cache key. A single canvas is bounded
// to 32 MiB of RGBA pixels before Image or canvas allocation begins.
var PREVIEW_RASTER_LIMITS = Object.freeze({
    policyID: "neutral-light-v1-raster-v1",
    maxSidePixels: 4096,
    maxPixels: 8 * 1024 * 1024
});

function checkedRasterSize(width, height) {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
        throw new Error("invalid SVG dimensions");
    }
    var pixelWidth = Math.max(1, Math.round(width * PREVIEW_RASTER_SCALE));
    var pixelHeight = Math.max(1, Math.round(height * PREVIEW_RASTER_SCALE));
    if (!Number.isSafeInteger(pixelWidth) || !Number.isSafeInteger(pixelHeight) ||
        pixelWidth < 1 || pixelHeight < 1 ||
        pixelWidth > PREVIEW_RASTER_LIMITS.maxSidePixels ||
        pixelHeight > PREVIEW_RASTER_LIMITS.maxSidePixels ||
        pixelWidth * pixelHeight > PREVIEW_RASTER_LIMITS.maxPixels) {
        throw new Error("diagram exceeds raster pixel limit");
    }
    return { width: pixelWidth, height: pixelHeight };
}

var __macdownRenderCounter = 0;

// Count UTF-8 without materializing another copy of a potentially large SVG.
// This gate runs before rasterization and before WebKit bridges the SVG to Swift.
function renderedUTF8ByteCount(text) {
    var bytes = 0;
    for (var index = 0; index < text.length; index += 1) {
        var code = text.charCodeAt(index);
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

// canvas.toDataURL produces canonical padded base64. Count decoded PNG bytes
// in place so a large raster stays inside WebKit, just like an oversized SVG.
function rasterPNGByteCount(base64) {
    if (base64.length % 4 !== 0) throw new Error("invalid raster output");
    var padding = base64.endsWith("==") ? 2 : (base64.endsWith("=") ? 1 : 0);
    return base64.length / 4 * 3 - padding;
}

// Rasterizes `svg` (Mermaid's own, unmodified output — including
// <foreignObject> HTML labels) via the standard canvas technique: load it
// as an <img> from a data: URI, draw that image onto a canvas, and read
// the canvas back out as a PNG data URL. This runs inside the SAME real
// WebKit engine that already renders <foreignObject>/CSS correctly for
// on-screen display — unlike AppKit's native SVG decoder (see the
// `png` field's doc comment) — so the result has full visual fidelity.
function rasterize(svg, width, height) {
    var size = checkedRasterSize(width, height);
    return new Promise((resolve, reject) => {
        var image = new Image();
        image.onload = () => {
            var canvas = document.createElement("canvas");
            canvas.width = size.width;
            canvas.height = size.height;
            var context = canvas.getContext("2d");
            context.drawImage(image, 0, 0, canvas.width, canvas.height);
            var dataURL = canvas.toDataURL("image/png");
            var prefix = "data:image/png;base64,";
            resolve(dataURL.startsWith(prefix) ? dataURL.slice(prefix.length) : dataURL);
        };
        image.onerror = () => reject(new Error("rasterization failed"));
        image.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
    });
}

function positiveLength(value) {
    var text = String(value || "").trim();
    var match = text.match(/^([+]?\d+(?:\.\d*)?|[+]?\.\d+)(?:[eE][+-]?\d+)?(?:px)?$/i);
    if (!match) return 0;
    var number = Number(text.replace(/px$/i, ""));
    return Number.isFinite(number) && number > 0 ? number : 0;
}

function svgCanvasDimensions(root) {
    var viewBox = root.getAttribute("viewBox");
    var values = viewBox ? viewBox.trim().split(/[\s,]+/).map(Number) : [];
    var validViewBox = values.length === 4 && values.every(Number.isFinite) && values[2] > 0 && values[3] > 0;
    if (validViewBox) {
        return {
            x: values[0],
            y: values[1],
            width: values[2],
            height: values[3],
            usesViewBox: true,
            rectWidth: String(values[2]),
            rectHeight: String(values[3])
        };
    }

    var rectWidth = root.getAttribute("width") || "";
    var rectHeight = root.getAttribute("height") || "";
    var width = positiveLength(rectWidth);
    var height = positiveLength(rectHeight);
    if (width && height) {
        return {
            x: 0,
            y: 0,
            width: width,
            height: height,
            usesViewBox: false,
            rectWidth: rectWidth,
            rectHeight: rectHeight
        };
    }

    throw new Error("invalid SVG dimensions");
}

function addOpaqueCanvas(svg, fill) {
    var parser = new DOMParser();
    var document = parser.parseFromString(svg, "image/svg+xml");
    var root = document.documentElement;
    if (!root || root.nodeName.toLowerCase() !== "svg") throw new Error("invalid SVG root");

    var dimensions = svgCanvasDimensions(root);
    if (!dimensions.usesViewBox) root.removeAttribute("viewBox");
    var rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    rect.setAttribute("x", String(dimensions.x));
    rect.setAttribute("y", String(dimensions.y));
    rect.setAttribute("width", dimensions.rectWidth);
    rect.setAttribute("height", dimensions.rectHeight);
    rect.setAttribute("fill", fill);
    root.insertBefore(rect, root.firstChild);
    return {
        svg: new XMLSerializer().serializeToString(root),
        width: dimensions.width,
        height: dimensions.height
    };
}

// Returns a plain, JSON-serializable object so it bridges cleanly across
// WKWebView's evaluateJavaScript boundary:
// { ok: true, svg, png, width, height } on success, { ok: false, message }
// on failure. Never throws — every failure path is caught and reported
// through this same shape so the Swift side has one place to interpret a
// result.
//
// `svg` is Mermaid's own, unmodified vector output (genuinely resolution-
// independent) — this is what Export splices into HTML/PDF
// (epic-20-implementation.md §7.1) and it must keep Mermaid's richer
// default HTML-based labels, not a degraded native-<text> substitute.
//
// `png` is a real WebKit-rendered raster snapshot of that SAME svg, added
// after a real spike (see this repository's PR history for
// epic-20-implementation.md Slice 4) proved AppKit's own built-in SVG
// decoder (`NSImage`/`_NSSVGImageRep`) does not reliably display real
// Mermaid output: it silently drops every <foreignObject> label (a
// two-node "graph TD; A-->B;" rendered as two empty boxes joined by a
// line, no "A"/"B" text at all), and forcing Mermaid's `htmlLabels: false`
// escape hatch to work around that produced native <text> elements in the
// wrong vertical position (a further, apparently CSS-support-related
// AppKit SVG decoder limitation) — so native, on-screen Preview display
// uses this raster snapshot instead (mirroring `MathContribution`'s own
// PNG-based approach), while Export keeps using `svg` untouched, genuinely
// vector, and unaffected by any of this.
window.__macdownRenderMermaid = async function (source, theme, maxOutputBytes = 2 * 1024 * 1024) {
    __macdownRenderCounter += 1;
    var id = "macdown-diagram-" + __macdownRenderCounter;
    try {
        if (!theme || !["neutral-light-v1", "preview-context-v1"].includes(theme.policyID)) {
            throw new Error("unsupported diagram palette");
        }
        var foreground = theme && theme.text ? theme.text : "#1A1A1A";
        var background = theme && theme.canvas ? theme.canvas : "#FFFFFF";
        var nodeFill = theme && theme.nodeFill ? theme.nodeFill : "#F3F5F8";
        var stroke = theme && theme.stroke ? theme.stroke : "#1A1A1A";
        var configuration = {
            startOnLoad: false,
            securityLevel: "strict",
            secure: [
                "secure", "securityLevel", "startOnLoad", "maxTextSize",
                "suppressErrorRendering", "maxEdges", "theme", "themeCSS"
            ],
            theme: "base",
            themeVariables: {
                background: background,
                primaryColor: nodeFill,
                primaryTextColor: foreground,
                primaryBorderColor: stroke,
                lineColor: stroke,
                secondaryColor: nodeFill,
                tertiaryColor: nodeFill,
                secondaryTextColor: foreground,
                tertiaryTextColor: foreground,
                secondaryBorderColor: stroke,
                tertiaryBorderColor: stroke,
                activationBorderColor: stroke,
                pieStrokeColor: stroke,
                pieOuterStrokeColor: stroke,
                archGroupBorderColor: stroke,
                archEdgeColor: foreground,
                archEdgeArrowColor: foreground,
                attributeBackgroundColorOdd: nodeFill,
                attributeBackgroundColorEven: nodeFill,
                altSectionBkgColor: nodeFill,
                excludeBkgColor: nodeFill,
                doneTaskBkgColor: nodeFill,
                doneTaskBorderColor: stroke,
                activeTaskBkgColor: nodeFill,
                activeTaskBorderColor: stroke,
                edgeLabelBackground: background,
                clusterBkg: nodeFill,
                clusterBorder: stroke,
                actorBkg: nodeFill,
                actorBorder: stroke,
                actorTextColor: foreground,
                signalColor: stroke,
                signalTextColor: foreground,
                labelBoxBkgColor: nodeFill,
                labelBoxBorderColor: stroke,
                labelTextColor: foreground,
                loopTextColor: foreground,
                noteBkgColor: nodeFill,
                noteBorderColor: stroke,
                noteTextColor: foreground,
                titleColor: foreground,
                pieSectionTextColor: background,
                pieLegendTextColor: foreground,
                pieTitleTextColor: foreground,
                pie1: theme.pie1,
                pie2: theme.pie2,
                pie3: theme.pie3,
                pie4: theme.pie4,
                pie5: theme.pie5,
                pie6: theme.pie6,
                pie7: theme.pie7,
                pie8: theme.pie8,
                pie9: theme.pie9,
                pie10: theme.pie10,
                pie11: theme.pie11,
                pie12: theme.pie12,
                critBkgColor: nodeFill,
                critBorderColor: stroke,
                todayLineColor: stroke,
                vertLineColor: stroke
            }
        };
        mermaid.initialize(configuration);
        // Use Mermaid's own sanitized source config, rather than its merged
        // config: the latter already contains computed aliases such as nodeBkg.
        // Reinitialize from raw defaults plus authored variables so primaryColor
        // and primaryTextColor can also update the paints derived from them.
        var parsed = await mermaid.parse(source);
        if (parsed.config.themeVariables) {
            configuration.themeVariables = Object.assign(
                {}, configuration.themeVariables, parsed.config.themeVariables
            );
            mermaid.initialize(configuration);
        }
        var result = await mermaid.render(id, source);
        // Read the resolved library configuration after its own safe directive
        // parser has applied init/frontmatter. An authored canvas color is
        // content too; it must not be covered by our default backing rect.
        var resolved = mermaid.mermaidAPI.getConfig().themeVariables || {};
        var canvas = addOpaqueCanvas(result.svg, resolved.background || background);
        var byteCount = renderedUTF8ByteCount(canvas.svg);
        if (byteCount > maxOutputBytes) {
            return { ok: false, outputTooLargeByteCount: byteCount,
                     message: "rendered output too large" };
        }
        var png = await rasterize(canvas.svg, canvas.width, canvas.height);
        var pngByteCount = rasterPNGByteCount(png);
        if (pngByteCount > maxOutputBytes) {
            return { ok: false, outputTooLargeByteCount: pngByteCount,
                     message: "rendered output too large" };
        }
        return { ok: true, svg: canvas.svg, png: png, width: canvas.width, height: canvas.height };
    } catch (error) {
        var message = error && error.message ? error.message : String(error);
        return { ok: false, message: message };
    } finally {
        // Mermaid's render() can leave a temporary measurement container in
        // the DOM on some failure paths. This offscreen page is reused
        // across many renders (pooled, epic-20-implementation.md §11), so
        // stray elements would otherwise accumulate for the life of the
        // pool entry.
        var stray = document.getElementById(id);
        if (stray && stray.parentNode) {
            stray.parentNode.removeChild(stray);
        }
    }
};

// The production renderer receives only Mermaid-generated SVG, but keeping
// this probe beside the production path lets package tests exercise the same
// real WebKit canvas/rasterization logic with SVG edge cases Mermaid does not
// normally emit (for example comma-separated viewBox values).
window.__macdownInspectMermaidSVG = async function (svg) {
    var canvas = addOpaqueCanvas(svg, "#FFFFFF");
    var png = await rasterize(canvas.svg, canvas.width, canvas.height);
    return { svg: canvas.svg, png: png, width: canvas.width, height: canvas.height };
};
