import Foundation

extension Array {
    func get(_ index: Int) -> Element? {
        if index >= 0 && index < count {
            return self[index]
        }
        return nil
    }
}

extension Sequence {
    func deduplicate<K: Hashable>(_ key: (Element) -> K) -> [Element] {
        var seen = Set<K>()
        return compactMap { el in
            let k = key(el)
            if seen.contains(k) {
                return nil
            }
            seen.insert(k)
            return el
        }
    }
}
