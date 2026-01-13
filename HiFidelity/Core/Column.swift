import Foundation

public struct Column: Hashable, Equatable, CustomStringConvertible {
    public let name: String

    // Primary initializer from raw column name
    public init(_ name: String) {
        self.name = name
    }

    // Convenience initializer from CodingKey (to mirror old GRDB convenience)
    public init(_ codingKey: some CodingKey) {
        self.name = codingKey.stringValue
    }

    public var description: String { name }
}
