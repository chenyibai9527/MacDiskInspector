import Darwin
import Foundation
import Testing
@testable import DiskInspectorCore

@Suite("Read-only directory scanner", .serialized)
struct DirectoryScannerTests {
    @Test("Uses allocated size and aggregates directories")
    func allocatedSizeAndAggregation() async throws {
        try await withFixture { root in
            let nested = root.appendingPathComponent(".npm/_cacache", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 8192).write(to: nested.appendingPathComponent("payload"))

            let report = try await DirectoryScanner().scan(rootURL: root)
            #expect(report.uniqueFiles == 1)
            #expect(report.totalAllocatedBytes > 0)
            #expect(report.totalLogicalBytes == 8192)
            #expect(report.findings.contains { $0.ruleIdentifier == "npm.cache" })
        }
    }

    @Test("Does not follow symbolic links")
    func symbolicLinks() async throws {
        try await withFixture { root in
            let outside = FileManager.default.temporaryDirectory
                .appendingPathComponent("MacDiskInspectorOutside-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: outside) }
            try Data(repeating: 1, count: 4096).write(to: outside.appendingPathComponent("secret"))
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("external-link"),
                withDestinationURL: outside
            )

            let report = try await DirectoryScanner().scan(rootURL: root)
            #expect(report.uniqueFiles == 0)
            #expect(report.issues.contains { $0.kind == .symbolicLinkSkipped })
        }
    }

    @Test("Deduplicates hard links")
    func hardLinks() async throws {
        try await withFixture { root in
            let original = root.appendingPathComponent("original.bin")
            let linked = root.appendingPathComponent("linked.bin")
            try Data(repeating: 7, count: 4096).write(to: original)
            try FileManager.default.linkItem(at: original, to: linked)

            let report = try await DirectoryScanner().scan(rootURL: root)
            #expect(report.uniqueFiles == 1)
            #expect(report.duplicateHardLinksSkipped == 1)
            #expect(report.totalLogicalBytes == 4096)
        }
    }

    @Test("Records permission errors when the platform enforces permissions")
    func permissionErrors() async throws {
        try await withFixture { root in
            let blocked = root.appendingPathComponent("blocked", isDirectory: true)
            try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: blocked.appendingPathComponent("file"))
            #expect(chmod(blocked.path, 0) == 0)
            defer { _ = chmod(blocked.path, S_IRWXU) }

            let report = try await DirectoryScanner().scan(rootURL: root)
            if geteuid() != 0 {
                #expect(report.issues.contains {
                    $0.kind == .permissionDenied && $0.path.contains("blocked")
                })
                #expect(report.hasCoverageGaps)
            }
        }
    }

    @Test("Cancellation propagates")
    func cancellation() async throws {
        try await withFixture { root in
            for index in 0..<200 {
                try Data([UInt8(index % 255)]).write(
                    to: root.appendingPathComponent("file-\(index)")
                )
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
            await #expect(throws: CancellationError.self) {
                _ = try await task.value
            }
        }
    }

    @Test("Keeps sparse logical size separate from allocated size")
    func sparseFiles() async throws {
        try await withFixture { root in
            let sparse = root.appendingPathComponent("sparse.bin")
            #expect(FileManager.default.createFile(atPath: sparse.path, contents: nil))
            let handle = try FileHandle(forWritingTo: sparse)
            try handle.truncate(atOffset: 1_073_741_824)
            try handle.close()

            var metadata = stat()
            #expect(lstat(sparse.path, &metadata) == 0)
            let expectedAllocated = Int64(metadata.st_blocks) * 512
            let report = try await DirectoryScanner().scan(rootURL: root)
            #expect(report.totalLogicalBytes == 1_073_741_824)
            #expect(report.totalAllocatedBytes == expectedAllocated)
            #expect(report.totalAllocatedBytes < report.totalLogicalBytes)
        }
    }

    @Test("Deep cache trees keep aggregation bounded")
    func largeDeepTree() async throws {
        try await withFixture { root in
            let base = root.appendingPathComponent(
                "Library/Caches/com.example.large/deep",
                isDirectory: true
            )
            for directoryIndex in 0..<40 {
                let directory = base.appendingPathComponent("batch-\(directoryIndex)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for fileIndex in 0..<25 {
                    try Data([UInt8(fileIndex)]).write(
                        to: directory.appendingPathComponent("file-\(fileIndex)")
                    )
                }
            }

            let report = try await DirectoryScanner().scan(rootURL: root)
            #expect(report.uniqueFiles == 1_000)
            #expect(report.findings.count <= 5)
            #expect(report.findings.contains { $0.path.hasSuffix("/Library/Caches/com.example.large") })
        }
    }

    @Test("Issue recording is bounded for large trees")
    func boundedIssues() async throws {
        try await withFixture { root in
            for index in 0..<20 {
                try FileManager.default.createSymbolicLink(
                    at: root.appendingPathComponent("link-\(index)"),
                    withDestinationURL: root.appendingPathComponent("missing-\(index)")
                )
            }
            let report = try await DirectoryScanner().scan(
                rootURL: root,
                configuration: ScanConfiguration(maxRecordedIssues: 8)
            )
            #expect(report.totalIssueCount == 20)
            #expect(report.issues.count == 8)
            #expect(report.omittedIssueCount == 12)
        }
    }

    private func withFixture(
        _ operation: (URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacDiskInspectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try await operation(root)
    }
}
