# Mac Disk Inspector

Mac Disk Inspector 是一个原生 macOS、默认只读的“可解释磁盘诊断器”。它回答三个问题：

1. 空间实际分配给了什么；
2. 为什么这些数据会出现、风险是什么；
3. 用户可以去哪里验证，并由用户自己决定是否处理。

它不是“一键清理大师”。App 不删除、不移动、不修改用户文件，不执行清理命令，不使用 `sudo`，不安装 privileged helper，也不上传路径、文件名或统计数据。

## MVP 能力

- 读取所选目录所在卷的总容量和可用空间；
- 由用户显式选择目录后进行本地只读扫描；
- 采用 allocated size，同时保留 logical size；
- 聚合根目录及最多三级子目录；
- 支持取消；
- 不跟随符号链接，默认不跨卷；
- 以设备号和 inode 去重硬链接；
- 记录权限、元数据、跨卷和符号链接问题，并明确展示访问缺口；
- 将扫描证据映射为 Finding：路径、allocated/logical bytes、文件数、修改时间、来源、类别、风险、置信度、解释、候选空间和建议；
- 首批规则覆盖 npm、`Library/Caches`、Gemini/Antigravity `browser_recordings`、Cursor `state.vscdb`、微信容器、Chrome `OnDeviceModel`、swapfile 和系统区域；
- 仅从编译进 App 的固定 allowlist 提供命令，且只复制、不执行。

## 运行

要求 macOS 13+ 和完整 Xcode。开发正式 `.app`：

```text
open MacDiskInspector.xcodeproj
```

扫描核心仍使用 Swift Package，便于独立测试：

```text
swift run MacDiskInspector
swift test
```

若本机尚未接受 Xcode 许可，可先运行不依赖测试框架的核心安全验收：

```text
swift run DiskInspectorCoreVerification
```

## 项目结构

```text
Sources/
  DiskInspectorCore/       扫描、模型、规则、容量读取、安全动作
  MacDiskInspectorApp/     SwiftUI App 与视图模型
  DiskInspectorCoreVerification/ 核心安全验收程序
Tests/
  DiskInspectorCoreTests/  规则、安全模板、符号链接、硬链接、权限与取消测试
App/                       Info.plist、只读沙盒、隐私与导出配置
Brand/                     品牌主图与视觉方向说明
MacDiskInspector.xcodeproj 正式 macOS .app 工程
Scripts/                   构建、社区包、安全校验与 Developer ID 公证流程
Documentation/
  USER_GUIDE.md
  PRIVACY.md
SECURITY.md                 漏洞报告与安全政策
  DISTRIBUTION.md
  ARCHITECTURE.md
  PRODUCT_AND_SAFETY.md
  IMPLEMENTATION_PLAN.md
  WORKLOG.md
```

## 隐私与权限

扫描仅在用户点击“选择目录并扫描”后开始。遇到 Mail、Messages、Safari 等受 TCC 保护的目录时，App 记录权限缺口，不推断其内容，也不会诱导用户授予全磁盘访问权限。是否授予权限由用户根据自己的诊断目标决定。

详细边界见 [Documentation/PRODUCT_AND_SAFETY.md](Documentation/PRODUCT_AND_SAFETY.md)。

## 文档

- [用户使用手册](Documentation/USER_GUIDE.md)
- [隐私说明](Documentation/PRIVACY.md)
- [官网分发与公证](Documentation/DISTRIBUTION.md)
- [RC 发布清单](Documentation/RELEASE_CHECKLIST.md)
- [RC1 验收结果](Documentation/RC1_ACCEPTANCE.md)
- [大目录性能结果](Documentation/BENCHMARK_RESULTS.md)
- [可复现构建与社区发布](Documentation/REPRODUCIBLE_BUILDS.md)
- [架构与威胁模型](Documentation/ARCHITECTURE.md)
- [漏洞报告与安全政策](SECURITY.md)
- [贡献指南](CONTRIBUTING.md)
- [更新日志](CHANGELOG.md)

## 持续集成

GitHub Actions 会在每个 PR 上运行单元测试、核心安全验收、Universal App 构建与源码安全不变量检查。社区包工作流只生成供维护者复核的 artifact，不会自动公开发布。

项目使用 [MIT License](LICENSE) 开源。
