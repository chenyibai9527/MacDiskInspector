import Foundation

public struct FindingRule: Sendable {
    public let identifier: String
    public let sourceApplication: String?
    public let category: FindingCategory
    public let risk: FindingRisk
    public let confidence: Confidence
    public let explanation: String
    public let recommendedAction: String
    public let reclaimability: Reclaimability
    private let matcher: @Sendable (String) -> Bool

    public init(
        identifier: String,
        sourceApplication: String?,
        category: FindingCategory,
        risk: FindingRisk,
        confidence: Confidence,
        explanation: String,
        recommendedAction: String,
        reclaimability: Reclaimability,
        matcher: @escaping @Sendable (String) -> Bool
    ) {
        self.identifier = identifier
        self.sourceApplication = sourceApplication
        self.category = category
        self.risk = risk
        self.confidence = confidence
        self.explanation = explanation
        self.recommendedAction = recommendedAction
        self.reclaimability = reclaimability
        self.matcher = matcher
    }

    public func matches(path: String) -> Bool {
        matcher(path)
    }
}

public struct RuleEngine: Sendable {
    public let rules: [FindingRule]

    public init(rules: [FindingRule] = RuleEngine.defaultRules) {
        self.rules = rules
    }

    public func finding(for measurement: DirectoryMeasurement) -> Finding {
        let rule = matchedRule(forPath: measurement.path)
        let candidateBytes: Int64? = rule.reclaimability == .candidate && measurement.allocatedBytes > 0
            ? measurement.allocatedBytes
            : nil
        return Finding(
            path: measurement.path,
            allocatedBytes: measurement.allocatedBytes,
            logicalBytes: measurement.logicalBytes,
            fileCount: measurement.fileCount,
            lastModified: measurement.lastModified,
            sourceApplication: rule.sourceApplication,
            category: rule.category,
            risk: rule.risk,
            confidence: rule.confidence,
            explanation: rule.explanation,
            potentialReclaimableBytes: candidateBytes,
            reclaimability: rule.reclaimability,
            recommendedAction: rule.recommendedAction,
            ruleIdentifier: rule.identifier
        )
    }

    func matchedRule(forPath path: String) -> FindingRule {
        let normalized = Self.normalize(path)
        return rules.first { $0.matches(path: normalized) } ?? Self.unknownRule
    }

    public static func normalize(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
    }

    public static let defaultRules: [FindingRule] = [
        FindingRule(
            identifier: "system.swapfile",
            sourceApplication: "macOS",
            category: .systemManaged,
            risk: .prohibited,
            confidence: .high,
            explanation: "交换文件由 macOS 虚拟内存系统自动创建和回收。它的体积会随内存压力变化，手动删除可能导致系统不稳定。",
            recommendedAction: "不要手动删除。关闭高内存应用并正常重启后再观察。",
            reclaimability: .notEstimated
        ) { path in
            path == "/private/var/vm" ||
            path.hasPrefix("/private/var/vm/swapfile") ||
            path == "/system/volumes/vm" ||
            path.hasPrefix("/system/volumes/vm/swapfile")
        },
        FindingRule(
            identifier: "system.protected",
            sourceApplication: "macOS",
            category: .systemManaged,
            risk: .prohibited,
            confidence: .high,
            explanation: "这是 macOS 或 APFS 管理的系统区域，不应作为普通文件手动处理。",
            recommendedAction: "仅使用系统设置或 Apple 提供的管理入口。",
            reclaimability: .notEstimated
        ) { path in
            Self.isExactOrDirectChild(path, of: "/system") ||
            path == "/.mobilebackups" ||
            path == "/volumes/com.apple.timemachine.localsnapshots"
        },
        FindingRule(
            identifier: "gemini.antigravity.browser-recordings",
            sourceApplication: "Gemini / Antigravity",
            category: .anomalous,
            risk: .medium,
            confidence: .high,
            explanation: "browser_recordings 通常是自动化浏览器录制产生的大量帧图像。异常的文件数量或单次录制体积可能长期占用空间。",
            recommendedAction: "先在 Finder 中核对录制日期与所属任务；确认不再需要后，使用产生这些录制的应用管理数据。",
            reclaimability: .candidate
        ) { path in
            path.hasSuffix("/.gemini/antigravity/browser_recordings") ||
            path.hasSuffix("/.gemini/browser_recordings")
        },
        FindingRule(
            identifier: "cursor.state-database",
            sourceApplication: "Cursor",
            category: .appManaged,
            risk: .high,
            confidence: .high,
            explanation: "state.vscdb 保存编辑器工作台状态、扩展状态或会话数据；backup 也不是普通缓存。直接删除可能丢失重要状态。",
            recommendedAction: "不要把它当缓存删除。退出 Cursor 后先备份，并优先通过 Cursor 的设置、扩展或工作区管理功能排查。",
            reclaimability: .notEstimated
        ) { path in
            path.contains("/library/application support/cursor/") &&
            (path.hasSuffix("/state.vscdb") || path.hasSuffix("/state.vscdb.backup"))
        },
        FindingRule(
            identifier: "wechat.container",
            sourceApplication: "微信",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "微信容器可能包含消息数据库、接收文件、图片和索引。消息数据库属于用户数据，不能按缓存处理。",
            recommendedAction: "仅通过微信“存储空间”管理，或在 Finder 中查看已确认的接收文件；不要删除数据库。",
            reclaimability: .notEstimated
        ) { path in
            let isWeChatContainer = path.hasSuffix("/library/containers/com.tencent.xinwechat") ||
                path.hasSuffix("/library/containers/com.tencent.xinwechat/data")
            let isWeChatDataTree = path.contains("/library/containers/com.tencent.xinwechat/") &&
                path.hasSuffix("/micromessenger")
            return isWeChatContainer || isWeChatDataTree
        },
        FindingRule(
            identifier: "chrome.on-device-model",
            sourceApplication: "Google Chrome",
            category: .appManaged,
            risk: .medium,
            confidence: .high,
            explanation: "OnDeviceModel 是 Chrome 下载的本地模型数据，通常可由 Chrome 重新获取，但不应在浏览器运行时直接修改。",
            recommendedAction: "先更新或退出 Chrome，并通过 Chrome 的组件、AI 功能或配置入口管理；处理前在 Finder 中核对路径。",
            reclaimability: .candidate
        ) { path in
            path.contains("/library/application support/") &&
            path.hasSuffix("/google/chrome/ondevicemodel")
        },
        FindingRule(
            identifier: "npm.cache",
            sourceApplication: "npm",
            category: .regenerableCache,
            risk: .low,
            confidence: .high,
            explanation: "npm 的 _cacache 是内容寻址下载缓存，通常可重新生成。先验证缓存完整性，再决定是否使用 npm 自己的清理命令。",
            recommendedAction: "复制“npm cache verify”检查；确需回收时再复制 npm 官方清理命令。",
            reclaimability: .candidate
        ) { path in
            path.hasSuffix("/.npm/_cacache")
        },
        FindingRule(
            identifier: "library.caches",
            sourceApplication: nil,
            category: .regenerableCache,
            risk: .medium,
            confidence: .medium,
            explanation: "Library/Caches 通常保存可重新生成的数据，但不同应用的退出状态、同步任务和离线内容含义不同。",
            recommendedAction: "先按应用排序并退出对应应用；优先使用应用内置的缓存管理功能。",
            reclaimability: .candidate
        ) { path in
            Self.isExactOrDirectChild(path, of: "/library/caches")
        }
    ]

    public static let unknownRule = FindingRule(
        identifier: "unknown",
        sourceApplication: nil,
        category: .unknown,
        risk: .medium,
        confidence: .low,
        explanation: "当前规则无法可靠判断这项数据的用途。体积本身不是可安全清理的证据。",
        recommendedAction: "在 Finder 中查看，确认来源与用途后再决定。",
        reclaimability: .notEstimated
    ) { _ in true }

    private static func isExactOrDirectChild(_ path: String, of marker: String) -> Bool {
        guard let range = path.range(of: marker, options: .backwards) else { return false }
        let suffix = path[range.upperBound...]
        guard suffix.isEmpty || suffix.first == "/" else { return false }
        let remainder = suffix.drop(while: { $0 == "/" })
        return remainder.isEmpty || !remainder.contains("/")
    }
}
