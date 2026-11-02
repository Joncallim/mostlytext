import AppSettings
import Foundation
import Observation

/// Required installation work precedes the independently skippable original-
/// MacDown offer. No normal owner may exist until this controller is ready.
@MainActor
@Observable
final class ApplicationMigrationStartup {
    enum Phase { case migrating, preservedReview, optionalImport, blocked, ready }
    private(set) var phase: Phase
    private(set) var optionalImport: LegacyImportStartup?
    private(set) var locations: ApplicationStorageLocations?
    private(set) var reviewDirectory: URL?
    private var publishedInstallation: PreparedInstallationMigration?
    private(set) var hasSeparateDevelopmentBackup = false
    var didBecomeReady: (() -> Void)?
    var canQuitWithoutSession: Bool {
        phase == .blocked || phase == .preservedReview ||
            (phase == .optionalImport && optionalImport?.canQuitWithoutSession == true)
    }

    private let publisher: InstallationPreferencesPublisher
    private let makeInstallation: @Sendable () async throws -> InstallationMigration
    private let source: @MainActor () throws -> InstallationPreferences
    private let validate: @MainActor (ApplicationStorageLocations, InstallationPreferences) throws -> Void
    private let relocate: @MainActor (ApplicationStorageLocations) async throws -> Void
    private let makeOptional: @MainActor (Bool) -> LegacyImportStartup
    private var installation: InstallationMigration?
    private var running = false

    init(disabled: Bool, publisher: InstallationPreferencesPublisher,
         makeInstallation: @escaping @Sendable () async throws -> InstallationMigration,
         source: @escaping @MainActor () throws -> InstallationPreferences,
         validate: @escaping @MainActor (ApplicationStorageLocations, InstallationPreferences) throws -> Void,
         relocate: @escaping @MainActor (ApplicationStorageLocations) async throws -> Void,
         makeOptional: @escaping @MainActor (Bool) -> LegacyImportStartup) {
        phase = disabled ? .ready : .migrating
        self.publisher = publisher; self.makeInstallation = makeInstallation; self.source = source
        self.validate = validate; self.relocate = relocate; self.makeOptional = makeOptional
    }

    func begin() async {
        guard !running, phase == .migrating || phase == .blocked else { return }
        running = true; phase = .migrating
        defer { running = false }
        do {
            if let installation {
                // Retry may replan only before this transaction changed defaults.
                _ = try await installation.retireUnapplied(currentPreferences: publisher.snapshot())
                await installation.close()
            }
            let installation = try await makeInstallation()
            self.installation = installation
            let prepared: PreparedInstallationMigration = if let resumed = try await installation
                .resumePublished() {
                resumed
            } else {
                try await installation.prepare(sourcePreferences: source(), currentPreferences: publisher.snapshot())
            }
            reviewDirectory = prepared.locations.preservedDirectory
            let published = try await publishIfNeeded(prepared, installation: installation)
            try validate(published.locations, publisher.snapshot())
            if try await !installation.pathsAcknowledged(published) {
                if published.adoptsDevelopment {
                    try await relocate(published.locations)
                }
                try validate(published.locations, publisher.snapshot())
                try await installation.acknowledgePaths(published)
            }
            locations = published.locations
            hasSeparateDevelopmentBackup = published.hasPreservedDevelopmentState && !published.adoptsDevelopment
            publishedInstallation = published
            if hasSeparateDevelopmentBackup, try await !installation.reviewAcknowledged(published) {
                phase = .preservedReview
            } else {
                await startOptional(published)
            }
        } catch { phase = .blocked }
    }

    private func publishIfNeeded(_ prepared: PreparedInstallationMigration,
                                 installation: InstallationMigration) async throws -> PreparedInstallationMigration {
        var published = prepared
        if !prepared.isComplete {
            try validate(prepared.locations, prepared.desiredPreferences)
            published = try await installation.publishFiles(prepared)
            reviewDirectory = published.locations.preservedDirectory
            if !published.preferencesAcknowledged {
                try await installation.revalidateSources(published)
                try Task.checkCancellation()
                try publisher.publish(desired: published.desiredPreferences,
                                      before: published.beforePreferenceDigests) {
                    guard try source().digests == published.sourcePreferenceDigests else {
                        throw UserDefaultsAppSettingsStore.LegacyPublicationFailure.sourceChanged
                    }
                }
                try await installation.acknowledgePreferences(published)
            }
            try await installation.complete(published)
        }
        return published
    }

    func continueWithCurrentInstallation() async {
        guard phase == .preservedReview, let installation, let publishedInstallation else { return }
        phase = .migrating
        do {
            try await installation.acknowledgeReview(publishedInstallation)
            await startOptional(publishedInstallation)
        } catch { phase = .blocked }
    }

    private func startOptional(_ published: PreparedInstallationMigration) async {
        let optional = makeOptional(published.completedOriginalImport)
        optionalImport = optional
        optional.didBecomeReady = { [weak self] in self?.finish() }
        phase = .optionalImport
        if optional.phase == .ready {
            finish()
        } else {
            await optional.begin()
        }
    }

    private func finish() {
        guard phase != .ready, locations != nil else { return }
        phase = .ready
        didBecomeReady?()
    }
}
