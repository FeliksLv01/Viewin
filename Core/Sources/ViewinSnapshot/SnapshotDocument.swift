import Foundation
import ViewinProtocol

public struct SnapshotIssue: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct SnapshotDocument: Sendable {
    public let snapshot: Snapshot
    private let nodesById: [String: SnapshotNode]

    public init(data: Data) throws {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.protocolVersion.major == ProtocolVersion.current.major,
              snapshot.protocolVersion.minor >= 1 else {
            throw SnapshotIssue(message: "不支持的快照协议版本。")
        }
        guard !snapshot.snapshotId.isEmpty, !snapshot.sessionId.isEmpty,
              Self.parseTimestamp(snapshot.capturedAt) != nil else {
            throw SnapshotIssue(message: "快照身份或时间无效。")
        }
        guard snapshot.nodes.count <= 10_000 else {
            throw SnapshotIssue(message: "快照超过 10,000 个节点的读取上限。")
        }
        let ids = snapshot.nodes.map(\.id)
        guard Set(ids).count == ids.count, !ids.contains("") else {
            throw SnapshotIssue(message: "节点 ID 为空或重复。")
        }
        let nodes = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
        let windowIds = snapshot.windows.map(\.id)
        guard Set(windowIds).count == windowIds.count else {
            throw SnapshotIssue(message: "窗口 ID 重复。")
        }
        let windows = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, $0) })
        for window in snapshot.windows {
            guard !window.id.isEmpty, window.size.width.isFinite, window.size.height.isFinite,
                  window.size.width > 0, window.size.height > 0,
                  window.pixelsPerUnit.isFinite, window.pixelsPerUnit > 0,
                  Set(window.rootNodeIds).count == window.rootNodeIds.count else {
                throw SnapshotIssue(message: "窗口几何或根节点无效：\(window.id)")
            }
            for root in window.rootNodeIds {
                guard let node = nodes[root], node.windowId == window.id, node.parentId == nil else {
                    throw SnapshotIssue(message: "窗口引用了无效根节点：\(root)")
                }
            }
        }
        for node in snapshot.nodes {
            guard let window = windows[node.windowId], Set(node.childIds).count == node.childIds.count else {
                throw SnapshotIssue(message: "节点窗口不存在或子节点重复：\(node.id)")
            }
            if let parentId = node.parentId {
                guard let parent = nodes[parentId], parent.windowId == node.windowId,
                      parent.childIds.contains(node.id) else {
                    throw SnapshotIssue(message: "父子引用不一致：\(node.id)")
                }
            } else if !window.rootNodeIds.contains(node.id) {
                throw SnapshotIssue(message: "根节点未登记到窗口：\(node.id)")
            }
            for childId in node.childIds {
                guard let child = nodes[childId], child.parentId == node.id,
                      child.windowId == node.windowId else {
                    throw SnapshotIssue(message: "子节点引用不一致：\(childId)")
                }
            }
            guard node.visibility.alpha.isFinite, (0...1).contains(node.visibility.alpha) else {
                throw SnapshotIssue(message: "透明度无效：\(node.id)")
            }
            if let geometry = node.geometry {
                let rects = [geometry.localBounds, geometry.frameInWindow]
                guard rects.allSatisfy({ rect in
                    [rect.x, rect.y, rect.width, rect.height].allSatisfy(\.isFinite)
                        && rect.width >= 0 && rect.height >= 0
                }), geometry.cornersInWindow.count == 4,
                geometry.cornersInWindow.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                geometry.clipInWindow.map({ $0.count >= 3 && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } }) ?? true else {
                    throw SnapshotIssue(message: "节点几何无效：\(node.id)")
                }
            }
        }
        // Iterative reachability also rejects disconnected cycles without recursive stack growth.
        var pending = snapshot.windows.flatMap(\.rootNodeIds).map { ($0, 0) }
        var visited = Set<String>()
        while let (id, depth) = pending.popLast() {
            guard depth <= 128 else {
                throw SnapshotIssue(message: "层级超过 128 层的读取上限。")
            }
            guard visited.insert(id).inserted else {
                throw SnapshotIssue(message: "层级中存在环或重复父节点：\(id)")
            }
            pending.append(contentsOf: (nodes[id]?.childIds ?? []).map { ($0, depth + 1) })
        }
        guard visited.count == nodes.count else {
            throw SnapshotIssue(message: "存在无法从窗口访问的节点或循环引用。")
        }
        for relation in snapshot.relations {
            guard nodes[relation.fromNodeId] != nil, nodes[relation.toNodeId] != nil else {
                throw SnapshotIssue(message: "跨树关系引用了不存在的节点。")
            }
        }
        let imageIds = snapshot.images.map(\.id)
        guard Set(imageIds).count == imageIds.count else {
            throw SnapshotIssue(message: "图片 ID 重复。")
        }
        for image in snapshot.images {
            let components = image.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !image.path.isEmpty, !image.path.hasPrefix("/"), !image.path.contains("\\"),
                  !components.contains(".."), !components.contains("."), !components.contains(""),
                  !image.path.contains(":"), image.pixelWidth > 0, image.pixelHeight > 0 else {
                throw SnapshotIssue(message: "图片路径或尺寸无效：\(image.id)")
            }
        }
        for window in snapshot.windows where window.screenshotId != nil {
            guard imageIds.contains(window.screenshotId!) else {
                throw SnapshotIssue(message: "窗口截图引用不存在：\(window.id)")
            }
        }
        let imageIdSet = Set(imageIds)
        for node in snapshot.nodes {
            guard [node.imageId, node.groupImageId].compactMap({ $0 }).allSatisfy(imageIdSet.contains) else {
                throw SnapshotIssue(message: "节点截图引用不存在：\(node.id)")
            }
        }
        self.snapshot = snapshot
        nodesById = nodes
    }

    public func node(_ id: String) -> SnapshotNode? { nodesById[id] }

    private static func parseTimestamp(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    public func children(of node: SnapshotNode) -> [SnapshotNode] {
        node.childIds.compactMap { nodesById[$0] }
    }

    public func roots(in windowId: String) -> [SnapshotNode] {
        snapshot.windows.first { $0.id == windowId }?.rootNodeIds.compactMap { nodesById[$0] } ?? []
    }

    /// Ancestors in root-to-parent order, for breadcrumbs and inherited visibility.
    public func ancestors(of node: SnapshotNode) -> [SnapshotNode] {
        var result: [SnapshotNode] = []
        var parentId = node.parentId
        while let id = parentId, let parent = nodesById[id] {
            result.append(parent)
            parentId = parent.parentId
        }
        return result.reversed()
    }

    public func find(_ text: String, in windowId: String) -> [SnapshotNode] {
        snapshot.nodes.filter { node in
            node.windowId == windowId && (text.isEmpty ||
                node.inspectionSearchText
                    .contains { $0.localizedCaseInsensitiveContains(text) })
        }
    }

    /// Geometric candidates only; paint order and arbitrary masks are not yet captured.
    public func hitTest(x: Double, y: Double, in windowId: String) -> [SnapshotNode] {
        snapshot.nodes.filter { node in
            guard node.windowId == windowId, let geometry = node.geometry,
                  geometry.frameInWindow.width > 0, geometry.frameInWindow.height > 0 else { return false }
            let chain = ancestors(of: node) + [node]
            guard chain.allSatisfy({ !$0.visibility.hidden && $0.visibility.alpha > 0 }) else { return false }
            guard Self.contains(x: x, y: y, polygon: geometry.cornersInWindow) else { return false }
            return chain.allSatisfy { ancestor in
                ancestor.geometry?.clipInWindow.map { Self.contains(x: x, y: y, polygon: $0) } ?? true
            }
        }.sorted { lhs, rhs in
            let leftDepth = ancestors(of: lhs).count
            let rightDepth = ancestors(of: rhs).count
            return leftDepth == rightDepth ? lhs.id < rhs.id : leftDepth > rightDepth
        }
    }

    private static func contains(x: Double, y: Double, polygon: [LayoutPoint]) -> Bool {
        var inside = false
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            let cross = (x - a.x) * (b.y - a.y) - (y - a.y) * (b.x - a.x)
            if abs(cross) < 0.000001,
               x >= min(a.x, b.x), x <= max(a.x, b.x),
               y >= min(a.y, b.y), y <= max(a.y, b.y) { return true }
            if (a.y > y) != (b.y > y), x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
        }
        return inside
    }
}
