import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

struct ToolbarControl: View {
  let workspace: WorkspaceStore
  let kind: String
  let openSnapshot: () -> Void
  let saveSnapshot: () -> Void
  private var popover: Bool {
    get { workspace.menuState.appPickerPresented }
    nonmutating set { workspace.menuState.appPickerPresented = newValue }
  }
  private var popoverBinding: Binding<Bool> {
    Binding(get: { popover }, set: { popover = $0 })
  }

  var body: some View {
    Group {
      switch kind {
      case "refresh":
        Button {
          workspace.refresh()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(
          workspace.isCapturing
            || (workspace.connectedTarget == nil)
        )
        .accessibilityLabel(L10n.text("刷新"))
      case "app":
        Button {
          popover.toggle()
        } label: {
          if let target = workspace.connectedTarget {
            HStack(spacing: 4) {
              TargetAppIcon(data: target.appIconPNG)
                .frame(width: 14, height: 14)
              Text(target.appName).lineLimit(1).layoutPriority(1)
              Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
              Image(systemName: "iphone.gen3").font(.system(size: 13))
              Text(
                target.osVersion.isEmpty
                  ? target.deviceName : "\(target.deviceName) (\(target.osVersion))"
              )
              .lineLimit(1).truncationMode(.middle)
            }.font(.system(size: 12)).padding(.horizontal, 5)
          } else {
            Image(systemName: "app")
          }
        }.accessibilityLabel(L10n.text("App 切换"))
          .help(workspace.connectedTarget.map { "\($0.appName) · \($0.deviceName)" } ?? L10n.text("切换 App"))
          .disabled(workspace.isCapturing)
          .popover(isPresented: popoverBinding) {
            AppSelectionView(workspace: workspace) { target in
              popover = false
              workspace.capture(target)
            }
          }
      case "mode":
        Picker(L10n.text("预览模式"), selection: workspace.binding(\.viewMode)) {
          Image(systemName: "square").tag("2D").accessibilityLabel("2D")
          Image(systemName: "cube").tag("3D").accessibilityLabel("3D")
        }.labelsHidden().pickerStyle(.segmented)
      case "rotation":
        Toggle(isOn: workspace.binding(\.freeRotation)) { Image(systemName: "rotate.3d") }
          .toggleStyle(.button).accessibilityLabel(L10n.text("自由旋转"))
      case "settings":
        Button {
          WorkspaceSettingsWindow.shared.show(workspace: workspace)
        } label: {
          Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel(L10n.text("设置"))
      case "scale":
        HStack(spacing: 5) {
          Button {
            workspace.zoom = max(0, workspace.zoom - 0.1)
          } label: {
            Image(systemName: "minus")
          }.accessibilityLabel(L10n.text("缩小"))
          Slider(value: workspace.binding(\.zoom), in: 0...1).accessibilityLabel(L10n.text("预览大小"))
          Button {
            workspace.zoom = min(1, workspace.zoom + 0.1)
          } label: {
            Image(systemName: "plus")
          }.accessibilityLabel(L10n.text("放大"))
        }.buttonStyle(.borderless).padding(.horizontal, 10)
      case "measure":
        Toggle(
          isOn: Binding(get: { workspace.isMeasuring }, set: { _ in workspace.toggleMeasurement() })
        ) {
          Image(systemName: "ruler")
        }.toggleStyle(.button).accessibilityLabel(L10n.text("测距"))
      default:
        Menu {
          Button(L10n.text("打开快照…"), action: openSnapshot)
          Button(L10n.text("保存快照…"), action: saveSnapshot).disabled(workspace.document == nil)
        } label: {
          Image(systemName: "folder")
        }.accessibilityLabel(L10n.text("打开快照"))
      }
    }
    .controlSize(.regular)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
