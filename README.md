# Mac 磁盘扫描助手

Mac 磁盘扫描助手（英文名：Mac Disk Inspector）是一个原生 macOS、默认只读的“可解释磁盘诊断器”。它回答三个问题：

项目主页：[github.com/chenyibai9527/MacDiskInspector](https://github.com/chenyibai9527/MacDiskInspector)

安装包与版本说明：[GitHub Releases](https://github.com/chenyibai9527/MacDiskInspector/releases)

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
- 解释 macOS Library/Application Support/Containers、系统运行目录、浏览器资料、云盘与媒体资料库；
- 覆盖 Xcode、Simulator、Docker、Homebrew、Node.js、npm、常见包管理器以及 AI 开发工具数据；
- 覆盖 Adobe、Figma、专业视频应用、Steam、微信、QQ、Chrome、Edge、Firefox 和 Safari 等高占用来源；
- 仅从编译进 App 的固定 allowlist 提供命令，且只复制、不执行。
- 在 macOS 26 及以上采用原生 Liquid Glass 功能层；macOS 13–15 自动回退到标准材质。

## 运行

运行要求 macOS 13+。从源码构建要求完整 Xcode 26 或更新版本，以编译 Liquid Glass API。开发正式 `.app`：

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

扫描仅在用户点击“选择目录并扫描”后开始。照片、音乐及其位于 `~/Library` 中的系统媒体索引与缓存、Mail、Messages、Safari、日历、通讯录、提醒事项、家庭数据，以及其他 App 的 Containers 与 Group Containers 等范围默认跳过。扫描器使用只返回目录项名称的 POSIX 浅层遍历，并在打开子目录或读取其元数据之前应用排除规则，避免 Foundation 在列出父目录时提前触碰受保护子项。用户主动开启后，App 才会在实际扫描到相应位置时交由 macOS 询问权限。被跳过或拒绝的位置会记录为覆盖缺口，不会被推断为 0 B。

详细边界见 [Documentation/PRODUCT_AND_SAFETY.md](Documentation/PRODUCT_AND_SAFETY.md)。

## 文档

- [用户使用手册](Documentation/USER_GUIDE.md)
- [隐私说明](Documentation/PRIVACY.md)
- [官网分发与公证](Documentation/DISTRIBUTION.md)
- [RC 发布清单](Documentation/RELEASE_CHECKLIST.md)
- [RC5 Liquid Glass 验收结果](Documentation/RC5_ACCEPTANCE.md)
- [RC4 历史验收结果](Documentation/RC4_ACCEPTANCE.md)
- [RC3 历史验收结果](Documentation/RC3_ACCEPTANCE.md)
- [RC2 历史验收结果](Documentation/RC2_ACCEPTANCE.md)
- [RC1 历史验收结果](Documentation/RC1_ACCEPTANCE.md)
- [大目录性能结果](Documentation/BENCHMARK_RESULTS.md)
- [可复现构建与社区发布](Documentation/REPRODUCIBLE_BUILDS.md)
- [架构与威胁模型](Documentation/ARCHITECTURE.md)
- [漏洞报告与安全政策](SECURITY.md)
- [贡献指南](CONTRIBUTING.md)
- [更新日志](CHANGELOG.md)

## 持续集成

GitHub Actions 会在每个 PR 上运行单元测试、核心安全验收、Universal App 构建与源码安全不变量检查。社区包工作流只生成供维护者复核的 artifact，不会自动公开发布。

GitHub Release 发布后，独立工作流会通过仓库 Secret
`CF_PAGES_DEPLOY_HOOK` 触发 Cloudflare Pages 官网的生产构建。配置步骤与可选
线上版本核验见
[官网分发与公证](Documentation/DISTRIBUTION.md#release-发布后同步-cloudflare-pages-官网)。

项目使用 [MIT License](LICENSE) 开源。

发现问题可前往 [GitHub Issues](https://github.com/chenyibai9527/MacDiskInspector/issues)；
安全漏洞请遵循 [安全政策](SECURITY.md)，不要先公开漏洞细节。
