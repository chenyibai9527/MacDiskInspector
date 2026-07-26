import Foundation

public enum FindingCategory: String, CaseIterable, Codable, Sendable {
    case regenerableCache = "可重新生成缓存"
    case appManaged = "应用内可管理数据"
    case userData = "用户数据"
    case anomalous = "异常数据"
    case systemManaged = "系统管理数据"
    case unknown = "未知数据"
    case inaccessible = "无权限访问"
}

public enum FindingRisk: String, CaseIterable, Codable, Sendable {
    case low = "低风险"
    case medium = "需确认"
    case high = "高风险"
    case prohibited = "禁止手动处理"

    public var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .prohibited: 3
        }
    }
}

public enum Confidence: String, CaseIterable, Codable, Sendable {
    case low = "低"
    case medium = "中"
    case high = "高"
}

public enum Reclaimability: String, Codable, Sendable {
    case notEstimated
    case candidate
}

public struct Finding: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let path: String
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let fileCount: Int
    public let lastModified: Date?
    public let sourceApplication: String?
    public let category: FindingCategory
    public let risk: FindingRisk
    public let confidence: Confidence
    public let explanation: String
    public let potentialReclaimableBytes: Int64?
    public let reclaimability: Reclaimability
    public let recommendedAction: String
    public let ruleIdentifier: String

    public init(
        id: UUID = UUID(),
        path: String,
        allocatedBytes: Int64,
        logicalBytes: Int64,
        fileCount: Int,
        lastModified: Date?,
        sourceApplication: String?,
        category: FindingCategory,
        risk: FindingRisk,
        confidence: Confidence,
        explanation: String,
        potentialReclaimableBytes: Int64?,
        reclaimability: Reclaimability,
        recommendedAction: String,
        ruleIdentifier: String
    ) {
        self.id = id
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.fileCount = fileCount
        self.lastModified = lastModified
        self.sourceApplication = sourceApplication
        self.category = category
        self.risk = risk
        self.confidence = confidence
        self.explanation = explanation
        self.potentialReclaimableBytes = potentialReclaimableBytes
        self.reclaimability = reclaimability
        self.recommendedAction = recommendedAction
        self.ruleIdentifier = ruleIdentifier
    }
}

public struct DirectoryMeasurement: Hashable, Sendable {
    public let path: String
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let fileCount: Int
    public let lastModified: Date?

    public init(
        path: String,
        allocatedBytes: Int64,
        logicalBytes: Int64,
        fileCount: Int,
        lastModified: Date?
    ) {
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.fileCount = fileCount
        self.lastModified = lastModified
    }
}

public enum ScanIssueKind: String, Codable, Sendable {
    case permissionDenied = "无权限"
    case protectedDirectorySkipped = "按设置跳过"
    case symbolicLinkSkipped = "已跳过符号链接"
    case differentVolumeSkipped = "已跳过其他卷"
    case unreadableMetadata = "无法读取元数据"
    case enumerationFailed = "目录读取失败"
}

public struct ScanIssue: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let path: String
    public let kind: ScanIssueKind
    public let message: String

    public init(id: UUID = UUID(), path: String, kind: ScanIssueKind, message: String) {
        self.id = id
        self.path = path
        self.kind = kind
        self.message = message
    }
}

public struct ScanProgress: Sendable {
    public let currentPath: String
    public let entriesVisited: Int
    public let allocatedBytesMeasured: Int64

    public init(currentPath: String, entriesVisited: Int, allocatedBytesMeasured: Int64) {
        self.currentPath = currentPath
        self.entriesVisited = entriesVisited
        self.allocatedBytesMeasured = allocatedBytesMeasured
    }
}

public struct ScanReport: Sendable {
    public let rootPath: String
    public let startedAt: Date
    public let finishedAt: Date
    public let findings: [Finding]
    public let issues: [ScanIssue]
    public let totalIssueCount: Int
    public let inaccessibleIssueCount: Int
    public let protectedDirectorySkippedCount: Int
    public let omittedIssueCount: Int
    public let entriesVisited: Int
    public let uniqueFiles: Int
    public let duplicateHardLinksSkipped: Int
    public let totalAllocatedBytes: Int64
    public let totalLogicalBytes: Int64
    public let isPartial: Bool

    public var hasCoverageGaps: Bool {
        isPartial || inaccessibleIssueCount > 0 || protectedDirectorySkippedCount > 0
    }
}

public struct VolumeCapacity: Sendable {
    public let name: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let availableForImportantUsageBytes: Int64?

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    public init(
        name: String,
        totalBytes: Int64,
        availableBytes: Int64,
        availableForImportantUsageBytes: Int64? = nil
    ) {
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.availableForImportantUsageBytes = availableForImportantUsageBytes
    }
}
