import Diagrams
import DiagramWebKitPool
import Foundation

/// Renders Mermaid in a bounded, offscreen WebKit pool. The shared pool owns
/// cancellation, construction and once-settled script evaluation. Admission
/// closes during shutdown; a new pool starts only after the old one retires.
public actor MermaidWebRenderer: MermaidDiagramRendering {
    public static let defaultMaxOutputBytes = 2 * 1024 * 1024

    private let maxOutputBytes: Int
    private let makePool: @Sendable () -> DiagramWebKitPool
    private var pool: DiagramWebKitPool?
    private var retirement: (id: UUID, task: Task<Void, Never>)?

    public init(
        poolSize: Int = 2,
        timeout: Duration = .seconds(5),
        maxOutputBytes: Int = MermaidWebRenderer.defaultMaxOutputBytes
    ) {
        let boundedSize = max(1, poolSize)
        makePool = {
            DiagramWebKitPool(
                harnessResourceName: "harness",
                bundle: Bundle.module,
                poolSize: boundedSize,
                timeout: timeout
            )
        }
        self.maxOutputBytes = maxOutputBytes
        pool = makePool()
    }

    /// Supplies deterministic page factories for lifecycle tests.
    init(
        pool: DiagramWebKitPool,
        makePool: @escaping @Sendable () -> DiagramWebKitPool,
        maxOutputBytes: Int = MermaidWebRenderer.defaultMaxOutputBytes
    ) {
        self.pool = pool
        self.makePool = makePool
        self.maxOutputBytes = maxOutputBytes
    }

    public func render(_ fence: MermaidFence, context: MermaidRenderContext) async throws -> RenderedMermaidDiagram {
        if let byteCount = DiagramSourceBudget.byteCountIfOversized(fence.source) {
            throw MermaidRenderError.sourceTooLarge(byteCount: byteCount)
        }
        let activePool = try availablePool()
        let outputLimit = maxOutputBytes
        do {
            let result = try await activePool.withPage { page in
                try await page.evaluate(
                    "return await window.__macdownRenderMermaid(source, theme, maxOutputBytes);",
                    arguments: [
                        "source": fence.source,
                        "theme": context.palette.rendererArguments,
                        "maxOutputBytes": outputLimit,
                    ]
                )
            }
            if let byteCount = result.outputTooLargeByteCount {
                throw MermaidRenderError.outputTooLarge(byteCount: byteCount)
            }
            guard result.succeeded else {
                throw MermaidRenderError.invalidSyntax(result.message ?? "unknown error")
            }
            guard let svg = result.svg else {
                throw MermaidRenderError.rendererUnavailable
            }
            guard result.width.isFinite, result.height.isFinite, result.width > 0, result.height > 0 else {
                throw MermaidRenderError.rendererUnavailable
            }
            let byteCount = svg.utf8.count
            guard byteCount <= outputLimit else {
                throw MermaidRenderError.outputTooLarge(byteCount: byteCount)
            }
            return RenderedMermaidDiagram(
                svg: svg,
                pngData: result.pngBase64.flatMap { Data(base64Encoded: $0) },
                naturalWidth: result.width,
                naturalHeight: result.height
            )
        } catch DiagramPoolError.timedOut {
            throw MermaidRenderError.timedOut
        } catch DiagramPoolError.pageUnavailable {
            throw MermaidRenderError.rendererUnavailable
        }
    }

    /// Closes admission to the current generation and waits for its pages
    /// and constructions to retire. A later render may create a fresh pool.
    public func shutdown() async {
        if retirement != nil {
            await finishRetirement()
            return
        }
        guard let oldPool = pool else { return }
        pool = nil
        retirement = (UUID(), Task { await oldPool.shutdown() })
        await finishRetirement()
    }

    private func availablePool() throws -> DiagramWebKitPool {
        try Task.checkCancellation()
        guard retirement == nil else {
            throw MermaidRenderError.rendererUnavailable
        }
        if let pool {
            return pool
        }
        let fresh = makePool()
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
}
