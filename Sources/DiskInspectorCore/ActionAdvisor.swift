import Foundation

public enum SuggestedActionKind: String, Codable, Sendable {
    case revealInFinder
    case openApplication
    case copyInspectionCommand
    case copyOfficialCleanupCommand
    case deferAction
}

public struct SuggestedAction: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: SuggestedActionKind
    public let title: String
    public let value: String?
    public let isDestructive: Bool

    public init(id: String, kind: SuggestedActionKind, title: String, value: String?, isDestructive: Bool) {
        self.id = id
        self.kind = kind
        self.title = title
        self.value = value
        self.isDestructive = isDestructive
    }
}

public struct ActionAdvisor: Sendable {
    private static let inspectionCommands: [String: String] = [
        "npm.cache": "npm cache verify"
    ]

    private static let cleanupCommands: [String: String] = [
        "npm.cache": "npm cache clean --force"
    ]

    public init() {}

    public func actions(for finding: Finding) -> [SuggestedAction] {
        var actions = [
            SuggestedAction(
                id: "finder",
                kind: .revealInFinder,
                title: "在访达中显示",
                value: finding.path,
                isDestructive: false
            )
        ]

        if finding.risk != .high && finding.risk != .prohibited {
            if let command = Self.inspectionCommands[finding.ruleIdentifier] {
                actions.append(
                    SuggestedAction(
                        id: "inspect.\(finding.ruleIdentifier)",
                        kind: .copyInspectionCommand,
                        title: "复制检查命令",
                        value: command,
                        isDestructive: false
                    )
                )
            }
            if let command = Self.cleanupCommands[finding.ruleIdentifier] {
                actions.append(
                    SuggestedAction(
                        id: "cleanup.\(finding.ruleIdentifier)",
                        kind: .copyOfficialCleanupCommand,
                        title: "复制 npm 官方清理命令",
                        value: command,
                        isDestructive: true
                    )
                )
            }
        }

        if let bundleIdentifier = bundleIdentifier(for: finding.ruleIdentifier) {
            actions.append(
                SuggestedAction(
                    id: "app.\(bundleIdentifier)",
                    kind: .openApplication,
                    title: "打开相关应用",
                    value: bundleIdentifier,
                    isDestructive: false
                )
            )
        }

        actions.append(
            SuggestedAction(
                id: "defer",
                kind: .deferAction,
                title: "暂不处理",
                value: nil,
                isDestructive: false
            )
        )
        return actions
    }

    private func bundleIdentifier(for ruleIdentifier: String) -> String? {
        switch ruleIdentifier {
        case "wechat.container": "com.tencent.xinWeChat"
        case "chrome.on-device-model": "com.google.Chrome"
        case "cursor.state-database": "com.todesktop.230313mzl4w4u92"
        default: nil
        }
    }
}
