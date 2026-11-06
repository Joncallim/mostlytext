import Testing

@MainActor
@Suite("Markdown session publication generations", .serialized)
struct MarkdownSessionPublicationTests {
    @Test func cancelPendingRejectsHeldImmediateWorkAndKeepsTheAcceptedDocument() async {
        for check in await MarkdownPublicationScenarios.cancelledImmediate() {
            #expect(check.passed, "\(check.message)")
        }
    }

    @Test func aNewerImmediateRequestRejectsOlderWorkBeforeTheNewerResultIsReady() async {
        for check in await MarkdownPublicationScenarios.supersededImmediate() {
            #expect(check.passed, "\(check.message)")
        }
    }

    @Test func aNewerDebouncedEditRejectsAnOlderImmediatePublication() async {
        for check in await MarkdownPublicationScenarios.supersededByEdit() {
            #expect(check.passed, "\(check.message)")
        }
    }
}
