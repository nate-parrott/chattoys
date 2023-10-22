import Foundation

public extension AsyncThrowingStream where Failure == (any Error) {
    func mapSimple<E2>(_ block: @escaping (Element) -> E2) -> AsyncThrowingStream<E2, Failure> {
        mapFilterSimple { block($0) }
    }

    func mapFilterSimple<E2>(_ block: @escaping (Element) -> E2?) -> AsyncThrowingStream<E2, Failure> {
        AsyncThrowingStream<E2, Failure> { cont in
            Task {
                do {
                    for try await item in self {
                        if let mapped = block(item) {
                            cont.yield(mapped)
                        }
                    }
                    cont.finish()
                } catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
    }

    static func just(_ block: @escaping () async throws -> Element) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream<Element, Error> { cont in
            Task {
                do {
                    let res = try await block()
                    cont.yield(res)
                    cont.finish()
                } catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
    }
}

public extension AsyncStream {
    func mapSimple<E2>(_ block: @escaping (Element) -> E2) -> AsyncStream<E2> {
        mapFilterSimple { block($0) }
    }

    func mapFilterSimple<E2>(_ block: @escaping (Element) -> E2?) -> AsyncStream<E2> {
        AsyncStream<E2> { cont in
            Task {
                for await item in self {
                    if let mapped = block(item) {
                        cont.yield(mapped)
                    }
                }
                cont.finish()
            }
        }
    }

    static func just(_ block: @escaping () async -> Element) -> AsyncStream<Element> {
        AsyncStream<Element> { cont in
            Task {
                let res = await block()
                cont.yield(res)
                cont.finish()
            }
        }
    }
}

public extension AsyncSequence {
    var asStream: AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { cont in
            Task {
                do {
                    for try await item in self {
                        cont.yield(item)
                    }
                    cont.finish()
                } catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
    }
}

public extension AsyncSequence where Element: Equatable {
    func removeDuplicates() -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { cont in
            Task {
                var prev: Element?
                do {
                    for try await item in self {
                        if item != prev {
                            cont.yield(item)
                        }
                        prev = item
                    }
                    cont.finish()
                } catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
    }
}

public extension AsyncSequence where Element: RandomAccessCollection, Element.Element: Equatable {
    // Takes a sequence of arrays and unwraps it into a sequence of elements, as they are added
    func unwind() -> AsyncThrowingStream<Element.Element, Error> {
        AsyncThrowingStream { cont in
            Task {
                do {
                    var prev = [Element.Element]()
                    for try await item in self {
                        for i in item {
                            if !prev.contains(i) {
                                cont.yield(i)
                            }
                        }
                        prev = Array(item)
                    }
                    cont.finish()
                } catch {
                    cont.yield(with: .failure(error))
                }
            }
        }
    }
}
