// Execute the existing D2 browser API, not a substitute parser or SVG fixture.
globalThis.__d2Result = null;
globalThis.__d2Phase = 'initialise';
(async () => {
  try {
    const engine = new window.D2();
    await engine.ready;
    __d2Phase = 'compile';
    const compiled = await engine.compile('alpha: JSC_D2_ALPHA\nbeta: JSC_D2_BETA\nalpha -> beta');
    __d2Phase = 'render';
    const svg = await engine.render(compiled.diagram, Object.assign({themeID: 0, darkThemeID: 0}, compiled.renderOptions || {}));
    if (typeof svg !== 'string' || !svg.includes('<svg') || !svg.includes('JSC_D2_ALPHA') || !svg.includes('JSC_D2_BETA')) throw Error('Missing real D2 SVG');
    if (/<(?:script|foreignObject)\b|(?:href|src)\s*=\s*['"](?:https?:|\/\/)|@import|url\(\s*['"]?https?:/i.test(svg)) throw Error('Unsafe D2 SVG');
    if (!/<(?:path|rect|polygon)\b/.test(svg)) throw Error('Missing vector geometry');
    __d2Result = {ok: true, phase: 'complete', svg, controls: __hostControls};
  } catch (error) {
    __d2Result = {ok: false, phase: __d2Phase, name: String(error.name).slice(0,128), message: String(error.message).slice(0,512)};
  }
})();
