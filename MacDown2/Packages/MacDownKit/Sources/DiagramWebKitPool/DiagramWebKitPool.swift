import Foundation

/// A bounded pool of `DiagramHarnessPage`s, generalized from
/// `MermaidWebRenderer`'s own pool/checkout/checkin/timeout logic
/// (epic-20-implementation.md §11) — extracted here because that part,
/// unlike JS invocation shape or result parsing, is genuinely identical
/// across every renderer built on `DiagramHarnessPage`
/// (epic-21-implementation.md §3.1). Each language's own renderer owns
/// one `DiagramWebKitPool` instance and its own bundled harness resource;
/// this type knows nothing about what JS a particular language runs.
///
/// Process-lifetime by design, not document-lifetime — pool warm-up
/// (loading a harness into a fresh page) is the expensive part, and
/// nothing about a single document owns a pool exclusively.
public actor DiagramWebKitPool {
    /// Queueing and cold WebKit navigation may outlast one diagram's script
    /// budget. Six requests through the standard two-slot pool can wait for
    /// two earlier five-second evaluation windows before acquiring a page.
    public static let defaultAdmissionTimeout: Duration = .seconds(15)

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Int, any Error>
    }

    private let poolSize: Int
    private let timeout: Duration
    private let admissionTimeout: Duration
    private let makePage: @Sendable () async throws -> DiagramHarnessPage
    private let retirePage: @Sendable (DiagramHarnessPage) async -> Void

    private var slots: [DiagramHarnessPage?]
    private var busy: [Bool]
    private var waiters: [Waiter] = []
    private var constructing: [Int: Task<DiagramHarnessPage, any Error>] = [:]
    private var retiring: [UUID: Task<Void, Never>] = [:]
    private var shutdownTask: Task<Void, Never>?
    private var closed = false

    var isShuttingDown: Bool {
        closed
    }

    public init(
        harnessResourceName: String,
        bundle: Bundle,
        poolSize: Int = 2,
        timeout: Duration = .seconds(5),
        admissionTimeout: Duration? = nil,
        preparePage: @escaping @Sendable (DiagramHarnessPage) async throws -> Void = { _ in }
    ) {
        self.init(poolSize: poolSize, timeout: timeout, admissionTimeout: admissionTimeout) {
            let page = try await DiagramHarnessPage.make(harnessResourceName: harnessResourceName, bundle: bundle)
            do {
                try await preparePage(page)
                try Task.checkCancellation()
                return page
            } catch {
                await page.teardown()
                throw error
            }
        }
    }

    /// Allows lifecycle tests to hold construction at a precise suspension point.
    /// Production always uses the bundled, contained harness factory above.
    init(
        poolSize: Int,
        timeout: Duration,
        admissionTimeout: Duration? = nil,
        makePage: @escaping @Sendable () async throws -> DiagramHarnessPage,
        retirePage: @escaping @Sendable (DiagramHarnessPage) async -> Void = { @MainActor in $0.teardown() }
    ) {
        self.poolSize = max(1, poolSize)
        self.timeout = timeout
        // A caller that deliberately raises the execution budget must not
        // silently receive a shorter admission deadline than before.
        self.admissionTimeout = admissionTimeout ?? max(timeout, Self.defaultAdmissionTimeout)
        self.makePage = makePage
        self.retirePage = retirePage
        slots = Array(repeating: nil, count: self.poolSize)
        busy = Array(repeating: false, count: self.poolSize)
    }

    /// The separately bounded admission deadline starts before a request
    /// waits for a slot or constructs a page. Once acquired, JavaScript
    /// evaluation keeps its own five-second default deadline.
    /// On timeout the cancelled worker still owns its slot until cleanup;
    /// explicit caller cancellation waits for that teardown.
    public func withPage<T: Sendable>(
        _ body: @escaping @Sendable (DiagramHarnessPage) async throws -> T
    ) async throws -> T {
        try await DiagramTimeoutRace.runWaitingForCancellationCleanupUntilMilestone(
            timeout: admissionTimeout,
            timeoutError: DiagramPoolError.timedOut
        ) { acquired in
            try await self.runWithPage(body, acquired: acquired)
        }
    }

    private func runWithPage<T: Sendable>(
        _ body: @escaping @Sendable (DiagramHarnessPage) async throws -> T,
        acquired: @Sendable () -> Void
    ) async throws -> T {
        let index = try await checkout()
        let page: DiagramHarnessPage
        do {
            try Task.checkCancellation()
            page = try await self.page(at: index)
            guard !closed else { throw DiagramPoolError.pageUnavailable }
            try Task.checkCancellation()
        } catch {
            if error is CancellationError, let page = slots[index] {
                slots[index] = nil
                let retirement = beginRetirement(page)
                await finishRetirement(retirement)
            }
            checkin(index)
            throw error
        }
        acquired()
        do {
            let result = try await DiagramTimeoutRace.run(
                timeout: timeout,
                timeoutError: DiagramPoolError.timedOut
            ) { try await body(page) }
            guard !closed else { throw DiagramPoolError.pageUnavailable }
            checkin(index)
            return result
        } catch {
            if error is CancellationError || (error as? DiagramPoolError) == .timedOut {
                slots[index] = nil
                let retirement = beginRetirement(page)
                await finishRetirement(retirement)
            }
            checkin(index)
            throw error
        }
    }

    /// Tears down every pooled page. Called on app termination and in
    /// tests; not required between individual documents.
    public func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        guard !closed else { return }
        closed = true
        let queued = waiters
        waiters.removeAll()
        for waiter in queued {
            waiter.continuation.resume(throwing: DiagramPoolError.pageUnavailable)
        }
        let pages = slots.compactMap(\.self)
        let builds = Array(constructing.values)
        let earlierRetirements = Array(retiring.values)
        let retire = retirePage
        constructing.removeAll()
        slots = Array(repeating: nil, count: poolSize)
        let task = Task {
            for build in builds {
                build.cancel()
            }
            for page in pages {
                await retire(page)
            }
            for build in builds {
                if case let .success(page) = await build.result {
                    await retire(page)
                }
            }
            for retirement in earlierRetirements {
                await retirement.value
            }
        }
        shutdownTask = task
        await task.value
        shutdownTask = nil
    }

    private func page(at index: Int) async throws -> DiagramHarnessPage {
        guard !closed else { throw DiagramPoolError.pageUnavailable }
        if let existing = slots[index] {
            if await !existing.isTerminated {
                guard !closed else { throw DiagramPoolError.pageUnavailable }
                return existing
            }
            await existing.teardown()
            slots[index] = nil
        }
        guard !closed else { throw DiagramPoolError.pageUnavailable }
        let factory = makePage
        let construction = Task { try await factory() }
        constructing[index] = construction
        let page: DiagramHarnessPage
        do {
            page = try await withTaskCancellationHandler {
                try await construction.value
            } onCancel: {
                construction.cancel()
            }
        } catch {
            constructing[index] = nil
            throw error
        }
        constructing[index] = nil
        guard !closed else {
            // Shutdown owns every registered construction, including this page.
            throw DiagramPoolError.pageUnavailable
        }
        if Task.isCancelled {
            let retirement = beginRetirement(page)
            await finishRetirement(retirement)
            throw CancellationError()
        }
        slots[index] = page
        return page
    }

    private func checkout() async throws -> Int {
        try Task.checkCancellation()
        guard !closed else { throw DiagramPoolError.pageUnavailable }
        if let index = busy.firstIndex(of: false) {
            busy[index] = true
            return index
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelCheckout(id) }
        }
    }

    private func cancelCheckout(_ id: UUID) {
        guard let position = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: position).continuation.resume(throwing: CancellationError())
    }

    /// Register retirement before removing the last slot/construction owner
    /// across an actor suspension, so shutdown can drain that page as well.
    private func beginRetirement(_ page: DiagramHarnessPage) -> (id: UUID, task: Task<Void, Never>) {
        let id = UUID()
        let retire = retirePage
        let task = Task { await retire(page) }
        retiring[id] = task
        return (id, task)
    }

    private func finishRetirement(_ retirement: (id: UUID, task: Task<Void, Never>)) async {
        await retirement.task.value
        retiring[retirement.id] = nil
    }

    /// Hands the slot directly to the next waiter if one is queued (it
    /// stays marked busy — ownership transfers without ever appearing
    /// free); otherwise marks it free.
    private func checkin(_ index: Int) {
        guard !closed else {
            busy[index] = false
            return
        }
        guard waiters.isEmpty else {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume(returning: index)
            return
        }
        busy[index] = false
    }
}
