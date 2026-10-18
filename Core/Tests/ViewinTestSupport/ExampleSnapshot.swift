import Foundation
import ViewinSnapshot

public enum ExampleSnapshot: String, CaseIterable, Sendable {
    case ios, android

    public var title: String { self == .ios ? "iOS · UIKit + SwiftUI" : "Android · View + Compose" }

    public func data() throws -> Data {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "json", subdirectory: "Fixtures") else {
            throw SnapshotIssue(message: "示例快照资源缺失。")
        }
        return try Data(contentsOf: url)
    }

    public func load() throws -> SnapshotDocument { try SnapshotDocument(data: data()) }
}
