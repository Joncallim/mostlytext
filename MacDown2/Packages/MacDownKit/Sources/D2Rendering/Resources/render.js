// Harness glue between D2WebRenderer (Swift) and the bundled D2 library
// (d2-browser.js — see NOTICE.txt for the one-line modification from
// upstream), loaded alongside this file into an offscreen,
// network-isolated WKWebView (epic-21-implementation.md §3.7, mirroring
// epic-20-implementation.md §10's Mermaid containment exactly).
//
// Unlike Mermaid, no raster PNG snapshot is produced here: a real spike
// (epic-21-implementation.md Slice 0 as-built note) confirmed D2's
// native SVG output has no <foreignObject> and displays correctly via
// AppKit's own SVG decoder, so `svg` alone serves both Export and native
// on-screen Preview display.
// AppKit's SVG decoder does not reliably apply D2's scoped theme classes.
// Give only generated theme-token paints a literal fallback. Existing literal
// attributes (authored colors) always win; WebKit retains the original CSS.
function d2ThemePaints(styles) {
    const paints = new Map();
    const declarations = /\.(fill|stroke)-(N[1-7]|B[1-6]|AA[245]|AB[45])\s*\{\s*(fill|stroke):\s*([^;{}]+)\s*;/g;
    for (const match of styles.matchAll(declarations)) {
        if (match[1] === match[3] && !paints.has(match[1] + "-" + match[2])) {
            paints.set(match[1] + "-" + match[2], match[4].trim());
        }
    }
    return paints;
}

function makeD2ThemePaintLiteral(root, styles) {
    const paints = d2ThemePaints(styles);
    for (const element of root.querySelectorAll("[class]")) {
        for (const token of element.classList) {
            const color = paints.get(token);
            const property = token.split("-")[0];
            if (color && !element.hasAttribute(property)) element.setAttribute(property, color);
        }
    }
}

function opaqueD2Canvas(svg, fill) {
    const document = new DOMParser().parseFromString(svg, "image/svg+xml");
    const root = document.documentElement;
    if (!root || root.localName !== "svg") throw new Error("invalid D2 SVG root");
    const values = (root.getAttribute("viewBox") || "").trim().split(/[\s,]+/).map(Number);
    if (values.length !== 4 || !values.every(Number.isFinite) || values[2] <= 0 || values[3] <= 0) {
        throw new Error("invalid D2 SVG dimensions");
    }
    // D2's generated background is the first rect in its nested SVG. AppKit's
    // SVG decoder does not apply D2's scoped CSS class to that rect and paints
    // it black. Make the generated theme background literal while
    // leaving every authored shape/style untouched. Only match the bundled
    // theme token class and CSS declaration, never a literal authored paint.
    const diagramRoot = root.firstElementChild;
    const background = diagramRoot && diagramRoot.localName === "svg" ? diagramRoot.firstElementChild : null;
    const styles = diagramRoot ? Array.from(diagramRoot.childNodes)
        .filter(node => node.localName === "style").map(node => node.textContent).join("\n") : "";
    const generatedFill = styles.match(/\.fill-N7\s*\{\s*fill:\s*(#[0-9A-F]{6})\s*;/i);
    if (background && background.localName === "rect" &&
        background.getAttribute("class")?.trim() === "fill-N7" &&
        generatedFill) {
        background.removeAttribute("class");
        background.setAttribute("fill", generatedFill[1]);
    }
    if (diagramRoot) makeD2ThemePaintLiteral(diagramRoot, styles);
    const canvas = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    canvas.setAttribute("x", String(values[0]));
    canvas.setAttribute("y", String(values[1]));
    canvas.setAttribute("width", String(values[2]));
    canvas.setAttribute("height", String(values[3]));
    canvas.setAttribute("fill", fill);
    root.insertBefore(canvas, root.firstChild);
    return { svg: new XMLSerializer().serializeToString(root), width: values[2], height: values[3] };
}

// One engine/worker belongs to each pooled page. The pool awaits readiness
// during bounded preparation and serializes every later compile/render pair.
const macdownD2Engine = new window.D2();
window.__macdownPrepareD2 = async function () {
    try {
        await macdownD2Engine.ready;
        return { ok: true };
    } catch (error) {
        return { ok: false, message: error && error.message ? error.message : String(error) };
    }
};

window.__macdownRenderD2 = async function (source, theme) {
    try {
        if (!theme || !["neutral-light-v1", "preview-context-v1"].includes(theme.policyID)) {
            throw new Error("unsupported diagram palette");
        }
        const d2 = macdownD2Engine;
        const compiled = await d2.compile(source);
        // This bundled D2.js version documents themeID/darkThemeID. Pin
        // defaults across WebKit appearances, while retaining a theme
        // explicitly authored in the D2 source.
        const authored = compiled.renderOptions || {};
        const options = Object.assign({ themeID: 0, darkThemeID: 0 }, authored);
        if (authored.themeID != null && authored.darkThemeID == null) {
            options.darkThemeID = authored.themeID;
        }
        // D2 keeps generated theme tokens distinct from literal authored
        // colors in its compiled diagram. Use its native override API;
        // never search and replace black pixels or authored SVG paint.
        const defaults = {
            N1: theme.text, N2: theme.text, N3: theme.stroke,
            N4: theme.stroke, N5: theme.nodeFill, N6: theme.nodeFill, N7: theme.canvas,
            B1: theme.stroke, B2: theme.stroke, B3: theme.nodeFill,
            B4: theme.nodeFill, B5: theme.nodeFill, B6: theme.nodeFill,
            AA2: theme.text, AA4: theme.nodeFill, AA5: theme.nodeFill,
            AB4: theme.nodeFill, AB5: theme.nodeFill
        };
        // An explicitly selected source theme remains an authored palette.
        // Explicit per-token overrides also win over application defaults.
        if (!authored.themeID) {
            options.themeOverrides = Object.assign({}, defaults, authored.themeOverrides || {});
            options.darkThemeOverrides = Object.assign({}, defaults,
                authored.themeOverrides || {}, authored.darkThemeOverrides || {});
        }
        const svg = await d2.render(compiled.diagram, options);
        const canvas = opaqueD2Canvas(svg, theme.canvas);
        return { ok: true, svg: canvas.svg, width: canvas.width, height: canvas.height };
    } catch (error) {
        const message = error && error.message ? error.message : String(error);
        return { ok: false, message: message };
    }
};
