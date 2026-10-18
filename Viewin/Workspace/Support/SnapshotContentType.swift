import UniformTypeIdentifiers

extension UTType {
  static let legacyInViewSnapshot = UTType(
    importedAs: "app.inview.snapshot", conformingTo: .archive)
  static let legacyUIInspectorSnapshot = UTType(
    importedAs: "app.uiinspector.snapshot", conformingTo: .archive)
  static let viewinSnapshot = UTType(
    exportedAs: "app.viewin.snapshot", conformingTo: .archive)
}
