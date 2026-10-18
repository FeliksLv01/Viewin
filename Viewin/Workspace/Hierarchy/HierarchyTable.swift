import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace
import UniformTypeIdentifiers

struct HierarchyTable: NSViewRepresentable {
  let contentID: ObjectIdentifier?
  let workspace: WorkspaceStore
  let document: SnapshotDocument
  let expanded: Set<String>
  let search: String
  let selectedId: String?
  let hoveredId: String?
  let focusRootId: String?
  let includedIds: Set<String>?
  let hiddenPreviewIds: Set<String>

  func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }
  func makeNSView(context: Context) -> NSScrollView {
    let table = OutlineTable()
    let column = NSTableColumn(identifier: .init("hierarchy"))
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 28
    table.intercellSpacing = .zero
    table.backgroundColor = .clear
    table.style = .plain
    table.usesAutomaticRowHeights = false
    table.allowsEmptySelection = true
    table.columnAutoresizingStyle = .noColumnAutoresizing
    column.resizingMask = []
    column.maxWidth = .greatestFiniteMagnitude
    table.delegate = context.coordinator
    table.dataSource = context.coordinator
    table.doubleAction = #selector(Coordinator.doubleClick(_:))
    table.target = context.coordinator
    table.hoverAction = { [weak coordinator = context.coordinator] row in
      guard let coordinator else { return }
      coordinator.workspace.hover(
        coordinator.rows.indices.contains(row) ? coordinator.rows[row].node.id : nil)
    }
    table.contextMenu = { [weak coordinator = context.coordinator] row in
      coordinator?.makeMenu(row: row)
    }
    table.keyboardAction = { [weak coordinator = context.coordinator] right, recursive in
      coordinator?.keyboard(right: right, recursive: recursive)
    }
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.drawsBackground = false
    scroll.autohidesScrollers = true
    context.coordinator.table = table
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.update(self)
  }

  @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Row {
      let node: SnapshotNode
      let depth: Int
      let detail: String
      let events: [EventHandlerPresentation]
      let tooltip: String
      let hidden: Bool
    }
    let workspace: WorkspaceStore
    weak var table: OutlineTable?
    var contentID: ObjectIdentifier?
    var snapshotId = ""
    var expanded = Set<String>()
    var search = ""
    var focusRootId: String?
    var includedIds: Set<String>?
    var hiddenPreviewIds = Set<String>()
    var hoveredId: String?
    var contentWidth: CGFloat = 0
    var allRows: [Row] = []
    var rows: [Row] = []
    var indices: [String: Int] = [:]
    var applying = false
    let eventsPopover = HierarchyEventsPopover()

    init(workspace: WorkspaceStore) { self.workspace = workspace }

    func update(_ input: HierarchyTable) {
      guard let table else { return }
      let replaced =
        contentID != input.contentID || snapshotId != input.document.snapshot.snapshotId
      let rebuild =
        replaced || expanded != input.expanded || search != input.search
        || focusRootId != input.focusRootId || includedIds != input.includedIds
      let restyle = hiddenPreviewIds != input.hiddenPreviewIds
      if rebuild { eventsPopover.close() }
      if replaced {
        contentID = input.contentID
        snapshotId = input.document.snapshot.snapshotId
        allRows = (workspace.hierarchy?.entries ?? []).map { entry in
          let node = entry.node
          let details = [node.sidebarDetail, node.listPositionSummary].compactMap { $0 }.joined(
            separator: " ")
          return Row(
            node: node, depth: entry.depth, detail: details,
            events: node.eventHandlers,
            tooltip: ([node.typeName] + node.memberReferenceNames).joined(separator: "\n"),
            hidden: entry.hidden)
        }
      }
      applying = true
      if rebuild {
        let oldVisible = table.rows(in: table.visibleRect)
        let topId = oldVisible.location < rows.count ? rows[oldVisible.location].node.id : nil
        let offset = table.visibleRect.minY - CGFloat(oldVisible.location) * table.rowHeight
        expanded = input.expanded
        search = input.search
        focusRootId = input.focusRootId
        includedIds = input.includedIds
        let baseDepth =
          focusRootId.flatMap { workspace.hierarchy?.positions[$0] }.map {
            workspace.hierarchy!.entries[$0].depth
          } ?? 0
        rows = workspace.visibleHierarchyIndices.map {
          allRows[$0]
        }
        table.baseDepth = baseDepth
        contentWidth =
          rows.map { row in
            let titleWidth = (row.node.sidebarTitle as NSString).size(withAttributes: [
              .font: NSFont.systemFont(ofSize: 12)
            ]).width
            let detailWidth = (row.detail as NSString).size(withAttributes: [
              .font: NSFont.systemFont(ofSize: 11)
            ]).width
            return CGFloat(max(0, row.depth - baseDepth)) * 13 + 76 + titleWidth + detailWidth
          }.max() ?? 0
        table.minimumContentWidth = ceil(contentWidth)
        indices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.node.id, $0) })
        table.reloadData()
        if !replaced, let topId, let row = indices[topId],
          let clip = table.enclosingScrollView?.contentView
        {
          clip.scroll(
            to: clip.constrainBoundsRect(
              NSRect(
                origin: CGPoint(x: clip.bounds.minX, y: CGFloat(row) * table.rowHeight + offset),
                size: clip.bounds.size)
            ).origin)
          table.enclosingScrollView?.reflectScrolledClipView(clip)
        }
      }
      if let selectedId = input.selectedId, let row = indices[selectedId], table.selectedRow != row
      {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        if !rebuild { table.scrollRowToVisible(row) }
      } else if input.selectedId == nil || indices[input.selectedId ?? ""] == nil {
        table.deselectAll(nil)
      }
      hiddenPreviewIds = input.hiddenPreviewIds
      if restyle && !rebuild {
        table.reloadData(
          forRowIndexes: IndexSet(integersIn: Range(table.rows(in: table.visibleRect)) ?? 0..<0),
          columnIndexes: IndexSet(integer: 0))
      }
      let oldHover = hoveredId
      hoveredId = input.hoveredId
      if oldHover != hoveredId || rebuild {
        for id in [oldHover, hoveredId].compactMap({ $0 }) {
          guard let row = indices[id],
            let view = table.rowView(atRow: row, makeIfNecessary: false) as? HoverRow
          else { continue }
          view.hovered = id == hoveredId
        }
        updateGuides()
      }
      applying = false
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    var tableViewBaseDepth: Int { table?.baseDepth ?? 0 }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
      let view = HoverRow()
      view.hovered = rows[row].node.id == hoveredId
      return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      let id = NSUserInterfaceItemIdentifier("HierarchyCell")
      let cell =
        tableView.makeView(withIdentifier: id, owner: nil) as? HierarchyCell ?? HierarchyCell()
      cell.identifier = id
      let value = rows[row]
      cell.configure(value, expanded: expanded.contains(value.node.id))
      cell.depth = max(0, value.depth - tableViewBaseDepth)
      cell.setPreviewHidden(workspace.isPreviewHidden(value.node.id))
      cell.highlightSearch(workspace.searchQuery)
      cell.disclose = { [weak self] in self?.workspace.toggleExpansion(value.node.id) }
      cell.showEvents = { [weak self, weak cell] in
        guard let self, let cell else { return }
        self.eventsPopover.show(events: value.events, from: cell)
      }
      return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
      guard !applying, let table else { return }
      workspace.selectedId =
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].node.id : nil
    }
    @objc func doubleClick(_ sender: NSTableView) {
      guard rows.indices.contains(sender.clickedRow) else { return }
      workspace.doubleClick(rows[sender.clickedRow].node.id)
    }
    func updateGuides() {
      guard let table, let hoveredId, let row = indices[hoveredId],
        let parent = rows[row].node.parentId, let parentRow = indices[parent]
      else {
        table?.guide.path = nil
        return
      }
      let siblings = rows.indices.filter { rows[$0].node.parentId == parent }
      guard let last = siblings.last else { return }
      let x = CGFloat(max(0, rows[row].depth - table.baseDepth)) * 13 + 23
      let path = CGMutablePath()
      path.move(to: CGPoint(x: x, y: table.rect(ofRow: parentRow).midY))
      path.addLine(to: CGPoint(x: x, y: table.rect(ofRow: last).midY))
      for index in siblings {
        let y = table.rect(ofRow: index).midY
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + 10, y: y))
      }
      table.guide.path = path
    }

    func makeMenu(row: Int) -> NSMenu? {
      guard let table, rows.indices.contains(row) else { return nil }
      let node = rows[row].node
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      let menu = NSMenu()
      menu.autoenablesItems = false
      func add(
        _ title: String, enabled: Bool = true, reason: String? = nil, _ action: @escaping () -> Void
      ) {
        let command = MenuCommand(action)
        let item = NSMenuItem(
          title: title, action: #selector(MenuCommand.invokeAction), keyEquivalent: "")
        item.target = command
        item.representedObject = command
        item.isEnabled = enabled
        item.toolTip = reason
        menu.addItem(item)
      }
      add(L10n.text("聚焦")) { [weak workspace] in workspace?.focus(node.id) }
      if workspace.connectedTarget != nil {
        add(L10n.text("打印对象"), enabled: false, reason: L10n.text("远程对象控制台尚未接入")) {}
        menu.addItem(.separator())
        add(L10n.text("刷新图层"), enabled: false, reason: L10n.text("当前连接只支持完整快照采集，局部刷新尚未接入")) {}
        add(L10n.text("刷新图层及其子层级"), enabled: false, reason: L10n.text("局部刷新尚未接入")) {}
      }
      let texts = copyTexts(node)
      if !texts.isEmpty { menu.addItem(.separator()) }
      for text in texts {
        add(L10n.format("复制文本“%@”", String(describing: text))) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        }
      }
      if !node.childIds.isEmpty {
        menu.addItem(.separator())
        add(L10n.text("递归展开")) { [weak workspace] in workspace?.expandSubtree(node.id) }
        add(L10n.text("收起子层级")) { [weak workspace] in workspace?.collapseSubtree(node.id) }
      }
      if node.geometry != nil {
        menu.addItem(.separator())
        let hidden = workspace.isPreviewHidden(node.id)
        add(hidden ? L10n.text("显示截图") : L10n.text("本次隐藏截图")) { [weak workspace] in workspace?.togglePreview(node.id) }
      }
      if let image = (node.groupImageId ?? node.imageId).flatMap({ workspace.nodeImages[$0] }) {
        menu.addItem(.separator())
        add(L10n.text("导出截图…")) { [weak self] in self?.export(image, node: node) }
      }
      return menu
    }

    func copyTexts(_ node: SnapshotNode) -> [String] {
      var texts: [String] = []
      if !((node.name.hasPrefix("UI") || node.name.hasPrefix("CA")) && node.name.count < 10) {
        texts.append(node.name)
      }
      if let detail = node.sidebarDetail, detail.hasSuffix(".view") {
        texts.append(String(detail.dropLast(5)))
      }
      if case .array(let references) = node.availableProperty("memberReferences") {
        for reference in references {
          if case .object(let fields) = reference, case .string(let name) = fields["name"] {
            texts.append(name.hasPrefix("_") ? String(name.dropFirst()) : name)
          }
        }
      }
      var seen = Set<String>()
      return texts.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func export(_ image: NSImage, node: SnapshotNode) {
      guard let window = table?.window else { return }
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.png]
      panel.nameFieldStringValue =
        "\(node.name.replacingOccurrences(of: "/", with: "-"))-\(node.id).png"
      panel.beginSheetModal(for: window) { [weak workspace] response in
        guard response == .OK, let url = panel.url else { return }
        do {
          guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
          else {
            throw SnapshotIssue(message: L10n.text("无法编码 PNG 截图。"))
          }
          try png.write(to: url, options: .atomic)
        } catch { workspace?.errorMessage = error.localizedDescription }
      }
    }
    func keyboard(right: Bool, recursive: Bool) {
      guard let table, rows.indices.contains(table.selectedRow) else { return }
      let node = rows[table.selectedRow].node
      if right {
        if recursive {
          workspace.expandSubtree(node.id)
        } else if !expanded.contains(node.id) && !node.childIds.isEmpty {
          workspace.toggleExpansion(node.id)
        } else if let next = rows.dropFirst(table.selectedRow + 1).first(where: { !$0.hidden }) {
          workspace.selectedId = next.node.id
        }
      } else if recursive {
        workspace.collapseSubtree(node.id)
      } else if expanded.contains(node.id) {
        workspace.toggleExpansion(node.id)
      } else if let parent = node.parentId {
        if expanded.contains(parent) { workspace.toggleExpansion(parent) }
        workspace.selectedId = parent
      }
    }
  }
}
