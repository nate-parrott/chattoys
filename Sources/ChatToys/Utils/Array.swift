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

// From https://stackoverflow.com/questions/65746299/how-do-you-find-the-top-3-maximum-values-in-a-swift-dictionary
extension Collection {

  /// - Complexity: O(k log k + nk)
  public func sortedPrefix(
    _ count: Int,
    by areInIncreasingOrder: (Element, Element) throws -> Bool
  ) rethrows -> [Self.Element] {
    assert(count >= 0, """
      Cannot prefix with a negative amount of elements!
      """
    )

    guard count > 0 else {
      return []
    }

    let prefixCount = Swift.min(count, self.count)

    guard prefixCount < (self.count / 10) else {
      return Array(try sorted(by: areInIncreasingOrder).prefix(prefixCount))
    }

    var result = try self.prefix(prefixCount).sorted(by: areInIncreasingOrder)

    for e in self.dropFirst(prefixCount) {
      if let last = result.last, try areInIncreasingOrder(last, e) {
        continue
      }
      let insertionIndex =
        try result.partitioningIndex { try areInIncreasingOrder(e, $0) }
      let isLastElement = insertionIndex == result.endIndex
      result.removeLast()
      if isLastElement {
        result.append(e)
      } else {
        result.insert(e, at: insertionIndex)
      }
    }

    return result
  }
}

extension Collection {
    /// Returns the index of the first element in the collection that matches
    /// the predicate.
    ///
    /// The collection must already be partitioned according to the predicate.
    /// That is, there should be an index `i` where for every element in
    /// `collection[..<i]` the predicate is `false`, and for every element
    /// in `collection[i...]` the predicate is `true`.
    ///
    /// - Parameter belongsInSecondPartition: A predicate that partitions the
    ///   collection.
    /// - Returns: The index of the first element in the collection for which
    ///   `predicate` returns `true`.
    ///
    /// - Complexity: O(log *n*), where *n* is the length of this collection if
    ///   the collection conforms to `RandomAccessCollection`, otherwise O(*n*).
    @inlinable
    public func partitioningIndex(
      where belongsInSecondPartition: (Element) throws -> Bool
    ) rethrows -> Index {
      var n = count
      var l = startIndex

      while n > 0 {
        let half = n / 2
        let mid = index(l, offsetBy: half)
        if try belongsInSecondPartition(self[mid]) {
          n = half
        } else {
          l = index(after: mid)
          n -= half + 1
        }
      }
      return l
    }
  }
