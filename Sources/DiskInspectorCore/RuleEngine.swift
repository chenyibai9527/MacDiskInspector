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
            explanation: "这是 macOS 为虚拟内存自动创建的交换文件。内存紧张时它会变大，系统会按需管理；手动删除可能造成系统异常。",
            recommendedAction: "不要手动删除。可以先退出占用内存较多的应用，正常重启 Mac 后再观察。",
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
            explanation: "这部分空间由 macOS 或 APFS 文件系统管理，不能按普通文件处理。",
            recommendedAction: "不要手动删除。只通过“系统设置”或 Apple 提供的工具管理。",
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
            explanation: "browser_recordings 保存自动化浏览器录制时产生的连续画面。一次长时间录制就可能生成大量图片，并在任务结束后继续占用空间。",
            recommendedAction: "先在访达中查看录制日期和所属任务。确认已经不需要后，再回到生成这些录制的应用中管理。",
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
            explanation: "state.vscdb 保存 Cursor 的界面、扩展和会话状态，备份文件也不是普通缓存。直接删除可能丢失设置或工作状态。",
            recommendedAction: "不要把它当作缓存删除。先退出 Cursor 并做好备份，再从 Cursor 的设置、扩展或工作区中查找占用来源。",
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
            explanation: "这里可能包含微信的聊天记录、接收文件、图片和索引。聊天数据库属于重要的个人数据，不能当作缓存处理。",
            recommendedAction: "优先使用微信自带的“存储空间”功能。也可以在访达中检查已经确认的接收文件，但不要直接删除数据库。",
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
            explanation: "OnDeviceModel 是 Chrome 下载到本机的模型文件。通常可以重新下载，但在 Chrome 运行时直接改动可能造成异常。",
            recommendedAction: "先退出或更新 Chrome，再从 Chrome 的组件或相关功能设置中管理。处理前可在访达中核对路径。",
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
            explanation: "_cacache 保存 npm 下载过的软件包，内容通常可以重新获取。",
            recommendedAction: "先复制并运行“npm cache verify”检查缓存。确认需要清理时，再使用 npm 自带的清理命令。",
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
            explanation: "Library/Caches 通常保存应用可以重新生成的临时数据，但其中也可能有离线内容或尚未完成的任务。",
            recommendedAction: "先确认这些文件属于哪个应用，并退出该应用。能在应用内清理时，优先使用应用自己的存储管理功能。",
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
        explanation: "目前无法可靠判断这项内容的用途。占用空间很大，并不代表它可以安全删除。",
        recommendedAction: "先在访达中查看，弄清来源和用途后再决定是否处理。",
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
