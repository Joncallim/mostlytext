import Foundation
import SwiftUIMath

/// The same provisional source/parser limits apply to Preview and Export.
public struct MathProcessingPolicy: Sendable, Equatable {
    public let maximumSpanCount: Int
    public let bodyLimits: SwiftUIMath.Math.BodyLimits

    public static let standard = MathProcessingPolicy(
        maximumSpanCount: 512,
        bodyLimits: .init(maximumUTF16Length: 8192, maximumDepth: 64, maximumParserSteps: 100_000)
    )
}
