import Foundation
import MarkdownEngine
import SwiftUI

/// Native links avoid depending on an inline text renderer's accessibility
/// rotor to activate source navigation. The host supplies only its current index.
struct NativeHeadingTOC: View {
    struct Entry: Identifiable {
        let heading: HeadingAnchorIndex.Heading
        let depth: Int
        let destination: URL
        var id: Int {
            heading.ordinal
        }
    }

    let entries: [Entry]

    init(index: HeadingAnchorIndex) {
        var levels: [Int] = []
        entries = index.headings.compactMap { heading in
            while let last = levels.last, last >= heading.level {
                levels.removeLast()
            }
            let depth = levels.count
            levels.append(heading.level)
            var components = URLComponents()
            // Set the raw fragment once; URLComponents owns percent encoding.
            components.fragment = heading.fragment
            guard let destination = components.url else { return nil }
            return Entry(heading: heading, depth: depth, destination: destination)
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "•").accessibilityHidden(true)
                    Link(destination: entry.destination) {
                        Text(verbatim: entry.heading.title)
                            .multilineTextAlignment(.leading)
                    }
                    .accessibilityLabel(Text(verbatim: entry.heading.title))
                    .accessibilityAddTraits(.isLink)
                }
                .padding(.leading, CGFloat(entry.depth) * 20)
            }
        }
    }
}
