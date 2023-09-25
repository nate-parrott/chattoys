////
//// A Swift property wrapper for adding "indirect" to struct properties.
//// Enum supports this out of the box, but for some reason struct doesn't.
////
//// This is useful when you want to do something recursive with structs like:
////
//// struct Node {
////   var next: Node?
//// }
////
//// Normally you can't do this. You get an error like:
//// error: Value type 'Node' cannot have a stored property that recursively contains it
////
//// One valid workaround is to use a class - but what if you *really* don't want to?!
//// Enter the @Indirect property wrapper! Use it like so:
////
//// struct Node {
////   @Indirect var next: Node? // it works!
//// }
////
//// Tada!
////
//// This works by piggybacking on the indirect support that already exists for enums.
//// I discovered this here: https://forums.swift.org/t/using-indirect-modifier-for-struct-properties/37600/14
//// My contribution is making it work with Codable (even when T is optional).
////
//@propertyWrapper
//public enum Indirect<T: Equatable>: Equatable {
//  indirect case wrapped(T)
//
//  public init(wrappedValue initialValue: T) {
//    self = .wrapped(initialValue)
//  }
//
//  public var wrappedValue: T {
//    get { switch self { case .wrapped(let x): return x } }
//    set { self = .wrapped(newValue) }
//  }
//}
//
//extension Indirect: Decodable where T: Decodable {
//    public init(from decoder: Decoder) throws {
//        try self.init(wrappedValue: T(from: decoder))
//    }
//}
//
//extension Indirect: Encodable where T: Encodable {
//    public func encode(to encoder: Encoder) throws {
//        try wrappedValue.encode(to: encoder)
//    }
//}
//
//extension KeyedDecodingContainer {
//    func decode<T: Decodable>(_: Indirect<T>.Type, forKey key: Key) throws -> Indirect<T> {
//        return try Indirect(wrappedValue: decode(T.self, forKey: key))
//    }
//
//    func decode<T: Decodable>(_: Indirect<Optional<T>>.Type, forKey key: Key) throws -> Indirect<Optional<T>> {
//        return try Indirect(wrappedValue: decodeIfPresent(T.self, forKey: key))
//    }
//}
