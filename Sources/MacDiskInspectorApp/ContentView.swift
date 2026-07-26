import AppKit
import DiskInspectorCore
import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: InspectorViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPrivacyFooterHovered = false

    var body: some View {
        NavigationSplitView {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(InspectorViewModel.Section.allCases) { section in
                        StableSidebarRow(
                            section: section,
                            isSelected: (model.selectedSection ?? .overview) == section
                        ) {
                            selectSection(section)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .navigationTitle("Mac 磁盘扫描助手")
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                privacyFooter
            }
        } detail: {
            GeometryReader { proxy in
                ZStack {
                    InspectorBackdrop()

                    selectedPage
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
                .clipped()
            }
        }
        .background(InspectorBackdrop())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isScanning {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在扫描")
                            .font(.callout)
                    }
                    .padding(.horizontal, 4)
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("正在只读扫描")

                    Button("取消", role: .cancel) {
                        model.requestCancelScan()
                    }
                } else if model.report != nil {
                    Button {
                        model.rescanLastLocation()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.titleAndIcon)
                    .disabled(!model.canRescanLastLocation)
                    .help("再次扫描上次选择的目录")

                    Button {
                        model.chooseAndScan()
                    } label: {
                        Label("其他目录", systemImage: "folder.badge.plus")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("选择其他目录并开始只读扫描")
                } else {
                    Button {
                        model.chooseAndScan()
                    } label: {
                        Label(
                            model.report == nil ? "选择目录" : "重新扫描",
                            systemImage: "folder.badge.plus"
                        )
                    }
                    .labelStyle(.titleAndIcon)
                    .help(model.report == nil ? "选择目录并开始只读扫描" : "重新选择扫描目录")
                }
            }
        }
        .background {
            UnifiedWindowChrome()
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
                .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? .linear(duration: 0.16) : .spring(response: 0.36, dampingFraction: 1),
            value: model.statusMessage
        )
    }

    private func selectSection(_ section: InspectorViewModel.Section) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.selectedSection = section
        }
    }

    @ViewBuilder
    private var selectedPage: some View {
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

    @ViewBuilder
    private var privacyFooter: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                privacyFooterLabel
            }
            .buttonStyle(.plain)
        } else {
            Button {
                openLegacySettings()
            } label: {
                privacyFooterLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var privacyFooterLabel: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.45)

            HStack(spacing: 9) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 24, height: 24)
                    .background(
                        Color.green.opacity(0.11),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("只在本机分析")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("不上传 · 不改文件")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(isPrivacyFooterHovered ? 0.055 : 0))
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.12)) {
                isPrivacyFooterHovered = isHovered
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("打开设置。只在本机分析，不上传，不修改文件")
        .help("打开设置")
    }

    private func openLegacySettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

private struct StableSidebarRow: View {
    let section: InspectorViewModel.Section
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .center)

                Text(section.rawValue)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowBackground)
            )
            .foregroundStyle(rowForeground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(nil, value: isSelected)
        .animation(nil, value: isHovered)
        .accessibilityLabel(section.rawValue)
        .accessibilityValue(isSelected ? "已选择" : "")
    }

    private var rowBackground: Color {
        if isSelected {
            return controlActiveState == .key
                ? Color.accentColor
                : Color.primary.opacity(0.12)
        }
        return isHovered ? Color.primary.opacity(0.06) : .clear
    }

    private var rowForeground: Color {
        isSelected && controlActiveState == .key ? .white : .primary
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
                    scanCompletedCard(report)
                    summaryGrid(report)
                    UsageVisualization(report: report)
                    coverageCard(report)
                } else {
                    emptyState
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
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
                Text("据 macOS 估算，系统回收部分空间后，重要任务最多可使用约 \(important.formattedBytes)；这不是当前的可用空间。")
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
                .chartXScale(domain: 0...max(1, progress.entriesVisited))
                .frame(height: 64)
                .accessibilityLabel("从扫描开始到当前的已统计空间趋势")
            }
        }
        .inspectorCard()
        .frame(maxWidth: .infinity)
    }

    private func summaryGrid(_ report: ScanReport) -> some View {
        HStack(spacing: 14) {
            MetricCard(title: "已分配空间", value: report.totalAllocatedBytes.formattedBytes, systemImage: "square.stack.3d.up")
            MetricCard(title: "独立文件", value: report.uniqueFiles.formatted(), systemImage: "doc.on.doc")
            MetricCard(title: "分析结果", value: report.findings.count.formatted(), systemImage: "list.bullet")
            MetricCard(title: "未扫描与访问问题", value: report.totalIssueCount.formatted(), systemImage: "exclamationmark.triangle")
        }
    }

    private func scanCompletedCard(_ report: ScanReport) -> some View {
        HStack(spacing: 16) {
            Image(systemName: report.isPartial
                ? "pause.circle.fill"
                : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(report.isPartial ? .orange : .green)

            VStack(alignment: .leading, spacing: 3) {
                Text(report.isPartial ? "已停止，显示当前结果" : "扫描完成")
                    .font(.headline)
                if report.isPartial {
                    Text("以下内容只代表取消前已经完成的部分，不是整个目录的完整结果。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(report.rootPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 18)

            Button {
                model.rescanLastLocation()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(!model.canRescanLastLocation)
            .adaptiveGlassButtonStyle()

            Button {
                model.chooseAndScan()
            } label: {
                Label("选择其他目录", systemImage: "folder.badge.plus")
            }
            .adaptiveGlassButtonStyle()
        }
        .inspectorCard()
        .frame(maxWidth: .infinity)
    }

    private func coverageCard(_ report: ScanReport) -> some View {
        let skipped = report.protectedDirectorySkippedCount
        let inaccessible = report.inaccessibleIssueCount
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本次扫描是否完整")
                    .font(.headline)
                Spacer()
                Label(
                    report.isPartial
                        ? "只包含已扫描部分"
                        : inaccessible > 0
                        ? "有内容未能读取"
                        : skipped > 0
                            ? "部分目录按设置跳过"
                            : "未发现读取错误",
                    systemImage: report.hasCoverageGaps
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .foregroundStyle(report.hasCoverageGaps ? .orange : .green)
            }
            Text(coverageDescription(report))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !report.issues.isEmpty {
                HStack {
                    Button("查看未扫描项目 \(report.totalIssueCount.formatted()) 项") {
                        model.selectedSection = .issues
                    }
                    .adaptiveGlassButtonStyle()

                    if skipped > 0 {
                        protectedDirectorySettingsButton
                    }
                }
            }
        }
        .inspectorCard()
        .frame(maxWidth: .infinity)
    }

    private func coverageDescription(_ report: ScanReport) -> String {
        let skipped = report.protectedDirectorySkippedCount
        let inaccessible = report.inaccessibleIssueCount
        if report.isPartial {
            return "你在扫描完成前选择了查看当前结果。这里仅统计取消前已经访问到的内容，不能用来判断整个目录的总占用；重新扫描可获得完整结果。"
        }
        if skipped > 0, inaccessible > 0 {
            return "按你的设置跳过了 \(skipped.formatted()) 个受保护目录，另有 \(inaccessible.formatted()) 个目录或文件未能读取。未知内容无法可靠估算，因此不显示容易误导的覆盖率百分比。"
        }
        if skipped > 0 {
            return "按你的设置跳过了 \(skipped.formatted()) 个受保护目录。它们没有被计入占用结果，你可以在设置中逐项选择是否扫描。"
        }
        if inaccessible > 0 {
            return "有 \(inaccessible.formatted()) 个目录或文件未能读取。无法知道其中还有多少内容，因此不显示容易误导的覆盖率百分比。"
        }
        return "扫描时没有遇到权限或目录读取错误。主动跳过的符号链接、其他磁盘和特殊文件仍会列在“访问问题”中。"
    }

    @ViewBuilder
    private var protectedDirectorySettingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Label("管理受保护目录", systemImage: "slider.horizontal.3")
            }
            .adaptiveGlassButtonStyle()
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("管理受保护目录", systemImage: "slider.horizontal.3")
            }
            .adaptiveGlassButtonStyle()
        }
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
            .adaptiveProminentGlassButtonStyle(controlSize: .large)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

private struct FindingsView: View {
    @EnvironmentObject private var model: InspectorViewModel

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        HStack {
                            Text("占用排行")
                                .font(.title2.bold())
                            Spacer()
                            AdaptiveFindingSortPicker(selection: $model.sortMode)
                                .frame(width: 230)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Label(model.sortMode.explanation, systemImage: "arrow.up.arrow.down")
                            Text(model.showZeroByteFindings
                                ? "当前显示占用为零的项目；最外层目录汇总仍会隐藏。文件夹大小包含其中的下级内容。"
                                : "已隐藏占用为零的项目和最外层目录汇总。文件夹大小包含其中的下级内容。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.5)
                    }

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
                                            .listRowBackground(Color.clear)
                                    }
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .overlay {
                            if model.isSorting {
                                ProgressView("正在排序…")
                                    .padding(12)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .frame(width: findingsListWidth(for: proxy.size.width))

                Divider()

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func findingsListWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.46, 420), 560)
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
            detailRow("判断可信度", finding.confidence.rawValue)
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
                        Button("查看依据") {
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
            .frame(maxWidth: .infinity, alignment: .top)
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
            .overlay(alignment: .bottom) {
                Divider().opacity(0.5)
            }

            if let issues = model.report?.issues, !issues.isEmpty {
                if let report = model.report, report.protectedDirectorySkippedCount > 0 {
                    Label(
                        "其中 \(report.protectedDirectorySkippedCount.formatted()) 项是为避免意外触发敏感权限而按设置跳过的目录，并非读取失败。",
                        systemImage: "hand.raised.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                }
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
                            Image(systemName: issueIcon(issue.kind))
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
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            } else {
                EmptyStateView(
                    title: "没有记录到访问问题",
                    systemImage: "checkmark.shield",
                    description: "这只说明本次选择的范围内没有出现读取错误，并不表示应用绕过了 macOS 的权限限制。"
                )
            }
        }
    }

    private func issueIcon(_ kind: ScanIssueKind) -> String {
        switch kind {
        case .permissionDenied:
            "lock.fill"
        case .protectedDirectorySkipped:
            "eye.slash"
        default:
            "exclamationmark.triangle"
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
                    text: "第一次使用，建议先选择你的个人文件夹，或某个已经怀疑占用较大的应用目录。扫描完成后，概览页会显示“重新扫描”和“选择其他目录”；先看占用排行，再打开具体项目查看说明和处理建议。"
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
                    text: "不会。路径、文件名和扫描结果都只留在本机。Mac 磁盘扫描助手不联网，不删除、不移动、不修改文件，也不会替你运行任何终端命令。"
                )
                guideSection(
                    "为什么有些目录读不到",
                    systemImage: "hand.raised",
                    text: "照片、音乐、邮件、信息、Safari、日历、通讯录、提醒事项、家庭数据和“其他 App 数据”默认跳过，避免扫描时突然出现权限提示。你可以在设置的“受保护目录”中逐项开启；只有实际扫描到相应范围时，macOS 才可能询问。拒绝权限不会中断其他目录的扫描。"
                )
                guideSection(
                    "频繁扫描会伤硬盘吗",
                    systemImage: "internaldrive",
                    text: "正常使用不会。扫描器主要读取目录结构、大小和日期，不打开文件内容；SSD 的耐久消耗主要来自写入。不过全盘扫描会暂时占用 CPU、磁盘带宽和电量，因此不建议连续反复运行。优先扫描个人文件夹或可疑目录，通常更快也更安静。"
                )
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
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
        VStack {
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
            .padding(30)
            .frame(maxWidth: 460)
            .inspectorContentSurface(cornerRadius: 24)
        }
        .padding(32)
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
            .inspectorContentSurface(cornerRadius: 14)
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
