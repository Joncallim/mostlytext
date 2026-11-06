# Prepare genuine hosted PDF pagination execution

The actual unsigned Release app, app tests and UI tests compile with both native
support and PDF opt-in conditions. No app or native helper ran locally. All330
compliance controls, source inventory, strict format/lint, five fail-closed PDF
receipt controls and three owned-executor controls pass. Both original print
test function bodies remain byte-identical to main.

The first compile failed because the support condition was absent and the
Testing trait could not call a MainActor-only switch. Its complete log is
retained. The final switch reads only a build condition and is nonisolated.
No shipping source, public interface, parser, dependency or budget changed.

Hosted execution remains unverified. The E08 combined candidate must execute
all9 original PDF functions in Release with a normal owned exit under600s, plus
full normal CI and final source/pin review. Neither compile-only nor pure receipt
controls establish PDF output, native Cancel/progress or a final RC pass.
