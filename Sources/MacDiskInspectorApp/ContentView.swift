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
                .background(.thickMaterial, in: Capsule())
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
                    subtitle: "先理解占用，再决定是否处理。扫描只读取所选目录的元数据。"
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
                Text("macOS 预计在清理可回收系统数据后，重要任务最多可使用约 \(important.formattedBytes)。这不是当前空闲空间。")
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
            Text("已访问 \(progress.entriesVisited.formatted()) 项 · 已计量 \(progress.allocatedBytesMeasured.formattedBytes)")
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
            MetricCard(title: "发现项", value: report.findings.count.formatted(), systemImage: "list.bullet")
            MetricCard(title: "访问问题", value: report.totalIssueCount.formatted(), systemImage: "exclamationmark.triangle")
        }
    }

    private func coverageCard(_ report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("扫描覆盖状态")
                    .font(.headline)
                Spacer()
                Label(
                    report.hasCoverageGaps ? "部分覆盖" : "无读取错误",
                    systemImage: report.hasCoverageGaps
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .foregroundStyle(report.hasCoverageGaps ? .orange : .green)
            }
            Text(report.hasCoverageGaps
                ? "有 \(report.inaccessibleIssueCount.formatted()) 个目录或项目无法访问。一个目录可能包含任意数量的数据，因此不显示虚假的百分比。"
                : "扫描期间没有权限或枚举错误；问题列表仍会记录主动跳过的符号链接、其他卷和特殊文件。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !report.issues.isEmpty {
                Button("查看问题 \(report.totalIssueCount.formatted()) 项") {
                    model.selectedSection = .issues
                }
            }
        }
        .inspectorCard()
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            title: "尚未扫描目录",
            systemImage: "folder.badge.questionmark",
            description: "选择一个目录后，App 会在本机读取文件大小、分配空间和修改时间。"
        ) {
            Button("选择目录并扫描…") {
                model.chooseAndScan()
            }
            .buttonStyle(.borderedProminent)
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
                    Picker("排序", selection: $model.sortMode) {
                        ForEach(InspectorViewModel.FindingSort.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
                .padding()

                Text("已隐藏零占用项目和扫描根目录汇总；目录条目可能包含其下级内容。")
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
                    List(model.displayedFindings, selection: $model.selectedFinding) { finding in
                        FindingRow(finding: finding)
                            .tag(finding)
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
                        title: "选择一项查看证据",
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
                DetailSection(title: "为什么出现", text: finding.explanation)
                DetailSection(title: "建议", text: finding.recommendedAction)

                VStack(alignment: .leading, spacing: 10) {
                    Text("可验证动作")
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
                        .buttonStyle(.bordered)
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
            detailRow("规则置信度", finding.confidence.rawValue)
            detailRow(
                "候选空间",
                finding.potentialReclaimableBytes?.formattedBytes ?? "不估算"
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
                    subtitle: "所有动作都由你决定。命令只会复制到剪贴板，本 App 从不执行。"
                )

                ForEach(model.recommendationFindings) { finding in
                    HStack(alignment: .top, spacing: 14) {
                        RiskDot(risk: finding.risk)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(URL(fileURLWithPath: finding.path).lastPathComponent)
                                .font(.headline)
                            Text(finding.recommendedAction)
                                .foregroundStyle(.secondary)
                            Text("候选空间 \(finding.potentialReclaimableBytes?.formattedBytes ?? "待确认") · 不是释放承诺")
                                .font(.caption)
                        }
                        Spacer()
                        Button("查看证据") {
                            model.selectedFinding = finding
                            model.selectedSection = .findings
                        }
                    }
                    .inspectorCard()
                    .frame(maxWidth: .infinity)
                }

                if model.recommendationFindings.isEmpty {
                    EmptyStateView(
                        title: "暂无候选建议",
                        systemImage: "checkmark.shield",
                        description: "未知或高风险数据不会被标记为候选空间。"
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
                    Text("一级目录空间分布")
                        .font(.headline)
                    Text("各条互不重叠；深层规则发现不在这里重复累计。")
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
                Text("这些路径没有被完整计量。无权限不等于零占用。")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            if let issues = model.report?.issues, !issues.isEmpty {
                if let report = model.report, report.omittedIssueCount > 0 {
                    Text("为控制全盘扫描内存，仅展示前 \(issues.count.formatted()) 项；另有 \(report.omittedIssueCount.formatted()) 项未保存在报告中。")
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
                    description: "这不代表绕过了 macOS 权限；仅表示本次所选范围没有返回访问错误。"
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
                    subtitle: "Mac Disk Inspector 负责解释，不替你做删除决定。"
                )

                guideSection(
                    "推荐使用方式",
                    systemImage: "1.circle",
                    text: "先扫描用户目录或某个应用目录，再查看一级目录分布、访问问题和具体 Finding。只有确认来源、用途和备份后，才在目标 App、Finder 或终端中自行处理。"
                )
                guideSection(
                    "为什么全盘扫描很慢",
                    systemImage: "clock",
                    text: "准确统计必须访问每个文件的元数据。数百万个小文件可能需要数十分钟；系统休眠、外置盘和权限检查也会影响速度。你可以随时取消，优先扫描怀疑的目录通常更有效。"
                )
                guideSection(
                    "候选空间不是释放承诺",
                    systemImage: "chart.bar.doc.horizontal",
                    text: "候选空间表示值得进一步核对的数据体积。APFS Clone、稀疏文件、正在使用的数据和应用重建行为都会影响最终释放量。"
                )
                guideSection(
                    "隐私和只读边界",
                    systemImage: "lock.shield",
                    text: "App 不上传路径、文件名或统计数据；不执行 Shell 命令；不删除、移动或修改扫描到的文件。复制的命令必须由你在终端中主动执行。"
                )
                guideSection(
                    "遇到无权限",
                    systemImage: "hand.raised",
                    text: "Mail、Messages、Safari 等目录可能受 macOS 保护。App 会把它们列为访问缺口，不会把它们当成零字节，也不会要求管理员权限。"
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
        .inspectorCard()
        .frame(maxWidth: .infinity)
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
