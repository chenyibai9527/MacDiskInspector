# 可复现构建与社区发布

## 目标

任何贡献者都应能从同一提交构建、测试并检查社区预览包。由于 Apple 工具链、SDK 和签名元数据可能变化，这里所说的“可复现”是指构建步骤和安全属性可复验，不承诺 ZIP 的每个字节完全相同。

## 环境

- macOS 13 或更高版本；
- 完整 Xcode 26 或更新版本，当前项目 CI 使用 `macos-26` runner；
- Swift Package Manager；
- 不需要第三方包管理器或运行时依赖。

确认当前使用完整 Xcode：

```bash
xcode-select -p
xcodebuild -version
swift --version
```

若输出仍指向 `/Library/Developer/CommandLineTools`，需要先从 Apple 安装完整 Xcode，再切换开发目录。只运行 `sudo xcodebuild -license` 不能替代 Xcode 安装。

## 本地验收

```bash
swift test
swift run DiskInspectorCoreVerification
./Scripts/check-source-safety.sh
./Scripts/package-community-preview.sh
./Scripts/verify-community-package.sh \
  build/community/MacDiskInspector-0.2.0-rc4-universal-community.zip
```

包脚本只接受字母、数字、点、下划线和连字符组成的短版本标签，避免 CI 输入形成意外路径。

## 社区包属性

- Universal 二进制：`arm64` 与 `x86_64`；
- ad-hoc 签名，不冒充 Developer ID；
- Hardened Runtime；
- App Sandbox；
- 只有用户选择目录只读 entitlement；
- 不含网络 client/server entitlement；
- 包内包含 `PrivacyInfo.xcprivacy`。

校验脚本会检查上述属性。校验通过不等于 Apple 公证，也不保证所有 Mac 的 Gatekeeper 行为一致。

## GitHub Actions

- `CI`：每次提交或 PR 运行测试、安全验收、Universal App 构建和源码不变量检查。
- `Build community package`：维护者手动输入版本标签，构建 ZIP 与 SHA-256，并仅上传为 14 天的 Actions artifact。

工作流不会自动创建公开 Release。维护者必须下载并在干净账号或干净 Mac 上验收，再手动发布，同时附上校验和与未公证说明。
