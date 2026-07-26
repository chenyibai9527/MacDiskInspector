import AppKit
import SwiftUI

private enum ProjectLinks {
    static let repository = URL(
        string: "https://github.com/chenyibai9527/MacDiskInspector"
    )!
    static let issues = repository.appending(path: "issues")
    static let license = repository.appending(path: "blob/main/LICENSE")
}

struct AboutView: View {
    @State private var showsLicense = false

    private var versionDescription: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "版本 \(version)（\(build)）"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text("Mac 磁盘扫描助手")
                        .font(.title2.bold())
                    Text(versionDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("看清空间去了哪里，再由你决定如何处理。")
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 14) {
                AboutInfoRow(
                    systemImage: "lock.shield.fill",
                    title: "本机只读分析",
                    detail: "不删除、移动或上传文件，也不会替你运行清理命令。",
                    tint: .green
                )

                AboutInfoRow(
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    title: "开放源代码",
                    detail: "采用 MIT License。源代码、构建脚本和安全边界均可公开检查。",
                    tint: .accentColor
                )

                HStack(spacing: 10) {
                    Link(destination: ProjectLinks.repository) {
                        Label("查看源代码", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)

                    Link(destination: ProjectLinks.issues) {
                        Label("报告问题", systemImage: "exclamationmark.bubble")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 22)

            HStack {
                Button("查看 MIT License") {
                    showsLicense = true
                }

                Spacer()

                Text("Copyright © 2026 Mac 磁盘扫描助手贡献者")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .frame(width: 480)
        .background(InspectorBackdrop())
        .sheet(isPresented: $showsLicense) {
            LicenseView()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: InspectorViewModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("占用排行") {
                    Picker("默认排序", selection: $model.sortMode) {
                        ForEach(InspectorViewModel.FindingSort.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Toggle("显示占用为 0 B 的项目", isOn: $model.showZeroByteFindings)

                    Text("这些设置会立即应用，并在下次打开 App 时继续保留。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("隐私与安全") {
                    Label("所有分析都在本机完成", systemImage: "lock.shield")
                    Text("符号链接、跨卷访问和系统管理数据始终受只读边界保护。下面的选择只控制是否进入个人目录和其他 App 的受保护数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("受保护目录") {
                    Text("默认全部跳过。开启某一项不会立即申请权限；只有之后的扫描确实进入该范围时，macOS 才可能询问是否允许访问。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(InspectorViewModel.ProtectedDirectory.allCases) { directory in
                        Toggle(
                            isOn: Binding(
                                get: { model.isProtectedDirectoryEnabled(directory) },
                                set: { model.setProtectedDirectory(directory, enabled: $0) }
                            )
                        ) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(directory.title)
                                    Text(directory.displayPath)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: directory.systemImage)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .help(directory.privacyExplanation)
                    }

                    Label(
                        "是否授权始终由 macOS 决定。拒绝权限不会中断其他目录的扫描。",
                        systemImage: "hand.raised"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("开源与反馈") {
                    Link(destination: ProjectLinks.repository) {
                        Label(
                            "查看 GitHub 仓库",
                            systemImage: "chevron.left.forwardslash.chevron.right"
                        )
                    }

                    Link(destination: ProjectLinks.issues) {
                        Label("报告问题或提出建议", systemImage: "exclamationmark.bubble")
                    }

                    Link(destination: ProjectLinks.license) {
                        Label("查看 MIT License", systemImage: "doc.text")
                    }

                    Text("github.com/chenyibai9527/MacDiskInspector")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("恢复默认设置") {
                    model.restoreDefaultPreferences()
                }
            }
            .padding(16)
        }
        .frame(width: 600, height: 620)
        .navigationTitle("设置")
    }
}

private struct AboutInfoRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MIT License")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                Text(Self.licenseText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .frame(width: 560, height: 440)
    }

    private static let licenseText = """
    MIT License

    Copyright (c) 2026 Mac 磁盘扫描助手贡献者

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
}
