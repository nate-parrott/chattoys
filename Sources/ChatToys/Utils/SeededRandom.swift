import GameplayKit

extension Array {
    public func shuffleDeterministically(seed: String) -> [Element] {
        var gen = SeededGenerator(string: seed)
        var out = self
        out.shuffle(using: &gen)
        return out
    }
}

public class SeededGenerator: RandomNumberGenerator {
    let seed: UInt64
    private let generator: GKMersenneTwisterRandomSource
    public convenience init() {
        self.init(seed: 0)
    }
    public convenience init(string: String) {
        self.init(seed: UInt64(bitPattern: Int64(string.djb2hash)))
    }
    public init(seed: UInt64) {
        self.seed = seed
        generator = GKMersenneTwisterRandomSource(seed: seed)
    }
    public func next() -> UInt64 {
        // From https://stackoverflow.com/questions/54821659/swift-4-2-seeding-a-random-number-generator
        // GKRandom produces values in [INT32_MIN, INT32_MAX] range; hence we need two numbers to produce 64-bit value.
        let next1 = UInt64(bitPattern: Int64(generator.nextInt()))
        let next2 = UInt64(bitPattern: Int64(generator.nextInt()))
        return next1 ^ (next2 << 32)
    }
}

public extension RandomNumberGenerator {
    mutating func nextRandFloat0_1() -> Double {
        let base: UInt64 = 32768
        let x = next() % base
        return Double(x) / Double(base)
    }

    mutating func nextRandFloat1_Neg1() -> Double {
        nextRandFloat0_1() * 2 - 1
    }

    mutating func shuffleSlightly<T>(array: [T], swapFraction: Double, maxSwapDist: Double) -> [T] {
        if swapFraction == 0 || array.count < 2 {
            return array
        }
        let maxSwapOffset = Int(Double(array.count) * maxSwapDist)
        let swapCount = Int(Double(array.count) * swapFraction)
        
        var x = array
        for _ in 0..<swapCount {
            let i = Int(nextRandFloat0_1() * Double(array.count))
            let minJ = max(0, i - maxSwapOffset)
            let maxJ = min(array.count - 1, i + maxSwapOffset)
            let j = Int(nextRandFloat0_1() * Double(maxJ - minJ)) + minJ
            x.swapAt(i, j)
        }
        return x
    }
}

extension String {
    // hash(0) = 5381
    // hash(i) = hash(i - 1) * 33 ^ str[i];
    var djb2hash: Int {
        let unicodeScalars = self.unicodeScalars.map { $0.value }
        return unicodeScalars.reduce(5381) {
            ($0 << 5) &+ $0 &+ Int($1)
        }
    }

    // hash(0) = 0
    // hash(i) = hash(i - 1) * 65599 + str[i];
    var sdbmhash: Int {
        let unicodeScalars = self.unicodeScalars.map { $0.value }
        return unicodeScalars.reduce(0) {
            Int($1) &+ ($0 << 6) &+ ($0 << 16) - $0
        }
    }
}
