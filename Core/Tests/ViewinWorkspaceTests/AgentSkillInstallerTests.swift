import Foundation
import XCTest
@testable import ViewinWorkspace

final class AgentSkillInstallerTests: XCTestCase {
  private var temporary: URL!
  override func setUpWithError() throws {
    temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Viewin Skill \(UUID())")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }

  private func executable(named name: String = "Viewin's $(not-a-command) app") throws -> URL {
    let url = temporary.appendingPathComponent(name)
    try Data("#!/bin/sh\nprintf '%s\\n' \"$@\"\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
  }

  func testInstallationAndLauncherPreserveQuotedPathsAndArguments() throws {
    let installer = AgentSkillInstaller(executable: try executable())
    let root = temporary.appendingPathComponent("skills with spaces")
    XCTAssertEqual(installer.status(in: root), .notInstalled)
    let folder = try installer.install(in: root)
    XCTAssertEqual(installer.status(in: root), .installed)
    XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("references/snapshot.md").path))
    let process = Process(); let output = Pipe()
    process.executableURL = installer.launcher(in: root)
    process.arguments = ["--output", "path with ' quotes $() and spaces", "--list"]
    process.standardOutput = output
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertEqual(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
                   "--output\npath with ' quotes $() and spaces\n--list\n")
  }

  func testUpdateRepairsManagedFilesAndRelocatedAppWithoutDeletingExtraFiles() throws {
    let root = temporary.appendingPathComponent("skills")
    let old = AgentSkillInstaller(executable: try executable(named: "old"))
    let folder = try old.install(in: root)
    let extra = folder.appendingPathComponent("notes.txt")
    try Data("keep".utf8).write(to: extra)
    try Data("changed".utf8).write(to: folder.appendingPathComponent("SKILL.md"))
    XCTAssertEqual(old.status(in: root), .needsUpdate)
    let new = AgentSkillInstaller(executable: try executable(named: "new"))
    XCTAssertEqual(new.status(in: root), .needsUpdate)
    try new.install(in: root)
    XCTAssertEqual(new.status(in: root), .installed)
    XCTAssertEqual(try String(contentsOf: extra, encoding: .utf8), "keep")
  }

  func testUnmanagedSkillIsNotOverwritten() throws {
    let installer = AgentSkillInstaller(executable: try executable())
    let root = temporary.appendingPathComponent("skills")
    let folder = root.appendingPathComponent("viewin")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("SKILL.md")
    try Data("user skill".utf8).write(to: file)
    XCTAssertEqual(installer.status(in: root), .conflict)
    XCTAssertThrowsError(try installer.install(in: root))
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "user skill")
  }

  func testManagedSubdirectorySymlinkCannotRedirectWrites() throws {
    let installer = AgentSkillInstaller(executable: try executable())
    let root = temporary.appendingPathComponent("skills")
    let folder = try installer.install(in: root)
    let outside = temporary.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let scripts = folder.appendingPathComponent("scripts")
    try FileManager.default.removeItem(at: scripts)
    try FileManager.default.createSymbolicLink(at: scripts, withDestinationURL: outside)
    XCTAssertThrowsError(try installer.install(in: root))
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
  }

  func testUpdateRepairsLauncherPermissions() throws {
    let installer = AgentSkillInstaller(executable: try executable())
    let root = temporary.appendingPathComponent("skills")
    try installer.install(in: root)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: installer.launcher(in: root).path)
    XCTAssertEqual(installer.status(in: root), .needsUpdate)
    try installer.install(in: root)
    XCTAssertEqual(installer.status(in: root), .installed)
  }

  func testMissingCLILeavesDestinationUntouched() throws {
    let installer = AgentSkillInstaller(executable: temporary.appendingPathComponent("missing"))
    let root = temporary.appendingPathComponent("skills")
    XCTAssertFalse(installer.cliAvailable)
    XCTAssertThrowsError(try installer.install(in: root))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }
}
