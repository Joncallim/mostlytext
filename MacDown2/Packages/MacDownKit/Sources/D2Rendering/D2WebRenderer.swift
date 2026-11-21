import DiagramsD2
import DiagramWebKitPool
import Foundation

/// The real, WebKit-backed implementation of `D2DiagramRendering`
/// (epic-21-implementation.md §3.2), built on the shared
/// `DiagramWebKitPool`/`DiagramHarnessPage` infrastructure rather than
/// reimplementing pool/checkout/timeout logic (§3.1, §3.3).
public actor D2WebRenderer: D2DiagramRendering {
    public static let defaultMaxOutputBytes = 2 * 1024 * 1024

    private var pool: DiagramWebKitPool?
    private var retirement: (id: UUID, task: Task<Void, Never>)?
    private let poolSize: Int
    private let timeout: Duration
    private let maxOutputBytes: Int

    public init(
        poolSize: Int = 1,
        timeout: Duration = .seconds(5),
        maxOutputBytes: Int = D2WebRenderer.defaultMaxOutputBytes
    ) {
        self.poolSize = poolSize
        self.timeout = timeout
        pool = DiagramWebKitPool(
            harnessResourceName: "harness",
            bundle: Bundle.module,
            poolSize: poolSize,
            timeout: timeout,
            bundledSchemeResourceNames: ["harness.html", "d2-browser.js", "render.js", "d2.wasm"],
            preparePage: Self.prepare
        )
        self.maxOutputBytes = maxOutputBytes
    }

    public func render(_ fence: D2Fence, context: D2RenderContext) async throws -> RenderedD2Diagram {
        try Task.checkCancellation()
        if let byteCount = DiagramSourceBudget.byteCountIfOversized(fence.source) {
            try Task.checkCancellation()
            throw D2RenderError.sourceTooLarge(byteCount: byteCount)
        }
        let activePool = try availablePool()
        let outputLimit = maxOutputBytes
        let diagram = try await withPoolErrorMapping {
            try await activePool.withPage { page in
                try await Self.render(fence, context: context, maxOutputBytes: outputLimit, on: page)
            }
        }
        let byteCount = diagram.svg.utf8.count
        guard byteCount <= outputLimit else {
            throw D2RenderError.outputTooLarge(byteCount: byteCount)
        }
        return diagram
    }

    public func shutdown() async {
        if retirement != nil {
            await finishRetirement()
            return
        }
        guard let retiring = pool else { return }
        pool = nil
        retirement = (UUID(), Task { await retiring.shutdown() })
        await finishRetirement()
    }

    private func availablePool() throws -> DiagramWebKitPool {
        try Task.checkCancellation()
        guard retirement == nil else { throw D2RenderError.rendererUnavailable }
        if let pool {
            return pool
        }
        let fresh = DiagramWebKitPool(
            harnessResourceName: "harness", bundle: Bundle.module,
            poolSize: poolSize, timeout: timeout,
            bundledSchemeResourceNames: ["harness.html", "d2-browser.js", "render.js", "d2.wasm"],
            preparePage: Self.prepare
        )
        pool = fresh
        return fresh
    }

    private func finishRetirement() async {
        guard let current = retirement else { return }
        await current.task.value
        if retirement?.id == current.id {
            retirement = nil
        }
    }

    @MainActor
    private static func prepare(_ page: DiagramHarnessPage) async throws {
        let result = try await page.evaluate("return await window.__macdownPrepareD2();", arguments: [:])
        guard result.succeeded else { throw D2RenderError.rendererUnavailable }
    }

    @MainActor
    private static func render(_ fence: D2Fence, context: D2RenderContext, maxOutputBytes: Int,
                               on page: DiagramHarnessPage) async throws -> RenderedD2Diagram {
        let result = try await page.evaluate(
            "return await window.__macdownRenderD2(source, theme, maxOutputBytes);",
            arguments: [
                "source": fence.source,
                "theme": context.palette.rendererArguments,
                "maxOutputBytes": maxOutputBytes,
            ]
        )
        if let byteCount = result.outputTooLargeByteCount {
            throw D2RenderError.outputTooLarge(byteCount: byteCount)
        }
        guard result.succeeded else {
            throw Self.failure(for: result.message, phase: result.failurePhase)
        }
        guard let svg = result.svg else {
            throw D2RenderError.rendererUnavailable
        }
        guard result.width.isFinite, result.height.isFinite, result.width > 0, result.height > 0 else {
            throw D2RenderError.rendererUnavailable
        }
        return RenderedD2Diagram(svg: svg, naturalWidth: result.width, naturalHeight: result.height)
    }

    static func failure(for message: String?, phase: String?) -> D2RenderError {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rendererUnavailable
        }
        // D2's compile call also runs layout. A Dagre failure can therefore
        // arrive in the compile phase for valid authored D2.
        if phase == "compile", message.hasPrefix("failed to dagre layout:") {
            return .rendererUnavailable
        }
        // Layout/runtime failures may occur for syntactically valid source.
        return phase == "compile" ? .invalidSyntax(message) : .rendererUnavailable
    }

    /// Maps the shared pool's generic errors to this language's own
    /// domain error type, matching `MermaidWebRenderer`'s own
    /// single-domain-error convention.
    private func withPoolErrorMapping<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch DiagramPoolError.timedOut {
            throw D2RenderError.timedOut
        } catch DiagramPoolError.pageUnavailable {
            throw D2RenderError.rendererUnavailable
        }
    }
}
