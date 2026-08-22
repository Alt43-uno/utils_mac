import Foundation

/// Minimal LRU cache. Screenshot bitmaps are big enough that unbounded caching
/// would grow the resident set by hundreds of megabytes over a session.
final class LRUCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    subscript(key: Key) -> Value? {
        get {
            guard let value = storage[key] else { return nil }
            touch(key)
            return value
        }
        set {
            if let newValue {
                storage[key] = newValue
                touch(key)
                while order.count > capacity, let oldest = order.first {
                    order.removeFirst()
                    storage.removeValue(forKey: oldest)
                }
            } else {
                storage.removeValue(forKey: key)
                order.removeAll { $0 == key }
            }
        }
    }

    func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    private func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }
}
