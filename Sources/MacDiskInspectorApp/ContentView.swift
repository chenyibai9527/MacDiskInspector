import DiskInspectorCore
import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: InspectorViewModel

    var body: some View {
        NavigationSplitView {
            List(InspectorViewModel.Section.allCases, selection: $model.selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Disk Inspector")
            .safeAreaInset(edge: .bottom) {
                privacyFooter
            }
        } detail: {
            Group {
                switch model.selectedSection ?? .overview {
                case .overview:
                    OverviewView()
                case .findings:
                    FindingsView()
                case .recommendations:
                    RecommendationsView()
                case .issues:
                    IssuesView()
                case .guide:
                    GuideView()
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    if model.isScanning {
                        Button("取消", role: .cancel) {
                            model.cancelScan()
                        }
                    }
                    Button {
                        model.chooseAndScan()
                    } label: {
                        Label("选择目录", systemImage: "folder.badge.plus")
                    }
                    .disabled(model.isScanning)
                }
            }
        }
        .alert("无法完成扫描", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let message = model.statusMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(message)
                    Button {
                        model.statusMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭提示")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .adaptiveStatusGlass()
                .shadow(radius: 12, y: 4)
                .padding(.bottom, 18)
            }
        }
    }

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("只在本机分析", systemImage: "lock.shield")
                .font(.headline)
            Text("不删除、移动或上传")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var model: InspectorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "磁盘概览",
                    subtitle: "先看清空间去了哪里，再决定要不要处理。扫描过程中只读取文件信息。"
                )

                if let capacity = model.capacity {
                    capacityCard(capacity)
                }

                if model.isScanning, let progress = model.progress {
                    scanningCard(progress)
                } else if let report = model.report {
                    summaryGrid(report)
                    UsageVisualization(report: report)
                    coverageCard(report)
                } else {
                    emptyState
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func capacityCard(_ capacity: VolumeCapacity) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(capacity.name, systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text("\(capacity.availableBytes.formattedBytes) 可用")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(capacity.usedBytes), total: Double(max(1, capacity.totalBytes)))
                .tint(.accentColor)
            HStack {
                Text("\(capacity.usedBytes.formattedBytes) 已使用")
                Spacer()
                Text("总容量 \(capacity.totalBytes.formattedBytes)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let important = capacity.availableForImportantUsageBytes,
               important > capacity.availableBytes {
                Text("macOS 估计，在系统自行回收部分空间后，重要任务最多可使用约 \(important.formattedBytes)。这不是现在的可用空间。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .inspectorCard()
    }

    private func scanningCard(_ progress: ScanProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("正在只读扫描")
                .font(.headline)
            Text(progress.currentPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 34, alignment: .topLeading)
            Text("已查看 \(progress.entriesVisited.formatted()) 项 · 已统计 \(progress.allocatedBytesMeasured.formattedBytes)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.scanSamples.count > 1 {
                Chart(model.scanSamples) { sample in
                    AreaMark(
                        x: .value("文件项", sample.entries),
                        y: .value("已计量空间", sample.allocatedBytes)
                    )
                    .foregroundStyle(.tint.opacity(0.12))
                    LineMark(
                        x: .value("文件项", sample.entries),
                        y: .value("已计量空间", sample.allocatedBytes)
                    )
                    .foregroundStyle(.tint)
                    .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 64)
                .accessibilityLabel("扫描进度趋势")
            }
        }
        .inspectorCard()
        .frame(maxWidth: .infinity)
    }

    private func summaryGrid(_ report: ScanReport) -> some View {
        HStack(spacing: 14) {
            MetricCard(title: "已分配空间", value: report.totalAllocatedBytes.formattedBytes, systemImage: "square.stack.3d.up")
            MetricCard(title: "唯一文件", value: report.uniqueFiles.formatted(), systemImage: "doc.on.doc")
            MetricCard(title: "分析结果", value: report.findings.count.formatted(), systemImage: "list.bullet")
            MetricCard(title: "访问问题", value: report.totalIssueCount.formatted(), systemImage: "exclamationmark.triangle")
        }
    }

    private func coverageCard(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本次扫描是否完整")
                    .font(.headline)
                Spacer()
                Label(
                    report.hasCoverageGaps ? "有内容未能读取" : "未发现读取错误",
                    systemImage: report.hasCoverageGaps
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .foregroundStyle(report.hasCoverageGaps ? .orange : .green)
            }
            Text(report.hasCoverageGaps
                ? "有 \(report.inaccessibleIssueCount.formatted()) 个目录或文件未能读取。无法知道这些目录里还有多少内容，因此这里不显示容易误导的百分比。"
                : "扫描时没有遇到权限或目录读取错误。主动跳过的符号链接、其他磁盘和特殊文件仍会列在“访问问题”中。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !report.issues.isEmpty {
                Button("查看问题 \(report.totalIssueCount.formatted()) 项") {
                    model.selectedSection = .issues
                }
                .adaptiveGlassButtonStyle()
            }
        }
        .inspectorCard()
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            title: "尚未扫描目录",
            systemImage: "folder.badge.questionmark",
            description: "选择一个目录后，所有分析都在这台 Mac 上完成，不会改动其中的文件。"
        ) {
            Button("选择目录并扫描…") {
                model.chooseAndScan()
            }
            .adaptiveProminentGlassButtonStyle()
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

private struct FindingsView: View {
    @EnvironmentObject private var model: InspectorViewModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("占用排行")
                        .font(.title2.bold())
                    Spacer()
                    AdaptiveFindingSortPicker(selection: $model.sortMode)
                    .frame(width: 230)
                }
                .padding()

                VStack(alignment: .leading, spacing: 4) {
                    Label(model.sortMode.explanation, systemImage: "arrow.up.arrow.down")
                    Text("已隐藏占用为零的项目和最外层目录汇总。文件夹大小包含其中的下级内容。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 10)

                Divider()

                if model.displayedFindings.isEmpty {
                    EmptyStateView(
                        title: "没有扫描结果",
                        systemImage: "list.bullet.rectangle",
                        description: "先选择目录开始只读扫描。"
                    )
                } else {
                    List(selection: $model.selectedFinding) {
                        ForEach(model.findingGroups) { group in
                            Section(group.title) {
                                ForEach(group.findings) { finding in
                                    FindingRow(finding: finding)
                                        .tag(finding)
                                }
                            }
                        }
                    }
                    .overlay {
                        if model.isSorting {
                            ProgressView("正在排序…")
                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .frame(minWidth: 420)

            Group {
                if let finding = model.selectedFinding {
                    FindingDetailView(finding: finding)
                } else {
                    EmptyStateView(
                        title: "选择一项查看详情",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .frame(minWidth: 380)
        }
    }
}

private struct FindingRow: View {
    let finding: Finding

    var body: some View {
        HStack(spacing: 12) {
            RiskDot(risk: finding.risk)
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: finding.path).lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(finding.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(finding.allocatedBytes.formattedBytes)
                    .monospacedDigit()
                Text("\(finding.fileCount.formatted()) 个文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct FindingDetailView: View {
    @EnvironmentObject private var model: InspectorViewModel
    let finding: Finding
    private let advisor = ActionAdvisor()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        RiskBadge(risk: finding.risk)
                        Text(finding.category.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    Text(URL(fileURLWithPath: finding.path).lastPathComponent)
                        .font(.title2.bold())
                    Text(finding.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Divider()
                detailGrid
                DetailSection(title: "这是什么", text: finding.explanation)
                DetailSection(title: "可以怎么做", text: finding.recommendedAction)

                VStack(alignment: .leading, spacing: 10) {
                    Text("你可以这样做")
                        .font(.headline)
                    ForEach(advisor.actions(for: finding)) { action in
                        Button {
                            model.perform(action, for: finding)
                        } label: {
                            HStack {
                                Text(action.title)
                                Spacer()
                                if action.isDestructive {
                                    Text("仅复制，不执行")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .adaptiveGlassButtonStyle()
                    }
                }
            }
            .padding(24)
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            detailRow("已分配", finding.allocatedBytes.formattedBytes)
            detailRow("逻辑大小", finding.logicalBytes.formattedBytes)
            detailRow("文件数量", finding.fileCount.formatted())
            detailRow("来源应用", finding.sourceApplication ?? "未知")
            detailRow("判断把握", finding.confidence.rawValue)
            detailRow(
                "可能可释放",
                finding.potentialReclaimableBytes?.formattedBytes ?? "暂不估算"
            )
            if let date = finding.lastModified {
                detailRow("最近修改", date.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct RecommendationsView: View {
    @EnvironmentObject private var model: InspectorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "建议中心",
                    subtitle: "这里只列出值得进一步核对的内容。是否处理、如何处理，都由你决定。"
                )

                ForEach(model.recommendationFindings) { finding in
                    HStack(alignment: .top, spacing: 14) {
                        RiskDot(risk: finding.risk)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(URL(fileURLWithPath: finding.path).lastPathComponent)
                                .font(.headline)
                            Text(finding.recommendedAction)
                                .foregroundStyle(.secondary)
                            Text("可能可释放 \(finding.potentialReclaimableBytes?.formattedBytes ?? "待确认") · 实际结果可能更少")
                                .font(.caption)
                        }
                        Spacer()
                        Button("查看证据") {
                            model.selectedFinding = finding
                            model.selectedSection = .findings
                        }
                        .adaptiveGlassButtonStyle()
                    }
                    .inspectorCard()
                    .frame(maxWidth: .infinity)
                }

                if model.recommendationFindings.isEmpty {
                    EmptyStateView(
                        title: "暂时没有可操作的建议",
                        systemImage: "checkmark.shield",
                        description: "用途不明或风险较高的数据不会计入“可能可释放”。"
                    )
                        .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct UsageVisualization: View {
    private struct Item: Identifiable {
        let id: String
        let name: String
        let allocatedBytes: Int64
        let risk: FindingRisk
    }

    let report: ScanReport

    private var items: [Item] {
        let children = report.findings
            .filter {
                URL(fileURLWithPath: $0.path)
                    .deletingLastPathComponent()
                    .standardizedFileURL.path == report.rootPath
            }
            .sorted { $0.allocatedBytes > $1.allocatedBytes }
            .prefix(8)
            .map {
                Item(
                    id: $0.path,
                    name: URL(fileURLWithPath: $0.path).lastPathComponent,
                    allocatedBytes: $0.allocatedBytes,
                    risk: $0.risk
                )
            }
        return Array(children)
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("第一层文件夹占用")
                        .font(.headline)
                    Text("图中每一项只计算一次，更深层的分析结果不会重复叠加。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Chart(items) { item in
                    BarMark(
                        x: .value("已分配空间", item.allocatedBytes),
                        y: .value("目录", item.name)
                    )
                    .foregroundStyle(item.risk.color.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bytes = value.as(Int64.self) {
                                Text(bytes.formattedBytes)
                            }
                        }
                    }
                }
                .frame(height: max(180, CGFloat(items.count) * 30))
                .accessibilityLabel("一级目录已分配空间对比图")
            }
            .inspectorCard()
            .frame(maxWidth: .infinity)
        }
    }
}

private struct IssuesView: View {
    @EnvironmentObject private var model: InspectorViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("访问问题")
                    .font(.largeTitle.bold())
                Text("下面这些内容没有读完整。无法读取，不代表它们不占空间。")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            if let issues = model.report?.issues, !issues.isEmpty {
                if let report = model.report, report.omittedIssueCount > 0 {
                    Text("为避免全盘扫描占用过多内存，这里只保留前 \(issues.count.formatted()) 项；另外 \(report.omittedIssueCount.formatted()) 项只计数，不保留明细。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                List(issues) { issue in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(issue.kind.rawValue)
                                .font(.headline)
                            Spacer()
                            Image(systemName: issue.kind == .permissionDenied
                                ? "lock.fill"
                                : "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                        Text(issue.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                EmptyStateView(
                    title: "没有记录到访问问题",
                    systemImage: "checkmark.shield",
                    description: "这只说明本次选择的范围没有报告读取错误，并不表示应用绕过了 macOS 的权限限制。"
                )
            }
        }
    }
}

private struct GuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "使用说明",
                    subtitle: "它帮你看清空间去了哪里，但不会替你删除任何东西。"
                )

                guideSection(
                    "从哪里开始",
                    systemImage: "1.circle",
                    text: "第一次使用，建议先选择你的个人文件夹，或某个已经怀疑占用较大的应用目录。扫描完成后，先看占用排行，再打开具体项目查看说明和处理建议。"
                )
                guideSection(
                    "为什么不建议一上来扫描整块硬盘",
                    systemImage: "clock",
                    text: "扫描速度主要取决于文件数量，而不是磁盘容量。几十万个小文件往往比一个很大的文件更耗时。你可以随时取消；从个人文件夹或可疑目录开始，通常更快找到问题。"
                )
                guideSection(
                    "“可能可释放”该怎么看",
                    systemImage: "chart.bar.doc.horizontal",
                    text: "这个数字表示“值得继续核对的大小”，不等于一定能腾出的空间。共享磁盘块、稀疏文件、正在使用的文件，以及应用重新生成缓存，都会让实际结果变少。"
                )
                guideSection(
                    "你的数据会离开这台 Mac 吗",
                    systemImage: "lock.shield",
                    text: "不会。路径、文件名和扫描结果都只留在本机。Mac Disk Inspector 不联网，不删除、不移动、不修改文件，也不会替你运行任何终端命令。"
                )
                guideSection(
                    "为什么有些目录读不到",
                    systemImage: "hand.raised",
                    text: "“邮件”“信息”、Safari 等目录受 macOS 保护。读不到时，应用会如实列出这些目录，不会把它们算成零，也不会要求管理员权限。"
                )
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func guideSection(_ title: String, systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .inspectorCard()
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .inspectorCard()
    }
}

private struct DetailSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String?
    @ViewBuilder let actions: Actions

    init(
        title: String,
        systemImage: String,
        description: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
            if let description {
                Text(description)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            actions
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension EmptyStateView where Actions == EmptyView {
    init(title: String, systemImage: String, description: String? = nil) {
        self.init(title: title, systemImage: systemImage, description: description) {
            EmptyView()
        }
    }
}

private struct RiskDot: View {
    let risk: FindingRisk

    var body: some View {
        Circle()
            .fill(risk.color)
            .frame(width: 9, height: 9)
            .accessibilityLabel(risk.rawValue)
    }
}

private struct RiskBadge: View {
    let risk: FindingRisk

    var body: some View {
        Text(risk.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(risk.color.opacity(0.14), in: Capsule())
            .foregroundStyle(risk.color)
    }
}

private extension FindingRisk {
    var color: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        case .prohibited: .purple
        }
    }
}

private extension View {
    func inspectorCard() -> some View {
        padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

extension Int64 {
    var formattedBytes: String {
        if self == 0 { return "0 B" }
        if abs(self) < 1_000 { return "\(self) B" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.allowsNonnumericFormatting = false
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: self)
    }
}
