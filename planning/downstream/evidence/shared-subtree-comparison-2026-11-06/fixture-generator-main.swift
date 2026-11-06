import Foundation
for size in [16,64,256] { let data = Data(HighlightBudgetFixture.inlineDense.markdown(utf8Bytes: size * 1024).utf8); try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("actual-inline-dense-\(size).md")) }
