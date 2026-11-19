import Diagrams
import DiagramWebKitPool
import Foundation
import OSLog

/// Renders Mermaid in a bounded, offscreen WebKit pool. The shared pool owns
/// cancellation, construction and once-settled script evaluation. Admission
/// closes during shutdown; a new pool starts only after the old one retires.
public actor MermaidWebRenderer: MermaidDiagramRendering {
    public static let defaultMaxOutputBytes = 2 * 1024 * 1024
    private static let logger = Logger(subsystem: "app.mostlytext.diagram", category: "mermaid")

    private let maxOutputBytes: Int
    private let includeRaster: Bool
    private let makePool: @Sendable () -> DiagramWebKitPool
    private var pool: DiagramWebKitPool?
    private var retirement: (id: UUID, task: Task<Void, Never>)?

    public init(
        poolSize: Int = 2,
        timeout: Duration = .seconds(5),
        maxOutputBytes: Int = MermaidWebRenderer.defaultMaxOutputBytes,
        includeRaster: Bool = true
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
        self.includeRaster = includeRaster
        pool = makePool()
    }

    /// Supplies deterministic page factories for lifecycle tests.
    init(
        pool: DiagramWebKitPool,
        makePool: @escaping @Sendable () -> DiagramWebKitPool,
        maxOutputBytes: Int = MermaidWebRenderer.defaultMaxOutputBytes,
        includeRaster: Bool = true
    ) {
        self.pool = pool
        self.makePool = makePool
        self.maxOutputBytes = maxOutputBytes
        self.includeRaster = includeRaster
    }

    public func render(_ fence: MermaidFence, context: MermaidRenderContext) async throws -> RenderedMermaidDiagram {
        try Task.checkCancellation()
        if let byteCount = DiagramSourceBudget.byteCountIfOversized(fence.source) {
            try Task.checkCancellation()
            throw MermaidRenderError.sourceTooLarge(byteCount: byteCount)
        }
        let activePool = try availablePool()
        let options = (limit: maxOutputBytes, raster: includeRaster)
        do {
            let result = try await activePool.withPage { page in
                try await page.evaluate(
                    "return await window.__macdownRenderMermaid(source, theme, maxOutputBytes, includeRaster);",
                    arguments: [
                        "source": fence.source,
                        "theme": context.palette.rendererArguments,
                        "maxOutputBytes": options.limit,
                        "includeRaster": options.raster,
                    ]
                )
            }
            if let byteCount = result.outputTooLargeByteCount {
                throw MermaidRenderError.outputTooLarge(byteCount: byteCount)
            }
            guard result.succeeded else {
                throw Self.failure(for: result.message ?? "unknown error")
            }
            guard let svg = result.svg else {
                throw Self.unavailable("missing SVG")
            }
            guard result.width.isFinite, result.height.isFinite, result.width > 0, result.height > 0 else {
                throw Self.unavailable("invalid dimensions")
            }
            let byteCount = svg.utf8.count
            guard byteCount <= options.limit else {
                throw MermaidRenderError.outputTooLarge(byteCount: byteCount)
            }
            let pngData = result.pngBase64.flatMap { Data(base64Encoded: $0) }
            if let pngData, pngData.count > options.limit {
                throw MermaidRenderError.outputTooLarge(byteCount: pngData.count)
            }
            return RenderedMermaidDiagram(
                svg: svg,
                pngData: pngData,
                naturalWidth: result.width,
                naturalHeight: result.height
            )
        } catch DiagramPoolError.timedOut {
            throw MermaidRenderError.timedOut
        } catch DiagramPoolError.pageUnavailable {
            throw Self.unavailable("page unavailable")
        }
    }

    private static func unavailable(_ phase: String) -> MermaidRenderError {
        logger.error("Mermaid runtime unavailable: \(phase, privacy: .public)")
        return .rendererUnavailable
    }

    /// A completed SVG can exceed the bounded preview raster dimensions.
    /// That is a renderer capacity refusal, not a Mermaid parse diagnostic.
    static func failure(for message: String) -> MermaidRenderError {
        message == "diagram exceeds raster pixel limit" ? .rendererUnavailable : .invalidSyntax(message)
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
