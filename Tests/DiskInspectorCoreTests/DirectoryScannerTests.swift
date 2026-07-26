import Darwin
import Foundation
import Testing
@testable import DiskInspectorCore

private actor ProgressLatch {
    private var reached = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if reached { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func signal() {
        reached = true
        continuation?.resume()
        continuation = nil
    }
}

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

    @Test("Skips configured protected directories without reading their contents")
    func protectedDirectoryExclusions() async throws {
        try await withFixture { root in
            let protected = root.appendingPathComponent("Pictures", isDirectory: true)
            try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
            try Data(repeating: 9, count: 4096).write(
                to: protected.appendingPathComponent("private-photo.jpg")
            )
            try Data(repeating: 1, count: 2048).write(
                to: root.appendingPathComponent("visible.bin")
            )

            let report = try await DirectoryScanner().scan(
                rootURL: root,
                configuration: ScanConfiguration(
                    excludedDirectories: [
                        ScanExcludedDirectory(
                            path: protected.path,
                            reason: "测试：按隐私设置跳过。"
                        )
                    ]
                )
            )

            #expect(report.uniqueFiles == 1)
            #expect(report.totalLogicalBytes == 2048)
            #expect(report.protectedDirectorySkippedCount == 1)
            #expect(report.hasCoverageGaps)
            #expect(report.issues.contains {
                $0.kind == .protectedDirectorySkipped &&
                    $0.path == protected.path
            })
        }
    }

    @Test("Skips both app container roots while continuing the rest of the scan")
    func appContainerExclusions() async throws {
        try await withFixture { root in
            let containers = root.appendingPathComponent("Library/Containers", isDirectory: true)
            let groupContainers = root.appendingPathComponent(
                "Library/Group Containers",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: containers.appendingPathComponent("com.example.private"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: groupContainers.appendingPathComponent("group.example.private"),
                withIntermediateDirectories: true
            )
            try Data(repeating: 1, count: 4_096).write(
                to: containers.appendingPathComponent("com.example.private/data.bin")
            )
            try Data(repeating: 2, count: 4_096).write(
                to: groupContainers.appendingPathComponent("group.example.private/data.bin")
            )
            try Data(repeating: 3, count: 2_048).write(
                to: root.appendingPathComponent("visible.bin")
            )

            let report = try await DirectoryScanner().scan(
                rootURL: root,
                configuration: ScanConfiguration(
                    excludedDirectories: [
                        ScanExcludedDirectory(path: containers.path, reason: "测试跳过容器。"),
                        ScanExcludedDirectory(
                            path: groupContainers.path,
                            reason: "测试跳过共享容器。"
                        )
                    ]
                )
            )

            #expect(report.uniqueFiles == 1)
            #expect(report.totalLogicalBytes == 2_048)
            #expect(report.protectedDirectorySkippedCount == 2)
            #expect(report.issues.filter { $0.kind == .protectedDirectorySkipped }.count == 2)
        }
    }

    @Test("A protected scan root returns an explicit coverage gap")
    func protectedRootExclusion() async throws {
        try await withFixture { root in
            try Data([1, 2, 3]).write(to: root.appendingPathComponent("private.bin"))

            let report = try await DirectoryScanner().scan(
                rootURL: root,
                configuration: ScanConfiguration(
                    excludedDirectories: [
                        ScanExcludedDirectory(
                            path: root.path,
                            reason: "测试：根目录默认跳过。"
                        )
                    ]
                )
            )

            #expect(report.entriesVisited == 0)
            #expect(report.uniqueFiles == 0)
            #expect(report.protectedDirectorySkippedCount == 1)
            #expect(report.issues.first?.kind == .protectedDirectorySkipped)
        }
    }

    @Test("APFS Data volume mirrors cannot bypass protected directory exclusions")
    func dataVolumeMirrorPathNormalization() {
        #expect(
            DirectoryScanner.comparisonPath(
                "/System/Volumes/Data/Users/test/Music/Media.localized"
            ) == "/Users/test/Music/Media.localized"
        )
        #expect(
            DirectoryScanner.comparisonPath(
                "/System/Volumes/Data/Users/test/Pictures/Photos Library.photoslibrary"
            ) == "/Users/test/Pictures/Photos Library.photoslibrary"
        )
        #expect(
            DirectoryScanner.comparisonPath(
                "/System/Volumes/Data/private/var/folders/example"
            ) == "/var/folders/example"
        )
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

    @Test("Can return explicitly partial findings when cancellation requests them")
    func partialResultsOnCancellation() async throws {
        try await withFixture { root in
            for index in 0..<400 {
                try Data(repeating: UInt8(index % 255), count: 1_024).write(
                    to: root.appendingPathComponent("file-\(index)")
                )
            }

            let reachedProgress = ProgressLatch()
            let task = Task {
                try await DirectoryScanner().scan(
                    rootURL: root,
                    configuration: ScanConfiguration(
                        progressInterval: 1,
                        returnPartialResultsOnCancellation: true
                    )
                ) { update in
                    if update.entriesVisited == 1 {
                        Task { await reachedProgress.signal() }
                    }
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }

            await reachedProgress.wait()
            task.cancel()
            let report = try await task.value

            #expect(report.isPartial)
            #expect(report.entriesVisited > 0)
            #expect(report.entriesVisited < 400)
            #expect(report.uniqueFiles > 0)
            #expect(report.hasCoverageGaps)
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
