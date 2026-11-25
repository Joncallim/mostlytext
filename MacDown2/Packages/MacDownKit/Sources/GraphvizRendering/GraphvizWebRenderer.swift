import DiagramsGraphviz
import DiagramWebKitPool
import Foundation

/// The real, WebKit-backed implementation of `GraphvizDiagramRendering`
/// (epic-21-implementation.md §3.2), built on the shared
/// `DiagramWebKitPool`/`DiagramHarnessPage` infrastructure.
public actor GraphvizWebRenderer: GraphvizDiagramRendering {
    public static let defaultMaxOutputBytes = 2 * 1024 * 1024

    private var pool: DiagramWebKitPool?
    private var retirement: (id: UUID, task: Task<Void, Never>)?
    private let poolSize: Int
    private let timeout: Duration
    private let maxOutputBytes: Int

    public init(
        poolSize: Int = 2,
        timeout: Duration = .seconds(5),
        maxOutputBytes: Int = GraphvizWebRenderer.defaultMaxOutputBytes
    ) {
        self.poolSize = poolSize
        self.timeout = timeout
        pool = DiagramWebKitPool(
            harnessResourceName: "harness",
            bundle: Bundle.module,
            poolSize: poolSize,
            timeout: timeout
        )
        self.maxOutputBytes = maxOutputBytes
    }

    public func render(_ fence: GraphvizFence,
                       context: GraphvizRenderContext) async throws -> RenderedGraphvizDiagram {
        try Task.checkCancellation()
        if let byteCount = DiagramSourceBudget.byteCountIfOversized(fence.source) {
            try Task.checkCancellation()
            throw GraphvizRenderError.sourceTooLarge(byteCount: byteCount)
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
            throw GraphvizRenderError.outputTooLarge(byteCount: byteCount)
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
        guard retirement == nil else { throw GraphvizRenderError.rendererUnavailable }
        if let pool {
            return pool
        }
        let fresh = DiagramWebKitPool(
            harnessResourceName: "harness", bundle: Bundle.module,
            poolSize: poolSize, timeout: timeout
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
    private static func render(_ fence: GraphvizFence,
                               context: GraphvizRenderContext, maxOutputBytes: Int,
                               on page: DiagramHarnessPage) async throws -> RenderedGraphvizDiagram {
        let result = try await page.evaluate(
            "return await window.__macdownRenderGraphviz(source, theme, maxOutputBytes);",
            arguments: [
                "source": fence.source,
                "theme": context.palette.rendererArguments,
                "maxOutputBytes": maxOutputBytes,
            ]
        )
        if let byteCount = result.outputTooLargeByteCount {
            throw GraphvizRenderError.outputTooLarge(byteCount: byteCount)
        }
        guard result.succeeded else {
            throw Self.failure(for: result.message)
        }
        guard let svg = result.svg else {
            throw GraphvizRenderError.rendererUnavailable
        }
        guard result.width.isFinite, result.height.isFinite, result.width > 0, result.height > 0 else {
            throw GraphvizRenderError.rendererUnavailable
        }
        return RenderedGraphvizDiagram(svg: svg, naturalWidth: result.width, naturalHeight: result.height)
    }

    /// Viz's WASM abort is an engine failure, including when the same DOT
    /// source rendered on another page. It does not diagnose authored syntax.
    static func failure(for message: String?) -> GraphvizRenderError {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rendererUnavailable
        }
        // The viewport refusal comes from our generated SVG guard after Viz
        // accepted the authored DOT. It is a resource failure, not syntax.
        if message == "diagram exceeds vector viewport limit" || message.hasPrefix("Aborted()") {
            return .rendererUnavailable
        }
        return .invalidSyntax(message)
    }

    private func withPoolErrorMapping<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch DiagramPoolError.timedOut {
            throw GraphvizRenderError.timedOut
        } catch DiagramPoolError.pageUnavailable {
            throw GraphvizRenderError.rendererUnavailable
        }
    }
}
