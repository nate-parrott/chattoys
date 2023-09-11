import Foundation

public struct Embedding: Hashable, Codable {
    public var vectors: [Float]
    public var provider: String // Embeddings are not comparable across different models or providers
    public var magnitude: Float

    public init(vectors: [Float], provider: String) {
        self.vectors = vectors
        self.provider = provider
        self.magnitude = computeMagnitude(vector: vectors)
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

private func dotProduct(a: [Float], b: [Float]) -> Float {
    var x: Float = 0
    for (a_, b_) in zip(a, b) {
        x += a_ * b_
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

// Implement custom encode/decode for Embedding
extension Embedding {
    enum CodingKeys: String, CodingKey {
        case vectors
        case provider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let vectorsBase64 = try container.decode(String.self, forKey: .vectors)
        guard let vectors = FloatArrayToBase64.decode(fromBase64String: vectorsBase64) else {
            throw DecodingError.dataCorruptedError(forKey: .vectors, in: container, debugDescription: "Could not decode vectors")
        }
        let provider = try container.decode(String.self, forKey: .provider)
        self.init(vectors: vectors, provider: provider)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let vectorsBase64 = FloatArrayToBase64.encode(vectors)
        try container.encode(vectorsBase64, forKey: .vectors)
        try container.encode(provider, forKey: .provider)
    }
}
