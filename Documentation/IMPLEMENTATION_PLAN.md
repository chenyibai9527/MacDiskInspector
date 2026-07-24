# 实现计划

## M0：可运行只读 MVP（本次）

- Swift Package + SwiftUI macOS App；
- 容量读取、用户选目录、扫描/取消；
- allocated/logical size、目录聚合、硬链接去重；
- 符号链接、跨卷、权限错误处理；
- Finding 和首批 8 组规则；
- 固定动作 allowlist；
- 概览、排行、详情、建议中心；
- 核心安全测试。

验收目标：`swift build` 与 `swift test` 通过；完整 Xcode 下可启动窗口并手工选择测试目录。

当前验收状态：

- 使用完整 Xcode 工具链，完整 App 与核心验收程序构建通过；
- 核心验收程序执行通过；
- Xcode 工具链已启用，Swift Testing 正式测试通过；
- 正式 Xcode `.app` 工程、只读沙盒、Hardened Runtime 和无签名 Release 构建通过；
- Developer ID 签名与 notarization 需要发布者证书和 Team ID，在发布阶段执行。

## M1：扫描准确性

- 用可注入文件系统接口完成稳定的权限错误测试；
- 增加 clone file、package 与本地化路径夹具；稀疏文件和大目录夹具已完成；
- 访问问题已经替代不可靠的百分比；后续增加失败子树规模提示；
- Finding 聚合和访问问题明细已设置边界；后续继续增加完整扫描会话内存基准；
- 支持用户选择聚合深度。

## M2：解释与验证

- Finding 规则版本和证据字段；
- 年龄分布、文件类型分布、单目录异常阈值；
- 官方文档链接 allowlist；
- 建议的已验证/暂不处理状态，仅保存在本机。

## M3：分发准备

- App Sandbox 与用户选择目录只读访问已完成；持久 bookmark 暂不需要；
- 本地化、VoiceOver、键盘导航和高对比度验收；
- 签名、公证、隐私清单；
- 性能与能耗测试。

## 明确不进入路线图

自动清理、`sudo`、privileged helper、远程规则注入、路径/统计上传。
