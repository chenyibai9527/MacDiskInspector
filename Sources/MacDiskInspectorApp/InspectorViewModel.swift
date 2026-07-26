import AppKit
import Darwin
import DiskInspectorCore
import Foundation

@MainActor
final class InspectorViewModel: ObservableObject {
    enum ProtectedDirectory: String, CaseIterable, Identifiable, Sendable {
        case desktop
        case documents
        case downloads
        case pictures
        case music
        case movies
        case mail
        case messages
        case safari
        case otherAppData

        var id: String { rawValue }

        var title: String {
            switch self {
            case .desktop: "桌面"
            case .documents: "文稿"
            case .downloads: "下载"
            case .pictures: "图片与照片图库"
            case .music: "音乐"
            case .movies: "影片"
            case .mail: "邮件数据"
            case .messages: "信息数据"
            case .safari: "Safari 数据"
            case .otherAppData: "其他 App 数据"
            }
        }

        var relativePaths: [String] {
            switch self {
            case .desktop: ["Desktop"]
            case .documents: ["Documents"]
            case .downloads: ["Downloads"]
            case .pictures: ["Pictures"]
            case .music: ["Music"]
            case .movies: ["Movies"]
            case .mail: ["Library/Mail"]
            case .messages: ["Library/Messages"]
            case .safari: ["Library/Safari"]
            case .otherAppData: ["Library/Containers", "Library/Group Containers"]
            }
        }

        var displayPath: String {
            relativePaths.map { "~/\($0)" }.joined(separator: "、")
        }

        var systemImage: String {
            switch self {
            case .desktop: "menubar.dock.rectangle"
            case .documents: "doc"
            case .downloads: "arrow.down.circle"
            case .pictures: "photo.on.rectangle"
            case .music: "music.note"
            case .movies: "film"
            case .mail: "envelope"
            case .messages: "message"
            case .safari: "safari"
            case .otherAppData: "app.badge"
            }
        }

        var privacyExplanation: String {
            if self == .otherAppData {
                return "默认不会进入其他 App 的容器。开启后，扫描到微信等应用数据时，macOS 可能询问是否允许访问。"
            }
            return "\(displayPath) 默认不会进入。开启后，扫描到这里时 macOS 仍可能询问访问权限。"
        }

        func urls(homeDirectory: URL) -> [URL] {
            relativePaths.map { relativePath in
                relativePath
                    .split(separator: "/")
                    .reduce(homeDirectory) { partial, component in
                        partial.appendingPathComponent(String(component), isDirectory: true)
                    }
                    .standardizedFileURL
                }
        }
    }

    struct FindingGroup: Identifiable, Sendable {
        let id: String
        let title: String
        let findings: [Finding]
    }

    enum Section: String, CaseIterable, Identifiable {
        case overview = "磁盘概览"
        case findings = "占用排行"
        case recommendations = "建议中心"
        case issues = "访问问题"
        case guide = "使用说明"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .overview: "internaldrive"
            case .findings: "list.bullet.rectangle"
            case .recommendations: "checklist"
            case .issues: "exclamationmark.shield"
            case .guide: "book.closed"
            }
        }
    }

    @Published var selectedSection: Section? = .overview
    @Published var selectedFinding: Finding?
    @Published var report: ScanReport?
    @Published var capacity: VolumeCapacity?
    @Published var progress: ScanProgress?
    @Published var isScanning = false
    @Published private(set) var scanRootPath: String?
    @Published var errorMessage: String?
    @Published var sortMode: FindingSort {
        didSet {
            defaults.set(sortMode.rawValue, forKey: PreferenceKey.defaultFindingSort)
            scheduleSort()
        }
    }
    @Published var showZeroByteFindings: Bool {
        didSet {
            defaults.set(showZeroByteFindings, forKey: PreferenceKey.showZeroByteFindings)
            scheduleSort()
        }
    }
    @Published var enabledProtectedDirectories: Set<ProtectedDirectory> {
        didSet {
            defaults.set(
                enabledProtectedDirectories.map(\.rawValue).sorted(),
                forKey: PreferenceKey.enabledProtectedDirectories
            )
        }
    }
    @Published private(set) var displayedFindings: [Finding] = []
    @Published private(set) var findingGroups: [FindingGroup] = []
    @Published private(set) var recommendationFindings: [Finding] = []
    @Published private(set) var scanSamples: [ScanTrendPoint] = ScanTrendSeries().points
    @Published private(set) var isSorting = false
    @Published var statusMessage: String?

    private enum PreferenceKey {
        static let defaultFindingSort = "defaultFindingSort"
        static let showZeroByteFindings = "showZeroByteFindings"
        static let enabledProtectedDirectories = "enabledProtectedDirectories"
    }

    private let defaults: UserDefaults
    private let scanner = DirectoryScanner()
    private let volumeReader = VolumeReader()
    private var scanTask: Task<Void, Never>?
    private var sortTask: Task<Void, Never>?
    private var scanGeneration = UUID()
    private var sortGeneration = UUID()
    private var scanTrendSeries = ScanTrendSeries()
    private var lastScanURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sortMode = defaults.string(forKey: PreferenceKey.defaultFindingSort)
            .flatMap(FindingSort.init(rawValue:)) ?? .size
        self.showZeroByteFindings = defaults.bool(forKey: PreferenceKey.showZeroByteFindings)
        let storedProtectedDirectories = defaults.stringArray(
            forKey: PreferenceKey.enabledProtectedDirectories
        ) ?? []
        self.enabledProtectedDirectories = Set(
            storedProtectedDirectories.compactMap(ProtectedDirectory.init(rawValue:))
        )
    }

    enum FindingSort: String, CaseIterable, Identifiable, Sendable {
        case size = "大小"
        case category = "类型"
        case risk = "风险"
        var id: String { rawValue }

        var explanation: String {
            switch self {
            case .size: "按占用空间从大到小排列"
            case .category: "按数据类型分组，每组内从大到小排列"
            case .risk: "按风险高低分组，每组内从大到小排列"
            }
        }

        nonisolated var coreMode: FindingSortMode {
            switch self {
            case .size: .size
            case .category: .category
            case .risk: .risk
            }
        }
    }

    nonisolated private static func sort(
        _ findings: [Finding],
        by mode: FindingSort
    ) -> [Finding] {
        FindingSorter().sort(findings, by: mode.coreMode)
    }

    func chooseAndScan() {
        let panel = NSOpenPanel()
        panel.title = "选择要只读扫描的目录"
        panel.message = "Mac 磁盘扫描助手只读取文件大小、日期和目录结构，不会修改任何文件。"
        panel.prompt = "开始只读扫描"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let temporarilyAllowed = temporaryProtectedAccess(for: url) else { return }
        if isVolumeRoot(url) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "全盘扫描可能需要较长时间"
            alert.informativeText = "整块磁盘可能包含数百万个文件，扫描时间会很长。建议先从个人文件夹开始；如果继续，你仍可随时取消。"
            alert.addButton(withTitle: "继续全盘扫描")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        startScan(url: url, temporarilyAllowed: temporarilyAllowed)
    }

    func startScan(
        url: URL,
        temporarilyAllowed: Set<ProtectedDirectory> = []
    ) {
        scanTask?.cancel()
        scanGeneration = UUID()
        let generation = scanGeneration
        report = nil
        progress = nil
        displayedFindings = []
        findingGroups = []
        recommendationFindings = []
        scanTrendSeries = ScanTrendSeries()
        scanSamples = scanTrendSeries.points
        errorMessage = nil
        statusMessage = nil
        selectedFinding = nil
        scanRootPath = url.standardizedFileURL.path
        lastScanURL = url
        isScanning = true
        selectedSection = .overview

        do {
            capacity = try volumeReader.capacity(for: url)
        } catch {
            capacity = nil
        }

        let fullVolume = isVolumeRoot(url)
        let allowedProtectedDirectories = enabledProtectedDirectories.union(temporarilyAllowed)
        let loginHomeDirectory = Self.loginHomeDirectory()
        let homeDirectories = fullVolume
            ? Self.localUserHomeDirectories()
            : [loginHomeDirectory]
        let excludedDirectories = Self.protectedDirectoryExclusions(
            homeDirectories: homeDirectories,
            loginHomeDirectory: loginHomeDirectory,
            allowedForLoginAccount: allowedProtectedDirectories
        )
        let configuration = ScanConfiguration(
            aggregationDepth: fullVolume ? 2 : 3,
            stayOnSelectedVolume: true,
            deduplicateHardLinks: true,
            progressInterval: fullVolume ? 1_000 : 400,
            excludedDirectories: excludedDirectories,
            returnPartialResultsOnCancellation: true
        )

        scanTask = Task { [weak self] in
            guard let self else { return }
            let didStartSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if didStartSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let scanReport = try await scanner.scan(
                    rootURL: url,
                    configuration: configuration
                ) { update in
                    Task { @MainActor [weak self] in
                        guard let self, self.scanGeneration == generation else { return }
                        self.progress = update
                        self.appendSample(update)
                    }
                }
                guard scanGeneration == generation else { return }
                self.report = scanReport
                self.selectedFinding = scanReport.findings.first
                self.isScanning = false
                if scanReport.isPartial {
                    self.statusMessage = "扫描已停止，正在显示已经完成的部分。"
                }
                self.scheduleSort(refreshRecommendations: true)
            } catch is CancellationError {
                if scanGeneration == generation {
                    self.isScanning = false
                }
            } catch {
                if scanGeneration == generation {
                    self.errorMessage = error.localizedDescription
                    self.isScanning = false
                }
            }
        }
    }

    func restoreDefaultPreferences() {
        sortMode = .size
        showZeroByteFindings = false
        enabledProtectedDirectories = []
    }

    var canRescanLastLocation: Bool {
        !isScanning && lastScanURL != nil
    }

    func rescanLastLocation() {
        guard let lastScanURL, !isScanning else { return }
        guard let temporarilyAllowed = temporaryProtectedAccess(for: lastScanURL) else { return }
        startScan(url: lastScanURL, temporarilyAllowed: temporarilyAllowed)
    }

    func isProtectedDirectoryEnabled(_ directory: ProtectedDirectory) -> Bool {
        enabledProtectedDirectories.contains(directory)
    }

    func setProtectedDirectory(_ directory: ProtectedDirectory, enabled: Bool) {
        if enabled {
            enabledProtectedDirectories.insert(directory)
        } else {
            enabledProtectedDirectories.remove(directory)
        }
    }

    func requestCancelScan() {
        guard isScanning else { return }
        let stoppedProgress = progress
        scanTask?.cancel()

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "要保留已经扫描的结果吗？"
        if let stoppedProgress {
            alert.informativeText = "扫描已经停止。目前已查看 \(stoppedProgress.entriesVisited.formatted()) 项，统计到 \(stoppedProgress.allocatedBytesMeasured.formattedBytes)。你可以查看这部分结果，也可以放弃本次扫描。"
        } else {
            alert.informativeText = "扫描已经停止。你可以查看目前已经完成的部分，也可以放弃本次扫描。"
        }
        alert.addButton(withTitle: "查看当前结果")
        alert.addButton(withTitle: "放弃结果")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            break
        default:
            discardCurrentScan()
        }
    }

    private func discardCurrentScan() {
        scanGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
        report = nil
        displayedFindings = []
        findingGroups = []
        recommendationFindings = []
        progress = nil
        isScanning = false
    }

    func perform(_ action: SuggestedAction, for finding: Finding) {
        switch action.kind {
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: finding.path)])
        case .openApplication:
            guard let bundleID = action.value,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                errorMessage = "没有找到相关应用。"
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .copyInspectionCommand, .copyOfficialCleanupCommand:
            guard let value = action.value else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            statusMessage = action.kind == .copyOfficialCleanupCommand
                ? "清理命令已复制。Mac 磁盘扫描助手没有运行这条命令。"
                : "检查命令已复制。"
        case .deferAction:
            selectedFinding = nil
        }
    }

    private func appendSample(_ update: ScanProgress) {
        scanTrendSeries.append(
            entries: update.entriesVisited,
            allocatedBytes: update.allocatedBytesMeasured
        )
        scanSamples = scanTrendSeries.points
    }

    private func scheduleSort(refreshRecommendations: Bool = false) {
        sortTask?.cancel()
        let allFindings = report?.findings ?? []
        let visibleFindings = showZeroByteFindings
            ? allFindings
            : allFindings.filter { $0.allocatedBytes > 0 }
        let findingsWithoutRoot = visibleFindings.filter { $0.path != report?.rootPath }
        let findings = findingsWithoutRoot.isEmpty ? visibleFindings : findingsWithoutRoot
        guard !findings.isEmpty else {
            displayedFindings = []
            findingGroups = []
            recommendationFindings = []
            isSorting = false
            return
        }
        let mode = sortMode
        sortGeneration = UUID()
        let generation = sortGeneration
        isSorting = true
        sortTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                let sorted = Self.sort(findings, by: mode)
                let groups = Self.groups(from: sorted, mode: mode)
                let recommendations = refreshRecommendations
                    ? Self.nonOverlappingRecommendations(from: findings)
                    : nil
                return (sorted, groups, recommendations)
            }.value
            guard let self, !Task.isCancelled, self.sortGeneration == generation else { return }
            self.displayedFindings = result.0
            self.findingGroups = result.1
            if self.selectedFinding.map({ selected in
                result.0.contains(where: { $0.id == selected.id })
            }) != true {
                self.selectedFinding = result.0.first
            }
            if let recommendations = result.2 {
                self.recommendationFindings = recommendations
            }
            self.isSorting = false
        }
    }

    nonisolated private static func groups(
        from findings: [Finding],
        mode: FindingSort
    ) -> [FindingGroup] {
        guard !findings.isEmpty else { return [] }
        if mode == .size {
            return [FindingGroup(id: "size", title: "从大到小", findings: findings)]
        }

        var orderedTitles: [String] = []
        var buckets: [String: [Finding]] = [:]
        for finding in findings {
            let title = mode == .category ? finding.category.rawValue : finding.risk.rawValue
            if buckets[title] == nil {
                orderedTitles.append(title)
            }
            buckets[title, default: []].append(finding)
        }
        return orderedTitles.map { title in
            FindingGroup(
                id: "\(mode.rawValue).\(title)",
                title: title,
                findings: buckets[title] ?? []
            )
        }
    }

    nonisolated private static func nonOverlappingRecommendations(
        from findings: [Finding]
    ) -> [Finding] {
        let candidates = findings
            .filter { ($0.potentialReclaimableBytes ?? 0) > 0 }
            .sorted {
                let leftDepth = URL(fileURLWithPath: $0.path).pathComponents.count
                let rightDepth = URL(fileURLWithPath: $1.path).pathComponents.count
                if leftDepth == rightDepth {
                    return $0.allocatedBytes > $1.allocatedBytes
                }
                return leftDepth < rightDepth
            }
        var selected: [Finding] = []
        for finding in candidates {
            let path = URL(fileURLWithPath: finding.path).standardizedFileURL.path
            let alreadyCovered = selected.contains { existing in
                guard existing.ruleIdentifier == finding.ruleIdentifier else { return false }
                let ancestor = URL(fileURLWithPath: existing.path).standardizedFileURL.path
                return path == ancestor || path.hasPrefix(ancestor + "/")
            }
            if !alreadyCovered {
                selected.append(finding)
            }
        }
        return selected
    }

    private func isVolumeRoot(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.volumeURLKey]),
              let volumeURL = values.volume else {
            return url.standardizedFileURL.path == "/"
        }
        return volumeURL.standardizedFileURL.path == url.standardizedFileURL.path
    }

    private func protectedDirectory(containing url: URL) -> ProtectedDirectory? {
        let path = privacyComparisonPath(url.path)
        let homeDirectory = Self.loginHomeDirectory()
        return ProtectedDirectory.allCases.first { directory in
            directory.urls(homeDirectory: homeDirectory).contains { protectedURL in
                let protectedPath = privacyComparisonPath(protectedURL.path)
                return path == protectedPath || path.hasPrefix(protectedPath + "/")
            }
        }
    }

    private func temporaryProtectedAccess(
        for url: URL
    ) -> Set<ProtectedDirectory>? {
        guard let protectedDirectory = protectedDirectory(containing: url),
              !enabledProtectedDirectories.contains(protectedDirectory) else {
            return []
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "这个目录默认不会扫描"
        alert.informativeText = "“\(protectedDirectory.title)”属于受保护范围。继续只对本次扫描放行；macOS 仍可能显示系统权限提示。"
        alert.addButton(withTitle: "只扫描这一次")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return [protectedDirectory]
    }

    private func privacyComparisonPath(_ rawPath: String) -> String {
        let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let dataVolumePrefix = "/System/Volumes/Data"
        if path == dataVolumePrefix {
            return "/"
        }
        if path.hasPrefix(dataVolumePrefix + "/") {
            return String(path.dropFirst(dataVolumePrefix.count))
        }
        return path
    }

    nonisolated static func loginHomeDirectory() -> URL {
        if let record = getpwuid(getuid()),
           let homePath = record.pointee.pw_dir {
            return URL(
                fileURLWithPath: String(cString: homePath),
                isDirectory: true
            )
            .standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    nonisolated static func localUserHomeDirectories() -> [URL] {
        var paths = Set([loginHomeDirectory().standardizedFileURL.path])

        setpwent()
        defer { endpwent() }
        while let record = getpwent(), let homePath = record.pointee.pw_dir {
            let path = URL(
                fileURLWithPath: String(cString: homePath),
                isDirectory: true
            ).standardizedFileURL.path
            if path.hasPrefix("/Users/"), path != "/Users/Shared" {
                paths.insert(path)
            }
        }

        return paths.sorted().map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    nonisolated static func protectedDirectoryExclusions(
        homeDirectories: [URL],
        loginHomeDirectory: URL,
        allowedForLoginAccount: Set<ProtectedDirectory>
    ) -> [ScanExcludedDirectory] {
        let loginPath = loginHomeDirectory.standardizedFileURL.path
        return homeDirectories.flatMap { homeDirectory in
            let isLoginAccount = homeDirectory.standardizedFileURL.path == loginPath
            return ProtectedDirectory.allCases
                .filter { !isLoginAccount || !allowedForLoginAccount.contains($0) }
                .flatMap { directory in
                    directory.urls(homeDirectory: homeDirectory).map { url in
                        let reason = isLoginAccount
                            ? "为避免意外触发敏感权限，“\(directory.title)”已按你的设置跳过。可在“设置 > 受保护目录”中选择是否扫描。"
                            : "为避免越过其他用户的隐私边界，已跳过该账户的“\(directory.title)”。"
                        return ScanExcludedDirectory(path: url.path, reason: reason)
                    }
                }
        }
    }
}
