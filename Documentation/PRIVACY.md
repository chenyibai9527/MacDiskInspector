# 隐私说明

## 数据处理

所有扫描和规则分析均在用户的 Mac 本地完成。Mac 磁盘扫描助手不包含网络客户端、分析 SDK、广告 SDK、账户系统或遥测端点。

项目不收集：

- 文件路径或文件名；
- 文件内容；
- 磁盘容量和扫描统计；
- 设备标识符；
- 使用行为和崩溃数据。

## 文件访问

正式 `.app` 启用 App Sandbox，仅申请：

```text
com.apple.security.files.user-selected.read-only
```

访问从用户主动打开 `NSOpenPanel` 并选择目录开始。App 不申请 user-selected read-write、网络客户端、管理员权限或全文件系统 entitlement。

macOS 的 TCC、ACL 和 POSIX 权限仍可能阻止访问。失败路径只在本机界面显示。

为避免在扫描个人文件夹或整块磁盘时意外触发敏感权限提示，App 默认跳过桌面、文稿、下载、图片与照片图库、音乐、影片、邮件、信息、Safari，以及其他 App 的 `Containers` 和 `Group Containers`。用户可以在“设置 → 受保护目录”中逐项选择是否扫描：

- 开启选项本身不会申请权限；
- 只有之后的扫描范围实际包含该目录时，macOS 才可能询问权限；
- 拒绝权限不会中断其他目录的扫描；
- 主动跳过和系统拒绝会分别记录，均不会被当作 0 B；
- 用户直接选择一个默认跳过的目录时，可以仅对该次扫描放行。

“其他 App 数据”不是基础扫描必需权限。保持关闭时，App 不会主动进入微信等应用的容器；开启后才能分析这些位置，macOS 15 或更高版本可能显示系统授权提示。

## 剪贴板与外部应用

用户点击“复制命令”时，固定模板会写入系统剪贴板。App 不读取剪贴板。用户点击“在 Finder 中显示”或“打开目标 App”时，App 调用 macOS 工作区服务完成明确动作。

## 开源验证

用户可以在
[GitHub 公开仓库](https://github.com/chenyibai9527/MacDiskInspector)
检查 `Sources/`、`App/MacDiskInspector.entitlements` 和构建脚本，验证发行版
应有的权限。官网下载页应同时公布签名 Team ID、版本哈希和源代码标签。
