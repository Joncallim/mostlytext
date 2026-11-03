import Foundation

/// Original UTF-16 paragraph coordinates, read in bounded chunks rather
/// than one Objective-C character lookup per unit. Other line breaks belong to
/// the wrap estimator, not this paragraph boundary contract.
enum HeightParagraphScanner {
    static let chunkCapacity = 16384

    static func forEach(in string: NSString, _ body: (NSRange) -> Void) {
        let length = string.length
        guard length > 0 else { body(NSRange(location: 0, length: 0)); return }
        var buffer = [unichar](repeating: 0, count: min(length, chunkCapacity))
        var start = 0
        var offset = 0
        var followsCR = false
        while offset < length {
            let count = min(buffer.count, length - offset)
            buffer.withUnsafeMutableBufferPointer { storage in
                guard let units = storage.baseAddress else { return }
                string.getCharacters(units, range: NSRange(location: offset, length: count))
                var local = 0
                while local < count {
                    let index = offset + local
                    let unit = units[local]
                    local += 1
                    if followsCR {
                        followsCR = false
                        if unit == 0x0A {
                            start = index + 1
                            continue
                        }
                    }
                    if unit == 0x0A || unit == 0x0D || unit == 0x2029 {
                        body(NSRange(location: start, length: index - start))
                        start = index + 1
                        followsCR = unit == 0x0D
                    }
                }
            }
            offset += count
        }
        body(NSRange(location: start, length: length - start))
    }
}
