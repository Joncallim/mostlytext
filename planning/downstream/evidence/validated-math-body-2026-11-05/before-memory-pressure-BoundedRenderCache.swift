/// A cache owned by DisplayProvider's existing serial lock. No independent concurrency.
/// Clear-before-insert gives a hard retained-entry ceiling; cached values are disposable.
struct BoundedRenderCache<Key: Hashable, Value> {
  private let capacity: Int
  private var entries: [Key: Value] = [:]

  init(capacity: Int) {
    precondition(capacity > 0)
    self.capacity = capacity
  }

  var count: Int { entries.count }

  func value(for key: Key) -> Value? { entries[key] }

  mutating func insert(_ value: Value, for key: Key) {
    if entries[key] == nil && entries.count >= capacity {
      entries.removeAll(keepingCapacity: true)
    }
    entries[key] = value
  }
}
