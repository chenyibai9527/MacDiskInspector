# 工作记录

## 2026-07-24

- 确认工作区为空，未初始化 Git。
- 检测到 Apple Swift 6.3.2 与 macOS SDK；`xcode-select` 当前指向 Command Line Tools，未安装/未选择完整 Xcode。
- 后续发现 `/Applications/Xcode.app` 已存在，但尚未接受 Xcode 许可；改用 Command Line Tools 的 macOS 15.4 SDK 进行无签名构建验证。
- 采用 Swift Package 作为项目单一来源，避免依赖 Xcode 工程生成步骤。
- 创建扫描核心、Finding 规则、安全动作、SwiftUI 三页界面和单元测试。
- 单元测试使用 Swift Testing，避免对当前 Command Line Tools 中缺失的 XCTest 模块产生不必要依赖。
- 当前 Command Line Tools 同时无法加载与其版本匹配的 Swift Testing；新增无测试框架依赖的核心验收可执行文件，覆盖规则、allowlist、硬链接、符号链接、权限错误、取消和深层精确规则。
- 核心验收首次发现对符号链接调用 `skipDescendants()` 可能误跳过后续兄弟目录；已移除该调用并通过夹具验证符号链接目标不会被扫描。
- 未扫描或修改工作区之外的用户数据；测试仅使用系统临时目录中的自建夹具。
- 未执行任何清理命令。
- 最终完整构建通过：核心库、SwiftUI App、核心验收程序均已编译并链接。
- 最终核心验收通过：输出 `DiskInspectorCore verification passed.`。
- 源码安全扫描未发现 `Process`/`NSTask`、Shell 执行、网络会话或生产代码中的删除/移动调用。
- 尚未运行 Swift Testing 单元测试：`/Applications/Xcode.app` 存在，但系统要求用户先在终端接受 Xcode 许可；App 启动与签名验收也保留到该步骤之后。

## 2026-07-24 后续加固

- Xcode 已正确切换并接受许可；正式 Swift Testing 测试通过。
- 修复稀疏文件 `st_blocks == 0` 时错误回退到逻辑大小的问题。
- 扫描元数据改为单次 `lstat`，以设备号限制同卷，减少全盘扫描系统调用。
- 将宽泛后代路径规则改为精确目录边界，避免全盘扫描时为每层缓存/System 后代创建聚合项。
- 移除固定比例“预计可释放”，改为不承诺结果的“候选空间”。
- 移除误导性的覆盖率百分比，新增完整访问问题页面。
- 修复旧扫描覆盖新扫描状态的竞态；排序改为后台一次性缓存。
- 增加扫描趋势图、一级目录非重叠空间图和内置使用说明。
- 新增正式 Xcode `.app` 工程、只读沙盒、Hardened Runtime、隐私清单和官网公证脚本。
- 正式无签名 Release `.app` 构建通过。
- 测试扩展到 17 项，新增稀疏文件、深层大目录和相似路径误判。

## 2026-07-24 RC1 验收

- 图标和品牌素材使用内置 imagegen 生成，并接入完整 macOS AppIcon 资产目录。
- 增加无需 Apple Developer 账号的 ad-hoc 社区版打包脚本。
- 测试扩展到 18 项，增加访问问题明细上限测试。
- 增加独立 Release 性能基准，使用真实 APFS 临时文件，不扫描用户数据。
- 10,000 / 50,000 / 100,000 文件扫描分别为 2.44 / 11.87 / 30.28 秒。
- 100,000 文件统计准确、聚合保持 4 项、峰值 RSS 约 42.4 MiB。
