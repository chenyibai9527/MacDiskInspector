# 参与贡献

感谢你帮助改进 Mac 磁盘扫描助手。这个项目最重要的约束不是“发现更多可删除内容”，而是避免把不确定数据描述成安全可删。

- [查看开放 Issue](https://github.com/chenyibai9527/MacDiskInspector/issues)
- [提交新的 Issue](https://github.com/chenyibai9527/MacDiskInspector/issues/new/choose)

## 开始之前

需要 macOS 13+、Xcode 26 或兼容工具链。首次使用：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
swift test
```

打开正式 App 工程：

```bash
open MacDiskInspector.xcodeproj
```

## 提交要求

- 扫描器保持只读，不加入删除、移动、修改或 Shell 执行能力。
- 新命令必须是固定模板，并为高风险数据提供负向测试。
- 新规则必须同时提供正确命中和相似路径不命中的测试。
- 不添加网络遥测、路径上传或远程规则执行。
- 改动扫描器时运行大目录、稀疏文件、符号链接、硬链接、权限和取消测试。
- UI 中不能把候选空间描述成保证可释放空间。

## 验证

```bash
swift test
swift build -c release
./Scripts/build-app.sh
```

涉及扫描性能的提交应附上夹具规模、硬件和前后耗时，不能只给主观描述。
