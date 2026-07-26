# 架构与威胁模型

## 模块

- `DiskInspectorCore`：只读扫描、容量、Finding 模型、规则和动作清单。
- `MacDiskInspectorApp`：目录选择、扫描会话状态和 SwiftUI。
- `DiskInspectorCoreTests`：文件系统边界与规则测试。
- `DiskInspectorCoreVerification`：测试框架不可用时的最小核心验收。
- `MacDiskInspector.xcodeproj`：正式 `.app`、沙盒、Hardened Runtime 与归档入口。

## 信任边界

```text
用户选择目录
      │ 只读 sandbox extension
      ▼
DirectoryScanner ──本机内存──▶ RuleEngine ──▶ Finding
      │                                │
      └─ 权限/跨卷/链接问题            └─ 固定动作 ID
                                                │
                                                ▼
                                  Finder / App / 复制固定命令
```

扫描结果不是删除授权。规则无法产生 Shell 字符串；动作层只根据固定 rule identifier 返回编译期模板。

## 目录遍历

扫描器使用显式目录栈逐层读取，每次只列出一个已经通过边界检查的目录：

1. 标准化 APFS Data 宗卷镜像与 `/private` 路径；
2. 使用 POSIX `readdir` 只读取目录项名称，避免 Foundation 在列出父目录时预取受保护子项元数据；
3. 根据名称构造纯词法路径，并在调用 `lstat` 或打开子目录之前匹配受保护目录；
4. 对符号链接、其他卷和无权限项目记录问题，但不继续向下；
5. 只将通过检查的普通目录加入待扫描栈。

这一顺序是隐私边界的一部分。不能改回先创建全树递归枚举器、再对已经返回的目录调用 `skipDescendants()`，因为 macOS 可能在后续跳过之前就进行受保护资源授权判断。

## 已知限制

- APFS Clone 的共享物理块不能仅凭普通文件元数据准确去重；
- 扫描期间文件系统可能变化，报告是某一时间窗口的近似快照；
- 权限失败子树的真实字节数未知；
- 全盘扫描时间主要取决于文件数量和存储延迟；
- 本地攻击者在扫描期间替换路径仍存在 TOCTOU 风险；未来可评估基于文件描述符的物理遍历。
