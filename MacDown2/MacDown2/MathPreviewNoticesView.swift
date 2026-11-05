import Math
import SwiftUI

struct MathPreviewNoticesView: View {
    let display: MathPreviewDisplay?
    let action: @MainActor (UUID, UUID) -> Void
    @State private var isPresented = false

    var body: some View {
        if let display, !display.notices.isEmpty {
            Button {
                isPresented = true
            } label: {
                Label("\(display.notices.count)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: MathDiagnosticText.noticesTitle))
            .accessibilityIdentifier("mathPreviewNotices")
            .popover(isPresented: $isPresented) {
                List(display.notices) { notice in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: notice.message)
                        if let sourceID = notice.sourceID {
                            Button {
                                action(display.content.id, sourceID)
                                isPresented = false
                            } label: {
                                Text(verbatim: MathDiagnosticText.sourceAction)
                            }
                            .accessibilityIdentifier("mathPreviewSourceAction")
                        }
                    }
                    .font(.caption)
                    .accessibilityElement(children: .contain)
                }
                .frame(minWidth: 320, minHeight: 120)
                .accessibilityIdentifier("mathPreviewNoticesList")
            }
        }
    }
}
