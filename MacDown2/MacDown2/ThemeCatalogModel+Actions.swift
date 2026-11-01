import Foundation
import LocalResourceAccess
import Themes

extension ThemeCatalogModel {
    func importTheme(from url: URL) async {
        guard canManage, let store else { return }
        isBusy = true
        problem = nil
        let token = generation
        defer { finishMutation() }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let cancellation = ResourceCancellation()
        readCancellation = cancellation
        let reading = Task.detached(priority: .utility) {
            let lease = try FileLease(opening: url)
            defer { lease.close() }
            return try ContainedResourceReader.read(lease, maxBytes: ThemeFile.maximumFileBytes,
                                                    cancellation: cancellation).bytes
        }
        do {
            let data = try await withTaskCancellationHandler {
                try await reading.value
            } onCancel: { cancellation.cancel(); reading.cancel() }
            guard generation == token, !Task.isCancelled else { return }
            let prepared = try await store.prepareImport(data)
            guard generation == token, !Task.isCancelled else { return }
            if case .conflictingIdentity = prepared.plan.situation {
                pendingImport = prepared
                return
            }
            let choice: ThemeImportPlan.Choice = if case .alreadyInstalled = prepared.plan.situation {
                .useExisting
            } else {
                .install
            }
            let result = try await store.commitImport(prepared, choice: choice)
            guard generation == token else { return }
            accept(result, select: true)
        } catch {
            if generation == token, !(error is CancellationError) {
                problem = error as? ResourceReadError == .oversized
                    ? String(localized: "Theme files are limited to 64 KiB.") : Self.message(for: error)
            }
        }
    }

    /// Consume the confirmation synchronously, before SwiftUI dismisses it.
    func resolvePendingImport(_ choice: ThemeImportPlan.Choice) {
        guard status == .ready, !isBusy, let prepared = pendingImport, let store else { return }
        pendingImport = nil
        isBusy = true
        problem = nil
        let token = generation
        confirmationTask = Task { [self] in
            defer { finishMutation() }
            do {
                try Task.checkCancellation()
                let result = try await store.commitImport(prepared, choice: choice)
                guard generation == token else { return }
                accept(result, select: true)
            } catch {
                if generation == token, !(error is CancellationError) {
                    problem = Self.message(for: error)
                }
            }
        }
    }

    func duplicate(_ theme: Theme) async {
        guard canManage, let store else { return }
        isBusy = true
        problem = nil
        let token = generation
        defer { finishMutation() }
        do {
            var copy = theme
            copy.name = copyName(for: theme.name)
            let file = try ThemeFile(theme: copy)
            let prepared = try await store.prepareImport(file.encoded())
            guard generation == token, !Task.isCancelled else { return }
            let result = try await store.commitImport(prepared, choice: .importCopy)
            guard generation == token else { return }
            accept(result, select: true)
        } catch {
            if generation == token {
                problem = Self.message(for: error)
            }
        }
    }

    func prepareDeletion(_ id: UUID) async {
        guard canManage, let store else { return }
        isBusy = true
        problem = nil
        let token = generation
        defer { finishMutation() }
        do {
            let prepared = try await store.prepareDeletion(id: id)
            guard generation == token, !Task.isCancelled else { return }
            pendingDeletion = prepared
        } catch {
            if generation == token {
                problem = Self.message(for: error)
            }
        }
    }

    func confirmDeletion() {
        guard status == .ready, !isBusy, let prepared = pendingDeletion, let store else { return }
        pendingDeletion = nil
        isBusy = true
        problem = nil
        let token = generation
        confirmationTask = Task { [self] in
            defer { finishMutation() }
            do {
                try Task.checkCancellation()
                let result = try await store.delete(prepared)
                guard generation == token else { return }
                accept(result, select: false)
            } catch {
                if generation == token, !(error is CancellationError) {
                    problem = Self.message(for: error)
                }
            }
        }
    }

    private func accept(_ mutation: ThemeCatalogMutation, select: Bool) {
        publish(mutation.state)
        if select, let file = mutation.state.catalog.customTheme(id: mutation.affectedID) {
            controller.select(file.theme)
            affectedThemeID = file.theme.id
        } else {
            affectedThemeID = nil
        }
        operationID = UUID()
        if mutation.warnings.contains(.directoryChanged) || mutation.warnings.contains(.refreshFailed) {
            status = .unavailable
        }
        if !mutation.warnings.isEmpty {
            problem =
                String(
                    localized: "The theme operation completed, but storage needs attention. Review the Themes folder."
                )
        }
    }

    private func copyName(for name: String) -> String {
        let suffix = " " + String(localized: "Copy")
        let existing = Set(controller.available.map(\.name))
        for number in 1 ... 257 {
            let ending = suffix + (number == 1 ? "" : " \(number)")
            var base = name
            while !base.isEmpty, (base + ending).unicodeScalars.count > 80 {
                base.removeLast()
            }
            let candidate = base.trimmingCharacters(in: .whitespaces) + ending
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return String(localized: "Custom Theme")
    }
}
