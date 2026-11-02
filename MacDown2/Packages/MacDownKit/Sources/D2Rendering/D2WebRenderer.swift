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
        poolSize: Int = 2,
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
            preparePage: Self.prepare
        )
        self.maxOutputBytes = maxOutputBytes
    }

    public func render(_ fence: D2Fence, context: D2RenderContext) async throws -> RenderedD2Diagram {
        let activePool = try availablePool()
        let diagram = try await withPoolErrorMapping {
            try await activePool.withPage { page in
                try await Self.render(fence, context: context, on: page)
            }
        }
        let byteCount = diagram.svg.utf8.count
        guard byteCount <= maxOutputBytes else {
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
    private static func render(_ fence: D2Fence, context: D2RenderContext,
                               on page: DiagramHarnessPage) async throws -> RenderedD2Diagram {
        let result = try await page.evaluate(
            "return await window.__macdownRenderD2(source, theme);",
            arguments: ["source": fence.source, "theme": context.palette.rendererArguments]
        )
        guard result.succeeded else {
            let message = result.message ?? "unknown error"
            throw D2RenderError.invalidSyntax(message)
        }
        guard let svg = result.svg else {
            throw D2RenderError.rendererUnavailable
        }
        guard result.width.isFinite, result.height.isFinite, result.width > 0, result.height > 0 else {
            throw D2RenderError.rendererUnavailable
        }
        return RenderedD2Diagram(svg: svg, naturalWidth: result.width, naturalHeight: result.height)
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
