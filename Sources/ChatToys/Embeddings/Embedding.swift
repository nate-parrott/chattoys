import Foundation

public struct Embedding: Hashable, Codable {
    public var vectors: [Double]
    public var provider: String // Embeddings are not comparable across different models or providers
    public var magnitude: Double

    public init(vectors: [Double], provider: String) {
        self.vectors = vectors
        self.provider = provider
        self.magnitude = computeMagnitude(vector: vectors)
    }
}

extension Embedding {
    public func cosineSimilarity(with other: Embedding) -> Double {
        #if DEBUG
        assert(provider == other.provider)
        assert(vectors.count == other.vectors.count)
        #endif
        if provider != other.provider || vectors.count != other.vectors.count {
            return 0
        }

        let denom = magnitude * other.magnitude
        if denom == 0 {
            return 0
        }

        return dotProduct(a: vectors, b: other.vectors) / denom
    }
}

// MARK: - Math

private func computeMagnitude(vector: [Double]) -> Double {
    var x: Double = 0
    for el in vector {
        x += el * el
    }
    return sqrt(x)
}

private func dotProduct(a: [Double], b: [Double]) -> Double {
    var x: Double = 0
    for (a_, b_) in zip(a, b) {
        x += a_ * b_
    }
    return x
}

//private func cosineSim(A: [Double], B: [Double]) -> Double {
//    return dot(A: A, B: B) / (magnitude(A: A) * magnitude(A: B))
//}
//
///** Dot Product **/
//private func dot(A: [Double], B: [Double]) -> Double {
//    var x: Double = 0
//    for i in 0...A.count-1 {
//        x += A[i] * B[i]
//    }
//    return x
//}
//
///** Vector Magnitude **/
//private func magnitude(A: [Double]) -> Double {
//    var x: Double = 0
//    for elt in A {
//        x += elt * elt
//    }
//    return sqrt(x)
//}
