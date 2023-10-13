import Foundation

public struct Embedding: Hashable, Codable {
//    public var vectors: [Float]
    public var provider: String // Embeddings are not comparable across different models or providers
    public var magnitude: Float
    public var halfPrecision: Bool // float16
    fileprivate var storage: Storage
    
    public var vectors: [Float] {
        switch storage {
        case .floats(let floats):
            return floats
        case .simd64(let simd64s):
            var floats: [Float] = Array()
            floats.reserveCapacity(simd64s.count * 64)
            for simd in simd64s {
                for idx in simd.indices {
                    floats.append(simd[idx])
                }
            }
            return floats
        }
    }

    enum Storage: Hashable {
        case floats([Float])
        case simd64([SIMD64<Float>])
    }

    public init(vectors: [Float], provider: String, halfPrecision: Bool = false, forceFloatStorage: Bool = false /* for testing */) {
        if vectors.count % 64 == 0 && !forceFloatStorage {
            var simdVectors: [SIMD64<Float>] = []
            for i in stride(from: 0, to: vectors.count, by: 64) {
                simdVectors.append(SIMD64<Float>(vectors[i..<i+64]))
            }
            storage = .simd64(simdVectors)
            self.magnitude = computeMagnitude(vector: simdVectors)
        } else {
            storage = .floats(vectors)
            self.magnitude = computeMagnitude(vector: vectors)
        }
        self.provider = provider
        self.halfPrecision = halfPrecision
    }
}

extension Embedding {
    public func cosineSimilarity(with other: Embedding) -> Float {
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

        if case .simd64(let vecs1) = storage, case .simd64(let vecs2) = other.storage {
            return dotProduct(a: vecs1, b: vecs2) / denom
        }

        return dotProduct(a: vectors, b: other.vectors) / denom
    }
}

// MARK: - Math

private func computeMagnitude(vector: [Float]) -> Float {
    var x: Float = 0
    for el in vector {
        x += el * el
    }
    return sqrt(x)
}

private func computeMagnitude(vector: [SIMD64<Float>]) -> Float {
    var x: Float = 0
    for el in vector {
        x += (el * el).sum()
    }
    return sqrt(x)
}

private func dotProduct(a: [Float], b: [Float]) -> Float {
    var x: Float = 0
    for (a_, b_) in zip(a, b) {
        x += a_ * b_
    }
    return x
}

private func dotProduct(a: [SIMD64<Float>], b: [SIMD64<Float>]) -> Float {
    var x: Float = 0
    for (a_, b_) in zip(a, b) {
        x += (a_ * b_).sum()
    }
    return x
}

// MARK: - Encoding

private enum FloatArrayToBase64 {
    // Convert to little endian
    static func encode(_ floats: [Float]) -> String {
        var bytes: [UInt8] = []
        for float in floats {
            var leFloat = float.bitPattern.littleEndian
            withUnsafeBytes(of: &leFloat) { bytes.append(contentsOf: $0) }
        }
        let data = Data(bytes)
        let base64String = data.base64EncodedString()
        return base64String
    }

    static func decode(fromBase64String string: String) -> [Float]? {
        guard let data = Data(base64Encoded: string) else {
            return nil
        }
        var decodedFloats: [Float] = []
        let count = data.count / MemoryLayout<UInt32>.size

        data.withUnsafeBytes { ptr in
            for i in 0..<count {
                let start = i * MemoryLayout<UInt32>.size
                let leBits = UInt32(littleEndian: ptr.load(fromByteOffset: start, as: UInt32.self))
                decodedFloats.append(Float(bitPattern: leBits))
            }
        }
        return decodedFloats
    }
}

private enum Float16ArrayToBase64 {
    // Convert to little endian
    static func encode(_ floats: [Float]) -> String {
        var bytes: [UInt8] = []
        for float in floats {
            var leFloat: UInt16 = Float16(float).bitPattern.littleEndian
            withUnsafeBytes(of: &leFloat) { bytes.append(contentsOf: $0) }
        }
        let data = Data(bytes)
        let base64String = data.base64EncodedString()
        return base64String
    }

    static func decode(fromBase64String string: String) -> [Float]? {
        guard let data = Data(base64Encoded: string) else {
            return nil
        }
        var decodedFloats: [Float] = []
        let count = data.count / MemoryLayout<UInt16>.size

        data.withUnsafeBytes { ptr in
            for i in 0..<count {
                let start = i * MemoryLayout<UInt16>.size
                let leBits = UInt16(littleEndian: ptr.load(fromByteOffset: start, as: UInt16.self))
                decodedFloats.append(Float(Float16(bitPattern: leBits)))
            }
        }
        return decodedFloats
    }
}

// Implement custom encode/decode for Embedding
extension Embedding {
    enum CodingKeys: String, CodingKey {
        case vectors
        case vectorsHalfPrecision // float16
        case provider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(String.self, forKey: .provider)

        if container.contains(.vectorsHalfPrecision) {
            let vectorsBase64 = try container.decode(String.self, forKey: .vectorsHalfPrecision)
            guard let vectors = Float16ArrayToBase64.decode(fromBase64String: vectorsBase64) else {
                throw DecodingError.dataCorruptedError(forKey: .vectors, in: container, debugDescription: "Could not decode vectors")
            }
            self.init(vectors: vectors, provider: provider, halfPrecision: true)
        } else {
            let vectorsBase64 = try container.decode(String.self, forKey: .vectors)
            guard let vectors = FloatArrayToBase64.decode(fromBase64String: vectorsBase64) else {
                throw DecodingError.dataCorruptedError(forKey: .vectors, in: container, debugDescription: "Could not decode vectors")
            }
            self.init(vectors: vectors, provider: provider, halfPrecision: false)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if halfPrecision {
            let vectorsBase64 = Float16ArrayToBase64.encode(vectors)
            try container.encode(vectorsBase64, forKey: .vectorsHalfPrecision)
        } else {
            let vectorsBase64 = FloatArrayToBase64.encode(vectors)
            try container.encode(vectorsBase64, forKey: .vectors)
        }
        try container.encode(provider, forKey: .provider)
    }
}
