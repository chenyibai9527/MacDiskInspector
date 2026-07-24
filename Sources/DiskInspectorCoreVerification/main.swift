import DiskInspectorCore
import Foundation

enum VerificationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): "Verification failed: \(message)"
        }
    }
}

@main
struct DiskInspectorCoreVerification {
    static func main() async throws {
        try verifyRulesAndAllowlist()
        try await verifyScannerBoundaries()
        try await verifyPermissionReporting()
        try await verifyCancellation()
        print("DiskInspectorCore verification passed.")
    }

    private static func verifyRulesAndAllowlist() throws {
        let engine = RuleEngine()
        let advisor = ActionAdvisor()

        let npm = engine.finding(for: measurement("/Users/test/.npm/_cacache"))
        try require(npm.category == .regenerableCache && npm.risk == .low, "npm classification")
        let commands = advisor.actions(for: npm).compactMap(\.value)
        try require(commands.contains("npm cache verify"), "npm inspection allowlist")
        try require(!commands.contains(where: { $0.contains("rm ") }), "generic rm command must not exist")

        let cursor = engine.finding(
            for: measurement("/Users/test/Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        )
        try require(cursor.risk == .high && cursor.potentialReclaimableBytes == nil, "Cursor state protection")
        try require(
            !advisor.actions(for: cursor).contains {
                $0.kind == .copyInspectionCommand || $0.kind == .copyOfficialCleanupCommand
            },
            "high-risk data must not receive commands"
        )

        let system = engine.finding(for: measurement("/private/var/vm"))
        try require(system.risk == .prohibited, "system-managed path protection")
    }

    private static func verifyScannerBoundaries() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("MacDiskInspectorVerification-\(UUID().uuidString)", isDirectory: true)
        let outside = manager.temporaryDirectory
            .appendingPathComponent("MacDiskInspectorOutside-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: root)
            try? manager.removeItem(at: outside)
        }

        let npm = root.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try manager.createDirectory(at: npm, withIntermediateDirectories: true)
        let original = npm.appendingPathComponent("payload")
        let hardLink = npm.appendingPathComponent("payload-link")
        try Data(repeating: 0x41, count: 8192).write(to: original)
        try manager.linkItem(at: original, to: hardLink)

        try Data(repeating: 0x42, count: 4096).write(to: outside.appendingPathComponent("must-not-scan"))
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("outside-link"),
            withDestinationURL: outside
        )

        let cursorDirectory = root
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage", isDirectory: true)
        try manager.createDirectory(at: cursorDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0x43, count: 1024).write(to: cursorDirectory.appendingPathComponent("state.vscdb"))

        let report = try await DirectoryScanner().scan(rootURL: root)
        try require(
            report.uniqueFiles == 2,
            "hard links should count once and symlink target never " +
            "(unique=\(report.uniqueFiles), hardLinks=\(report.duplicateHardLinksSkipped), " +
            "issues=\(report.issues.map(\.kind.rawValue)), " +
            "findings=\(report.findings.map { "\($0.ruleIdentifier):\($0.path)" }))"
        )
        try require(report.duplicateHardLinksSkipped == 1, "hard-link duplicate counter")
        try require(report.issues.contains { $0.kind == .symbolicLinkSkipped }, "symlink issue reporting")
        try require(report.findings.contains { $0.ruleIdentifier == "npm.cache" }, "deep npm rule mapping")
        try require(
            report.findings.contains {
                $0.ruleIdentifier == "cursor.state-database" && $0.path.hasSuffix("state.vscdb")
            },
            "deep exact-file Cursor rule mapping"
        )

        let symlinkRoot = root.appendingPathComponent("outside-link")
        do {
            _ = try await DirectoryScanner().scan(rootURL: symlinkRoot)
            throw VerificationFailure.failed("a symlink root must be rejected")
        } catch let error as CocoaError where error.code == .fileReadUnsupportedScheme {
            // Expected.
        }
    }

    private static func verifyPermissionReporting() async throws {
        guard geteuid() != 0 else { return }
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("MacDiskInspectorPermission-\(UUID().uuidString)", isDirectory: true)
        let blocked = root.appendingPathComponent("blocked", isDirectory: true)
        try manager.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: blocked.appendingPathComponent("private"))
        guard chmod(blocked.path, 0) == 0 else {
            throw VerificationFailure.failed("could not create permission fixture")
        }
        defer {
            _ = chmod(blocked.path, S_IRWXU)
            try? manager.removeItem(at: root)
        }

        let report = try await DirectoryScanner().scan(rootURL: root)
        try require(
            report.issues.contains {
                $0.kind == .permissionDenied && $0.path.contains("/blocked")
            },
            "permission error reporting"
        )
        try require(report.hasCoverageGaps, "permission errors must create a coverage gap")
    }

    private static func verifyCancellation() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("MacDiskInspectorCancellation-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        for index in 0..<200 {
            try Data([UInt8(index % 255)]).write(to: root.appendingPathComponent("file-\(index)"))
        }

        let task = Task {
            try await DirectoryScanner().scan(
                rootURL: root,
                configuration: ScanConfiguration(progressInterval: 1)
            ) { _ in
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            throw VerificationFailure.failed("cancelled scan returned a report")
        } catch is CancellationError {
            // Expected.
        }
    }

    private static func measurement(_ path: String) -> DirectoryMeasurement {
        DirectoryMeasurement(
            path: path,
            allocatedBytes: 1_000_000,
            logicalBytes: 900_000,
            fileCount: 1,
            lastModified: nil
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw VerificationFailure.failed(message) }
    }
}
