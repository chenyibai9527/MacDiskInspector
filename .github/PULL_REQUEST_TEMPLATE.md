## 改动

简述改动和用户可见影响。

## 验证

- [ ] `swift test`
- [ ] `swift run DiskInspectorCoreVerification`
- [ ] 涉及正式 App 时运行 `./Scripts/build-app.sh`
- [ ] 涉及发布包时运行 `./Scripts/verify-community-package.sh <zip>`
- [ ] 没有加入删除、移动、文件修改、`sudo`、任意 Shell 或网络遥测
- [ ] 新规则含正确命中与相似路径不命中的测试
- [ ] 截图、日志和测试夹具不包含私人路径或用户数据

## 风险与回滚

说明扫描边界、规则误判、性能或 UI 风险，以及如何撤回本改动。
