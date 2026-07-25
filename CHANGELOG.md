# 更新日志

本项目遵循 [Semantic Versioning](https://semver.org/)；候选版本在版本号后使用 `-rcN`。

## 未发布

### 修复

- 将 Verification 与 Benchmark 的入口文件从特殊文件名 `main.swift` 改为普通 Swift 文件名，避免 Xcode 的 Swift Package scheme 将隐式入口和 `@main` 同时编译而报错。

## [0.2.0-rc5] - 2026-07-24

### 改进

- 重建窗口级 Liquid Glass 层级：增加可感知的环境背景、悬浮扫描操作层与侧栏隐私层。
- 扫描范围、只读状态和主要操作现在集中显示在同一功能层中，不再依赖零散的小玻璃按钮。
- 页面切换使用无弹跳的弹簧过渡；排序选中态使用 `glassEffectID` 和 matched glass transition。
- “减少动态效果”和“降低透明度”开启时自动切换为更克制的呈现。
- 删除标题栏中与扫描操作层重复的入口。

### 验证

- 使用项目内测试夹具在 macOS 26 上实际运行并检查空状态、扫描结果、占用排行、排序切换和使用说明。

## [0.2.0-rc4] - 2026-07-24

### 新增

- 在 macOS 26 及以上使用原生 SwiftUI Liquid Glass。
- 占用排行排序器使用 `GlassEffectContainer`、玻璃按钮和选中态突出样式。
- 主要操作、详情操作和临时状态提示使用系统 Liquid Glass。
- macOS 13–15 保留原有标准材质和按钮样式。

### 工程

- GitHub Actions 切换至 macOS 26 runner，确保使用包含 Liquid Glass API 的 Xcode 26 SDK。

## [0.2.0-rc3] - 2026-07-24

### 修复

- “占用排行”切换排序时不再重复计算与排序无关的建议列表。
- “类型”和“风险”排序现在显示清晰的分组标题，并说明当前排序规则。
- 为大小、类型和风险排序加入确定性的次级排序规则与单元测试。

## [0.2.0-rc2] - 2026-07-24

### 修复

- “使用说明”页面的卡片现在保持等宽，不再随文字长度变化。
- 重写应用内主要中文说明，移除中英文混写和生硬的翻译腔。
- 将“候选空间”等内部术语改成更容易理解的用户表达。

## [0.2.0-rc1] - 2026-07-24

### 新增

- 原生 SwiftUI 磁盘概览、占用排行、Finding 详情和建议中心。
- 用户显式选择目录后的本地只读扫描，支持取消、覆盖率和权限缺口。
- allocated/logical size、文件数、修改时间、多级目录聚合。
- 符号链接跳过、默认不跨卷、设备号与 inode 硬链接去重。
- npm、Library Caches、Antigravity browser recordings、Cursor 数据库、微信容器、Chrome 本地模型、swapfile 和系统区域规则。
- 固定 allowlist 的检查/清理命令复制，不执行 Shell。
- 空间构成与风险分布可视化、大目录提示和使用说明。
- Universal（arm64 + x86_64）社区预览包与可复现验证脚本。

### 安全

- App Sandbox 仅声明用户选择目录只读权限。
- 无网络 entitlement、遥测、删除、移动、`sudo` 或 privileged helper。
- 高风险和系统管理数据不提供删除命令。

### 已知限制

- 社区包采用 ad-hoc 签名，未经过 Apple Developer ID 签名与公证。
- 首次打开可能需要 Finder 中右键“打开”，不同 macOS 安全策略下表现可能不同。
- Mail、Messages、Safari 等受保护目录的覆盖率取决于用户授予的系统权限。
