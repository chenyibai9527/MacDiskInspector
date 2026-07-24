import Darwin
import Foundation

public struct ScanConfiguration: Sendable {
    public var aggregationDepth: Int
    public var stayOnSelectedVolume: Bool
    public var deduplicateHardLinks: Bool
    public var progressInterval: Int
    public var maxRecordedIssues: Int

    public init(
        aggregationDepth: Int = 3,
        stayOnSelectedVolume: Bool = true,
        deduplicateHardLinks: Bool = true,
        progressInterval: Int = 250,
        maxRecordedIssues: Int = 5_000
    ) {
        self.aggregationDepth = max(1, aggregationDepth)
        self.stayOnSelectedVolume = stayOnSelectedVolume
        self.deduplicateHardLinks = deduplicateHardLinks
        self.progressInterval = max(1, progressInterval)
        self.maxRecordedIssues = max(1, maxRecordedIssues)
    }
}

private struct HardLinkIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
}

private struct MutableMeasurement {
    var allocatedBytes: Int64 = 0
    var logicalBytes: Int64 = 0
    var fileCount: Int = 0
    var lastModified: Date?

    mutating func add(allocated: Int64, logical: Int64, modified: Date?) {
        allocatedBytes += max(0, allocated)
        logicalBytes += max(0, logical)
        fileCount += 1
        if let modified, lastModified == nil || modified > lastModified! {
            lastModified = modified
        }
    }
}

private final class EnumerationIssueCollector: NSObject, FileManagerDelegate {
    private let limit: Int
    var issues: [ScanIssue] = []
    private(set) var totalIssueCount = 0
    private(set) var inaccessibleIssueCount = 0

    init(limit: Int) {
        self.limit = limit
    }

    var omittedIssueCount: Int {
        max(0, totalIssueCount - issues.count)
    }

    func fileManager(
        _ fileManager: FileManager,
        shouldProceedAfterError error: Error,
        copyingItemAt srcURL: URL,
        to dstURL: URL
    ) -> Bool {
        record(error: error, url: srcURL)
        return true
    }

    func record(error: Error, url: URL) {
        let nsError = error as NSError
        let cocoaPermission = nsError.domain == NSCocoaErrorDomain &&
            nsError.code == NSFileReadNoPermissionError
        let posixPermission = nsError.domain == NSPOSIXErrorDomain &&
            (nsError.code == Int(EACCES) || nsError.code == Int(EPERM))
        let permission = cocoaPermission || posixPermission
        append(
            ScanIssue(
                path: url.path,
                kind: permission ? .permissionDenied : .enumerationFailed,
                message: nsError.localizedDescription
            )
        )
    }

    func append(_ issue: ScanIssue) {
        totalIssueCount += 1
        if issue.kind == .permissionDenied || issue.kind == .enumerationFailed {
            inaccessibleIssueCount += 1
        }
        if issues.count < limit {
            issues.append(issue)
        }
    }
}

public final class DirectoryScanner: @unchecked Sendable {
    private let ruleEngine: RuleEngine

    public init(ruleEngine: RuleEngine = RuleEngine()) {
        self.ruleEngine = ruleEngine
    }

    public func scan(
        rootURL: URL,
        configuration: ScanConfiguration = ScanConfiguration(),
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> ScanReport {
        let task = Task.detached(priority: .userInitiated) { [self] in
            try scanSynchronously(rootURL: rootURL, configuration: configuration, progress: progress)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func scanSynchronously(
        rootURL: URL,
        configuration: ScanConfiguration,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) throws -> ScanReport {
        let startedAt = Date()
        let root = rootURL.standardizedFileURL
        guard root.isFileURL else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let rootStat = try Self.fileStat(atPath: root.path)
        guard !rootStat.isSymbolicLink else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard rootStat.isDirectory else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let manager = FileManager()
        let issueCollector = EnumerationIssueCollector(limit: configuration.maxRecordedIssues)
        manager.delegate = issueCollector
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { url, error in
                issueCollector.record(error: error, url: url)
                return true
            }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var measurements: [String: MutableMeasurement] = [root.path: MutableMeasurement()]
        var seenHardLinks = Set<HardLinkIdentity>()
        var entriesVisited = 0
        var uniqueFiles = 0
        var duplicateHardLinksSkipped = 0
        var totalAllocated: Int64 = 0
        var totalLogical: Int64 = 0

        for case let itemURL as URL in enumerator {
            try Task.checkCancellation()
            entriesVisited += 1

            let stat: PortableStat
            do {
                stat = try Self.fileStat(atPath: itemURL.path)
            } catch {
                issueCollector.record(error: error, url: itemURL)
                continue
            }

            if stat.isSymbolicLink {
                issueCollector.append(
                    ScanIssue(
                        path: itemURL.path,
                        kind: .symbolicLinkSkipped,
                        message: "为避免越界和循环，扫描器不会跟随符号链接。"
                    )
                )
                continue
            }

            if configuration.stayOnSelectedVolume,
               stat.device != rootStat.device {
                if stat.isDirectory {
                    enumerator.skipDescendants()
                }
                issueCollector.append(
                    ScanIssue(
                        path: itemURL.path,
                        kind: .differentVolumeSkipped,
                        message: "该项目位于另一个卷，已跳过。"
                    )
                )
                continue
            }

            guard stat.isRegularFile else { continue }

            if configuration.deduplicateHardLinks && stat.linkCount > 1 {
                let identity = HardLinkIdentity(device: stat.device, inode: stat.inode)
                guard seenHardLinks.insert(identity).inserted else {
                    duplicateHardLinksSkipped += 1
                    continue
                }
            }

            let allocated = stat.allocatedBytes
            let logical = stat.logicalBytes
            uniqueFiles += 1
            totalAllocated += allocated
            totalLogical += logical

            for aggregatePath in aggregatePaths(
                fileURL: itemURL,
                rootURL: root,
                depth: configuration.aggregationDepth
            ) {
                var measurement = measurements[aggregatePath, default: MutableMeasurement()]
                measurement.add(
                    allocated: allocated,
                    logical: logical,
                    modified: stat.modifiedAt
                )
                measurements[aggregatePath] = measurement
            }

            if entriesVisited.isMultiple(of: configuration.progressInterval) {
                progress(
                    ScanProgress(
                        currentPath: itemURL.path,
                        entriesVisited: entriesVisited,
                        allocatedBytesMeasured: totalAllocated
                    )
                )
            }
        }

        let findings = measurements
            .map { path, value in
                ruleEngine.finding(
                    for: DirectoryMeasurement(
                        path: path,
                        allocatedBytes: value.allocatedBytes,
                        logicalBytes: value.logicalBytes,
                        fileCount: value.fileCount,
                        lastModified: value.lastModified
                    )
                )
            }
            .filter { $0.fileCount > 0 }
            .sorted {
                if $0.allocatedBytes == $1.allocatedBytes {
                    return $0.path.localizedStandardCompare($1.path) == .orderedAscending
                }
                return $0.allocatedBytes > $1.allocatedBytes
            }

        progress(
            ScanProgress(
                currentPath: root.path,
                entriesVisited: entriesVisited,
                allocatedBytesMeasured: totalAllocated
            )
        )
        return ScanReport(
            rootPath: root.path,
            startedAt: startedAt,
            finishedAt: Date(),
            findings: findings,
            issues: issueCollector.issues,
            totalIssueCount: issueCollector.totalIssueCount,
            inaccessibleIssueCount: issueCollector.inaccessibleIssueCount,
            omittedIssueCount: issueCollector.omittedIssueCount,
            entriesVisited: entriesVisited,
            uniqueFiles: uniqueFiles,
            duplicateHardLinksSkipped: duplicateHardLinksSkipped,
            totalAllocatedBytes: totalAllocated,
            totalLogicalBytes: totalLogical
        )
    }

    private func aggregatePaths(fileURL: URL, rootURL: URL, depth: Int) -> [String] {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let parentComponents = fileURL.deletingLastPathComponent().standardizedFileURL.pathComponents
        guard parentComponents.starts(with: rootComponents) else { return [rootURL.path] }
        let relative = Array(parentComponents.dropFirst(rootComponents.count))
        var paths = Set([rootURL.path])
        guard !relative.isEmpty else {
            includeExactFileRule(fileURL, in: &paths)
            return Array(paths)
        }
        for level in 1...min(depth, relative.count) {
            let components = rootComponents + relative.prefix(level)
            paths.insert(NSString.path(withComponents: Array(components)))
        }
        if relative.count > depth {
            for level in (depth + 1)...relative.count {
                let components = rootComponents + relative.prefix(level)
                let path = NSString.path(withComponents: Array(components))
                if ruleEngine.matchedRule(forPath: path).identifier != "unknown" {
                    paths.insert(path)
                }
            }
        }
        includeExactFileRule(fileURL, in: &paths)
        return Array(paths)
    }

    private func includeExactFileRule(_ fileURL: URL, in paths: inout Set<String>) {
        let identifier = ruleEngine.matchedRule(forPath: fileURL.path).identifier
        if identifier == "cursor.state-database" || identifier == "system.swapfile" {
            paths.insert(fileURL.path)
        }
    }

    private struct PortableStat {
        let device: UInt64
        let inode: UInt64
        let linkCount: UInt64
        let logicalBytes: Int64
        let allocatedBytes: Int64
        let modifiedAt: Date
        let mode: mode_t

        var isSymbolicLink: Bool { mode & S_IFMT == S_IFLNK }
        var isDirectory: Bool { mode & S_IFMT == S_IFDIR }
        var isRegularFile: Bool { mode & S_IFMT == S_IFREG }
    }

    private static func fileStat(atPath path: String) throws -> PortableStat {
        var info = stat()
        let result = path.withCString { lstat($0, &info) }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let modified = Double(info.st_mtimespec.tv_sec) +
            Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
        return PortableStat(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            linkCount: UInt64(info.st_nlink),
            logicalBytes: Int64(info.st_size),
            allocatedBytes: Int64(info.st_blocks) * 512,
            modifiedAt: Date(timeIntervalSince1970: modified),
            mode: info.st_mode
        )
    }
}
