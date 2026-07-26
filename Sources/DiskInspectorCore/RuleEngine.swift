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
            identifier: "system.apfs-data-volume",
            sourceApplication: "macOS / APFS",
            category: .systemManaged,
            risk: .prohibited,
            confidence: .high,
            explanation: "这是 APFS 数据卷的挂载入口，汇总了应用和用户数据，并不是一个可以整体清理的普通目录。",
            recommendedAction: "不要手动处理这个挂载入口。请继续查看它下面已经识别出的具体目录。",
            reclaimability: .notEstimated
        ) { path in
            path == "/system/volumes/data"
        },
        FindingRule(
            identifier: "system.var-folders",
            sourceApplication: "macOS",
            category: .systemManaged,
            risk: .prohibited,
            confidence: .high,
            explanation: "var/folders 保存 macOS 和应用按用户隔离的临时文件、缓存及运行状态。系统会管理其中内容，直接清空可能影响正在运行的应用。",
            recommendedAction: "不要手动批量删除。先退出异常应用或正常重启，再观察空间是否由系统回收。",
            reclaimability: .notEstimated
        ) { path in
            path == "/private/var/folders" || path == "/var/folders"
        },
        FindingRule(
            identifier: "system.metadata",
            sourceApplication: "macOS",
            category: .systemManaged,
            risk: .prohibited,
            confidence: .high,
            explanation: "这是 Spotlight、文件系统事件或废纸篓等系统维护目录，大小和生命周期由 macOS 管理。",
            recommendedAction: "不要直接删除。索引或系统状态异常时，应使用对应的 macOS 设置或 Apple 工具处理。",
            reclaimability: .notEstimated
        ) { path in
            path == "/.spotlight-v100" ||
            path == "/.fseventsd" ||
            path == "/.trashes"
        },
        FindingRule(
            identifier: "system.library-root",
            sourceApplication: "macOS 与系统级应用",
            category: .systemManaged,
            risk: .prohibited,
            confidence: .high,
            explanation: "根目录下的 Library 保存系统级支持文件、字体、插件、开发组件和所有用户共享的应用数据。",
            recommendedAction: "不要把整个目录当作缓存。只通过系统设置、应用卸载器或对应开发工具管理其中的具体内容。",
            reclaimability: .notEstimated
        ) { path in
            path == "/library"
        },
        FindingRule(
            identifier: "system.applications",
            sourceApplication: "macOS",
            category: .appManaged,
            risk: .medium,
            confidence: .high,
            explanation: "Applications 保存已安装的 Mac 应用。应用包可能很大，但删除应用也不一定会移除它的用户数据。",
            recommendedAction: "先确认应用是否仍在使用。需要卸载时优先使用应用自带卸载器或开发者说明。",
            reclaimability: .notEstimated
        ) { path in
            path == "/applications"
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
            identifier: "ai-tool.workspace-data",
            sourceApplication: "AI 开发工具",
            category: .appManaged,
            risk: .high,
            confidence: .medium,
            explanation: "这里可能保存会话、索引、工作区状态、模型缓存或任务产物。不同版本的目录结构会变化，不能把整个目录当作普通缓存。",
            recommendedAction: "先在对应应用中确认会话、项目和本地模型的用途。重要记录应先导出或备份。",
            reclaimability: .notEstimated
        ) { path in
            path.hasSuffix("/.codex") ||
            path.hasSuffix("/.gemini")
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
            identifier: "cursor.application-data",
            sourceApplication: "Cursor",
            category: .appManaged,
            risk: .high,
            confidence: .high,
            explanation: "这是 Cursor 的设置、扩展、工作区状态和本地索引目录，其中可能包含无法自动恢复的编辑器状态。",
            recommendedAction: "优先在 Cursor 中管理扩展、工作区和缓存。不要把整个目录直接删除。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/application support/cursor")
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
            guard Self.isUserHomeLibraryPath(path) else { return false }
            let isWeChatContainer = path.hasSuffix("/library/containers/com.tencent.xinwechat") ||
                path.hasSuffix("/library/containers/com.tencent.xinwechat/data") ||
                path.hasSuffix("/library/containers/com.tencent.xinwechat/data/documents")
            let isWeChatDataTree = path.contains("/library/containers/com.tencent.xinwechat/") &&
                path.hasSuffix("/micromessenger")
            return isWeChatContainer || isWeChatDataTree
        },
        FindingRule(
            identifier: "qq.container",
            sourceApplication: "QQ",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "QQ 容器可能包含聊天记录、接收文件、图片、数据库和索引，属于重要的个人数据。",
            recommendedAction: "优先使用 QQ 自带的存储管理功能。不要直接删除聊天数据库或整个容器。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            (path.hasSuffix("/library/containers/com.tencent.qq") ||
            path.hasSuffix("/library/containers/com.tencent.qq/data")
            )
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
            Self.isUserHomeLibraryPath(path) &&
            path.contains("/library/application support/") &&
            path.hasSuffix("/google/chrome/ondevicemodel")
        },
        FindingRule(
            identifier: "chrome.profile-data",
            sourceApplication: "Google Chrome",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "Chrome 的应用支持目录包含浏览器配置、扩展、登录状态、历史记录和站点数据，并不只是缓存。",
            recommendedAction: "优先使用 Chrome 的设置管理浏览数据、下载内容和扩展。不要直接删除整个配置目录。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/application support/google/chrome")
        },
        FindingRule(
            identifier: "google.application-data",
            sourceApplication: "Google 应用",
            category: .appManaged,
            risk: .high,
            confidence: .medium,
            explanation: "这里汇总 Google 应用的本地配置、账号状态、组件和用户数据，通常不应整体视为缓存。",
            recommendedAction: "继续查看下一级具体应用，并优先在对应应用中管理。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/application support/google")
        },
        FindingRule(
            identifier: "edge.profile-data",
            sourceApplication: "Microsoft Edge",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "Edge 的应用支持目录包含浏览器配置、扩展、账号状态、历史记录和站点数据。",
            recommendedAction: "优先使用 Edge 的浏览数据和扩展管理功能，不要直接删除整个目录。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/application support/microsoft edge")
        },
        FindingRule(
            identifier: "firefox.profile-data",
            sourceApplication: "Firefox",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "Firefox Profiles 保存书签、扩展、登录信息、历史记录和站点数据，属于浏览器用户资料。",
            recommendedAction: "优先使用 Firefox 的配置文件与浏览数据管理功能。重要资料应先同步或备份。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            (path.hasSuffix("/library/application support/firefox") ||
            path.hasSuffix("/library/application support/firefox/profiles")
            )
        },
        FindingRule(
            identifier: "safari.user-data",
            sourceApplication: "Safari",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "Safari 数据可能包含历史记录、网站数据、阅读列表、扩展状态和标签页恢复信息。",
            recommendedAction: "使用 Safari 的“设置”和“清除历史记录”功能管理，不要直接删除数据库。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/safari")
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
            Self.isExactOrDirectChild(path, of: "/.npm/_cacache")
        },
        FindingRule(
            identifier: "npm.data",
            sourceApplication: "npm",
            category: .appManaged,
            risk: .medium,
            confidence: .high,
            explanation: ".npm 由 npm 使用，除下载缓存外还可能包含日志、更新状态和工具元数据，不能假定全部可删除。",
            recommendedAction: "继续查看 _cacache 等具体项目。缓存应通过 npm 官方命令验证和管理。",
            reclaimability: .notEstimated
        ) { path in
            path.hasSuffix("/.npm")
        },
        FindingRule(
            identifier: "developer.package-cache",
            sourceApplication: "开发工具",
            category: .regenerableCache,
            risk: .medium,
            confidence: .medium,
            explanation: "这是常见开发包管理器的下载缓存或本地依赖仓库，通常能够重新获取，但重新下载可能耗时且依赖网络。",
            recommendedAction: "先确认对应工具和项目仍可正常恢复依赖，再使用该工具自己的缓存检查或清理功能。",
            reclaimability: .candidate
        ) { path in
            path.hasSuffix("/.pnpm-store") ||
            path.hasSuffix("/.yarn/cache") ||
            path.hasSuffix("/.gradle/caches") ||
            path.hasSuffix("/.m2/repository") ||
            path.hasSuffix("/.cargo/registry") ||
            path.hasSuffix("/library/caches/homebrew")
        },
        FindingRule(
            identifier: "developer.generic-cache",
            sourceApplication: "开发工具与应用",
            category: .regenerableCache,
            risk: .medium,
            confidence: .medium,
            explanation: ".cache 通常保存命令行工具、模型或开发程序可重新生成的数据，但也可能包含离线资源和未完成任务。",
            recommendedAction: "先查看下一级来源并退出相关工具。优先使用来源工具自己的缓存管理功能。",
            reclaimability: .candidate
        ) { path in
            Self.isExactOrDirectChild(path, of: "/.cache")
        },
        FindingRule(
            identifier: "node.version-manager",
            sourceApplication: "Node.js 开发环境",
            category: .appManaged,
            risk: .medium,
            confidence: .high,
            explanation: "这里保存 Node.js 的多个版本、全局包和版本管理器状态。较旧版本可能很大，但项目仍可能依赖它们。",
            recommendedAction: "先检查项目使用的 Node.js 版本，再通过 nvm、Volta 或对应版本管理器卸载不用的版本。",
            reclaimability: .notEstimated
        ) { path in
            path.hasSuffix("/.nvm") ||
            path.hasSuffix("/.volta") ||
            path.hasSuffix("/.asdf")
        },
        FindingRule(
            identifier: "xcode.derived-data",
            sourceApplication: "Xcode",
            category: .regenerableCache,
            risk: .low,
            confidence: .high,
            explanation: "DerivedData 保存 Xcode 构建产物、索引和中间文件，删除后会在下次构建时重新生成。",
            recommendedAction: "优先从 Xcode 的项目或设置中管理。清理后首次索引和构建会明显变慢。",
            reclaimability: .candidate
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/developer/xcode/deriveddata")
        },
        FindingRule(
            identifier: "xcode.archives",
            sourceApplication: "Xcode",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "Archives 保存应用归档、符号文件和发布记录，可能用于重新导出、崩溃符号化或版本追溯。",
            recommendedAction: "只在 Xcode Organizer 中删除已经确认不再需要的归档。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/developer/xcode/archives")
        },
        FindingRule(
            identifier: "xcode.simulators",
            sourceApplication: "Xcode Simulator",
            category: .appManaged,
            risk: .medium,
            confidence: .high,
            explanation: "CoreSimulator 保存模拟器运行时、虚拟设备、应用和测试数据，通常是开发环境中的主要占用之一。",
            recommendedAction: "通过 Xcode 的 Platforms/Components 或 Simulator 的设备管理功能移除不用的运行时与设备。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            (path.hasSuffix("/library/developer/coresimulator") ||
            path.hasSuffix("/library/developer/xcode/ios devicesupport")
            )
        },
        FindingRule(
            identifier: "android.development-data",
            sourceApplication: "Android 开发工具",
            category: .appManaged,
            risk: .medium,
            confidence: .high,
            explanation: "这里可能包含 Android SDK、系统镜像、模拟器和虚拟设备数据，通常应由 Android Studio 或 SDK Manager 管理。",
            recommendedAction: "使用 Android Studio 的 SDK Manager 与 Device Manager 移除不用的组件和虚拟设备。",
            reclaimability: .notEstimated
        ) { path in
            (Self.isUserHomeLibraryPath(path) &&
                path.hasSuffix("/library/android/sdk")) ||
            path.hasSuffix("/.android/avd")
        },
        FindingRule(
            identifier: "docker.desktop-data",
            sourceApplication: "Docker Desktop",
            category: .appManaged,
            risk: .high,
            confidence: .high,
            explanation: "Docker Desktop 数据可能包含镜像、容器、卷和 Linux 虚拟磁盘。卷中可能有数据库等重要数据。",
            recommendedAction: "只通过 Docker Desktop 或 Docker CLI 查看和管理镜像、容器与卷，不要直接删除虚拟磁盘文件。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            (path.hasSuffix("/library/containers/com.docker.docker") ||
            path.hasSuffix("/library/group containers/group.com.docker")
            )
        },
        FindingRule(
            identifier: "homebrew.data",
            sourceApplication: "Homebrew",
            category: .appManaged,
            risk: .medium,
            confidence: .high,
            explanation: "这是 Homebrew 安装的软件包、版本和链接目录。直接删除其中项目可能破坏命令行环境。",
            recommendedAction: "使用 brew list、brew outdated 和 brew cleanup 等 Homebrew 命令检查与管理。",
            reclaimability: .notEstimated
        ) { path in
            path == "/opt/homebrew" ||
            path == "/usr/local/cellar"
        },
        FindingRule(
            identifier: "adobe.application-data",
            sourceApplication: "Adobe Creative Cloud",
            category: .appManaged,
            risk: .high,
            confidence: .high,
            explanation: "Adobe 应用支持目录可能包含插件、预设、素材库、同步状态和项目相关数据，并不只是缓存。",
            recommendedAction: "优先从 Creative Cloud 或对应 Adobe 应用中管理插件、素材和缓存。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/application support/adobe")
        },
        FindingRule(
            identifier: "adobe.cache",
            sourceApplication: "Adobe Creative Cloud",
            category: .regenerableCache,
            risk: .medium,
            confidence: .medium,
            explanation: "这是 Adobe 应用生成的缓存或媒体临时数据，通常可以重建，但可能影响正在进行的渲染和离线工作。",
            recommendedAction: "退出相关 Adobe 应用，并优先使用应用内的媒体缓存管理功能。",
            reclaimability: .candidate
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/caches/adobe")
        },
        FindingRule(
            identifier: "figma.application-data",
            sourceApplication: "Figma",
            category: .appManaged,
            risk: .medium,
            confidence: .high,
            explanation: "Figma 的本地数据可能包含应用组件、离线状态、插件和缓存，云端文件与本地内容不能仅凭目录名区分。",
            recommendedAction: "优先在 Figma 中管理离线文件和插件，确认同步完成后再处理本地占用。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            (path.hasSuffix("/library/application support/figma") ||
            path.hasSuffix("/library/caches/figma")
            )
        },
        FindingRule(
            identifier: "video-production-data",
            sourceApplication: "专业视频应用",
            category: .appManaged,
            risk: .high,
            confidence: .medium,
            explanation: "这里可能包含媒体缓存、代理文件、渲染文件、插件或项目数据库。部分内容可重建，部分内容可能是唯一项目数据。",
            recommendedAction: "从 Final Cut Pro、DaVinci Resolve 或对应视频应用内部管理媒体与缓存，处理前确认项目备份。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            (path.hasSuffix("/library/application support/blackmagic design") ||
            path.hasSuffix("/library/application support/proapps")
            )
        },
        FindingRule(
            identifier: "media.library-bundle",
            sourceApplication: "照片、音乐或视频应用",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "这是媒体资料库包，可能包含原始照片、视频、音乐、编辑记录和数据库。资料库包不能当作普通缓存。",
            recommendedAction: "在对应的照片、音乐、Final Cut Pro 或 iMovie 应用中管理，并在处理前确认已有可靠备份。",
            reclaimability: .notEstimated
        ) { path in
            path.hasSuffix(".photoslibrary") ||
            path.hasSuffix(".musiclibrary") ||
            path.hasSuffix(".fcpbundle") ||
            path.hasSuffix(".imovielibrary")
        },
        FindingRule(
            identifier: "cloud-storage",
            sourceApplication: "云盘与 iCloud",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "这里可能包含云端文件、本地副本和按需下载占位符。allocated size 与云端总大小可能不同，直接删除还可能同步到其他设备。",
            recommendedAction: "使用 Finder 的“移除下载项”或对应云盘应用管理本地副本，不要把同步目录当作缓存删除。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            (path.hasSuffix("/library/cloudstorage") ||
            path.hasSuffix("/library/mobile documents")
            )
        },
        FindingRule(
            identifier: "steam.library",
            sourceApplication: "Steam",
            category: .appManaged,
            risk: .medium,
            confidence: .high,
            explanation: "Steam 数据可能包含已安装游戏、创意工坊内容、下载缓存和游戏状态。",
            recommendedAction: "通过 Steam 的“存储空间”管理游戏和库目录，避免直接删除清单或存档。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            path.hasSuffix("/library/application support/steam")
        },
        FindingRule(
            identifier: "user.container-data",
            sourceApplication: "macOS App Sandbox",
            category: .userData,
            risk: .high,
            confidence: .high,
            explanation: "这是某个沙盒应用的独立容器或数据目录，可能包含设置、数据库、文档和账号状态，不能按普通缓存处理。",
            recommendedAction: "根据容器中的 bundle identifier 确认所属应用，并优先在应用内部管理。",
            reclaimability: .notEstimated
        ) { path in
            Self.isContainerRootOrDataPath(path)
        },
        FindingRule(
            identifier: "user.containers-root",
            sourceApplication: "macOS App Sandbox",
            category: .appManaged,
            risk: .high,
            confidence: .high,
            explanation: "Containers 汇总沙盒应用的独立数据目录，其中既有缓存，也可能有文档、消息数据库和应用状态。",
            recommendedAction: "不要整体清理。请查看具体 bundle identifier，并在对应应用中管理。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            (path.hasSuffix("/library/containers") ||
                path.hasSuffix("/library/group containers"))
        },
        FindingRule(
            identifier: "user.application-support",
            sourceApplication: "已安装应用",
            category: .appManaged,
            risk: .high,
            confidence: .high,
            explanation: "Application Support 保存应用运行所需的数据，可能包括数据库、模型、插件、账号状态和用户内容，并不等同于缓存。",
            recommendedAction: "继续查看下一级应用或厂商目录，并优先使用对应应用的存储管理功能。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) &&
            Self.isExactOrDirectChild(path, of: "/library/application support")
        },
        FindingRule(
            identifier: "user.library-root",
            sourceApplication: "macOS 与已安装应用",
            category: .appManaged,
            risk: .high,
            confidence: .high,
            explanation: "个人 Library 保存应用支持文件、沙盒容器、邮件、浏览器资料、缓存和系统偏好，其中许多内容不可自动恢复。",
            recommendedAction: "不要整体清理。请继续查看已经识别出的 Application Support、Containers、Caches 等具体区域。",
            reclaimability: .notEstimated
        ) { path in
            Self.isUserHomeLibraryPath(path) && path.hasSuffix("/library")
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
            (Self.isUserHomeLibraryPath(path) || path.hasPrefix("/library/")) &&
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

    private static func isContainerRootOrDataPath(_ path: String) -> Bool {
        guard isUserHomeLibraryPath(path),
              let range = path.range(of: "/library/containers/") else {
            return false
        }
        let remainder = path[range.upperBound...]
        let components = remainder.split(separator: "/")
        guard !components.isEmpty, components.count <= 3 else { return false }
        if components.count == 1 { return true }
        guard components[1] == "data" else { return false }
        return components.count == 2 || components[2] == "documents"
    }

    private static func isUserHomeLibraryPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return components.count >= 3 &&
            components[0] == "users" &&
            components[2] == "library"
    }
}
