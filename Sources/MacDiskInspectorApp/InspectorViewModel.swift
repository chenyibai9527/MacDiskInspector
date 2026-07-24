import AppKit
import DiskInspectorCore
import Foundation

@MainActor
final class InspectorViewModel: ObservableObject {
    struct ScanSample: Identifiable, Sendable {
        let id = UUID()
        let entries: Int
        let allocatedBytes: Int64
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
    @Published var sortMode: FindingSort = .size {
        didSet { scheduleSort() }
    }
    @Published private(set) var displayedFindings: [Finding] = []
    @Published private(set) var findingGroups: [FindingGroup] = []
    @Published private(set) var recommendationFindings: [Finding] = []
    @Published private(set) var scanSamples: [ScanSample] = []
    @Published private(set) var isSorting = false
    @Published var statusMessage: String?

    private let scanner = DirectoryScanner()
    private let volumeReader = VolumeReader()
    private var scanTask: Task<Void, Never>?
    private var sortTask: Task<Void, Never>?
    private var scanGeneration = UUID()
    private var sortGeneration = UUID()

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
        panel.message = "Mac Disk Inspector 只读取文件大小、日期和目录结构，不会修改任何文件。"
        panel.prompt = "开始只读扫描"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isVolumeRoot(url) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "全盘扫描可能需要较长时间"
            alert.informativeText = "整块磁盘可能包含数百万个文件，扫描时间会很长。建议先从个人文件夹开始；如果继续，你仍可随时取消。"
            alert.addButton(withTitle: "继续全盘扫描")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        startScan(url: url)
    }

    func startScan(url: URL) {
        scanTask?.cancel()
        scanGeneration = UUID()
        let generation = scanGeneration
        report = nil
        progress = nil
        displayedFindings = []
        findingGroups = []
        recommendationFindings = []
        scanSamples = []
        errorMessage = nil
        statusMessage = nil
        selectedFinding = nil
        scanRootPath = url.standardizedFileURL.path
        isScanning = true
        selectedSection = .overview

        do {
            capacity = try volumeReader.capacity(for: url)
        } catch {
            capacity = nil
        }

        let fullVolume = isVolumeRoot(url)
        let configuration = ScanConfiguration(
            aggregationDepth: fullVolume ? 2 : 3,
            stayOnSelectedVolume: true,
            deduplicateHardLinks: true,
            progressInterval: fullVolume ? 1_000 : 400
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
                guard !Task.isCancelled, scanGeneration == generation else { return }
                self.report = scanReport
                self.selectedFinding = scanReport.findings.first
                self.isScanning = false
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

    func cancelScan() {
        scanGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
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
                ? "清理命令已复制。Mac Disk Inspector 没有运行这条命令。"
                : "检查命令已复制。"
        case .deferAction:
            selectedFinding = nil
        }
    }

    private func appendSample(_ update: ScanProgress) {
        scanSamples.append(
            ScanSample(entries: update.entriesVisited, allocatedBytes: update.allocatedBytesMeasured)
        )
        if scanSamples.count > 80 {
            scanSamples.removeFirst(scanSamples.count - 80)
        }
    }

    private func scheduleSort(refreshRecommendations: Bool = false) {
        sortTask?.cancel()
        let allFindings = report?.findings ?? []
        let nonEmptyFindings = allFindings.filter { $0.allocatedBytes > 0 }
        let findingsWithoutRoot = nonEmptyFindings.filter { $0.path != report?.rootPath }
        let findings = findingsWithoutRoot.isEmpty ? nonEmptyFindings : findingsWithoutRoot
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
}
