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
    @Published var errorMessage: String?
    @Published var sortMode: FindingSort = .size {
        didSet { scheduleSort() }
    }
    @Published private(set) var displayedFindings: [Finding] = []
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
        case size = "占用"
        case category = "类别"
        case risk = "风险"
        var id: String { rawValue }
    }

    nonisolated private static func sort(
        _ findings: [Finding],
        by mode: FindingSort
    ) -> [Finding] {
        findings.sorted {
            switch mode {
            case .size:
                return $0.allocatedBytes > $1.allocatedBytes
            case .category:
                if $0.category.rawValue == $1.category.rawValue {
                    return $0.allocatedBytes > $1.allocatedBytes
                }
                return $0.category.rawValue < $1.category.rawValue
            case .risk:
                if $0.risk.rank == $1.risk.rank {
                    return $0.allocatedBytes > $1.allocatedBytes
                }
                return $0.risk.rank > $1.risk.rank
            }
        }
    }

    func chooseAndScan() {
        let panel = NSOpenPanel()
        panel.title = "选择要只读扫描的目录"
        panel.message = "Mac Disk Inspector 只读取元数据和目录结构，不会修改文件。"
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
            alert.informativeText = "大型磁盘可能包含数百万个文件。建议先扫描用户目录；继续全盘扫描时可以随时取消。"
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
        recommendationFindings = []
        scanSamples = []
        errorMessage = nil
        statusMessage = nil
        selectedFinding = nil
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
                self.scheduleSort()
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
                errorMessage = "未找到目标 App。"
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .copyInspectionCommand, .copyOfficialCleanupCommand:
            guard let value = action.value else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            statusMessage = action.kind == .copyOfficialCleanupCommand
                ? "清理命令已复制。本 App 没有执行它。"
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

    private func scheduleSort() {
        sortTask?.cancel()
        let allFindings = report?.findings ?? []
        let nonEmptyFindings = allFindings.filter { $0.allocatedBytes > 0 }
        let findingsWithoutRoot = nonEmptyFindings.filter { $0.path != report?.rootPath }
        let findings = findingsWithoutRoot.isEmpty ? nonEmptyFindings : findingsWithoutRoot
        guard !findings.isEmpty else {
            displayedFindings = []
            recommendationFindings = []
            isSorting = false
            return
        }
        let mode = sortMode
        sortGeneration = UUID()
        let generation = sortGeneration
        isSorting = true
        sortTask = Task { [weak self] in
            let sorted = await Task.detached(priority: .userInitiated) {
                Self.sort(findings, by: mode)
            }.value
            guard let self, !Task.isCancelled, self.sortGeneration == generation else { return }
            self.displayedFindings = sorted
            self.recommendationFindings = Self.nonOverlappingRecommendations(from: sorted)
            self.isSorting = false
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
