# 官网分发与公证

本项目不提交 Mac App Store。公开版本使用 Developer ID 签名、Hardened Runtime、App Sandbox 和 Apple notarization。

## 前置条件

- Apple Developer Program 账户；
- 本机钥匙串中的 `Developer ID Application` 证书；
- Xcode 已登录对应 Team；
- 使用 `xcrun notarytool store-credentials` 创建的钥匙串 profile。

## 本地验证构建

```bash
./Scripts/build-app.sh
```

产物位于：

```text
build/DerivedData.noindex/Build/Products/Release/Mac 磁盘扫描助手.app
```

该脚本会在无需 Developer ID 的情况下进行 ad-hoc 签名，保留 App Sandbox 和“用户选择目录只读” entitlement。它仍不代表 Apple 已验证或已公证。

## 没有 Developer ID 时

可以发布未签名或 ad-hoc 签名的社区构建，但它不是无感安装：

1. 用户下载并解压 `.zip`，把 App 拖入“应用程序”；
2. 第一次双击通常会被 Gatekeeper 阻止；
3. 用户打开“系统设置 → 隐私与安全性”，在安全区域点击“仍要打开”；
4. 输入自己的登录密码确认；之后通常可以正常双击启动。

不要指导用户全局关闭 Gatekeeper，也不要把删除 quarantine 属性作为默认安装方式。公司管理的 Mac 可能由管理员策略禁止“仍要打开”，这种情况下未签名版本无法使用。

未签名、self-signed 和 ad-hoc 签名都不能证明发布者身份，也不能向 Apple 公证。源码公开、可复现构建和 SHA-256 可以改善供应链透明度，但不能替代 Developer ID 的系统信任体验。

推荐无账号版本使用 ad-hoc 签名，以保留 App Sandbox 与只读 entitlement：

```bash
./Scripts/package-community-preview.sh
```

该脚本生成的仍是“未知开发者”社区版本，不应标注为 Apple 已验证或已公证。

### 生成 DMG

```bash
./Scripts/package-dmg.sh
```

脚本会构建 Universal App，并生成包含以下内容的压缩 DMG：

- `Mac 磁盘扫描助手.app`；
- 指向 `/Applications` 的“Applications”快捷方式；
- `使用说明.pdf`；
- `打不开？双击这里.pdf`；
- 兼容无法预览 PDF 场景的 `打不开请看这里.txt`；
- 安静、克制的 Finder 安装背景、挂载磁盘图标与固定图标布局。

完成后，脚本会重新挂载 DMG，验证 App 名称、ad-hoc 签名、Applications
快捷方式、说明文档、Finder 布局以及 `arm64`、`x86_64` 双架构，并输出
SHA-256。DMG 默认位于：

```text
build/distribution/Mac磁盘扫描助手-0.2.0-universal.dmg
```

DMG 只改变分发和拖拽安装体验，不会让未公证的 App 自动获得系统信任。没有
Developer ID 时，首次启动仍可能需要用户通过“隐私与安全性”选择“仍要打开”。
“打不开”说明只采用 Apple 官方允许的“仍要打开”流程，不包含全局关闭
Gatekeeper、移除 quarantine、`sudo` 或任何自动修改系统安全设置的命令。
Finder 图标位置、挂载磁盘图标和背景由固定版本、固定 SHA-256 的
`dmgbuild` 构建依赖写入。
依赖只安装到被 Git 忽略的 `build/tools`，不进入 App；打包者无需授权终端控制
Finder，用户安装时也不会触发自动化权限。首次打包需要联网从 PyPI 获取
`Scripts/requirements-dmg.txt` 中锁定的构建依赖，后续会复用本地副本。

DMG 同时包含 72 DPI 与 144 DPI 背景资源，并在构建时合成为 HiDPI TIFF。
Finder 对自定义 DMG 背景的跨系统兼容性并不稳定，macOS 26.x 上可能忽略背景
图片；因此 App、Applications 快捷方式和三份说明文档即使在纯色背景下也保持
可辨认、可操作。背景只作为隐藏的 Finder 资源写入，不会再以普通图片文件重复
出现在安装窗口中。`.VolumeIcon.icns` 用于挂载后的磁盘图标；
浏览器直接下载 `.dmg` 时，下载文件自身的 Finder 自定义图标可能因扩展属性
丢失而回退为系统磁盘映像图标，不影响安装内容。

## 签名、归档与公证

不要把 Team ID、App Store Connect 密钥或公证密码提交到仓库。通过环境变量传入：

```bash
export MDI_TEAM_ID="YOUR_TEAM_ID"
export MDI_NOTARY_PROFILE="MacDiskInspector-Notary"
./Scripts/archive-notarize.sh
```

脚本会：

1. 创建 Release archive；
2. 使用 Developer ID 导出 `.app`；
3. 创建公证 ZIP；
4. 等待 Apple notarization；
5. staple ticket；
6. 使用 `codesign` 和 `spctl` 验证。

## 官网发布清单

- 更新 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`；
- 运行 `swift test` 和 Release 构建；
- 验证 entitlements 中没有网络或写权限；
- 公证并 staple；
- 生成 SHA-256；
- 发布 `.dmg` 或 `.zip`、哈希、签名 Team ID、源代码 tag 和变更日志；
- 在干净账户上验证 Gatekeeper 首次启动；
- 测试 macOS 13、14、15 和当前版本；
- 保留公证日志与构建 tag。

## Release 发布后同步 Cloudflare Pages 官网

`.github/workflows/deploy-website-on-release.yml` 监听 GitHub Release 的
`published` 事件。正式 Release 和 prerelease 都会触发，因为官网当前使用
`RELEASE_CHANNEL=preview`，会从公开 Release 中选择最新的 Universal DMG。
[GitHub Actions 官方文档](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release)
也明确建议：需要同时覆盖正式版与预发布版时，应监听 `published`，而不是组合
`released` 与 `prereleased`。

官网 Cloudflare Pages 项目的生产构建命令必须设置为：

```text
npm run build:cloudflare
```

该命令会先通过 GitHub Releases API 更新官网 Release 快照，再构建静态站点。

### 创建 Cloudflare Pages Production Deploy Hook

1. 登录 Cloudflare Dashboard，进入官网对应的 **Workers & Pages** 项目；
2. 打开 **Settings → Builds**，选择 **Add deploy hook**；
3. 创建一个指向生产分支的 Deploy Hook，例如命名为
   `MacDiskInspector GitHub Release`；
4. 复制 Cloudflare 生成的 Hook URL。不要把 URL 写入源码、Issue、Actions
   日志或公开文档。

具体界面与安全说明以
[Cloudflare Pages Deploy Hooks 官方文档](https://developers.cloudflare.com/pages/configuration/deploy-hooks/)
为准。Deploy Hook URL 无需额外认证即可触发构建，应像密码一样保护；如果怀疑
泄露，应在 Cloudflare 删除并重新生成。

### 在 GitHub 保存 Deploy Hook

1. 打开 `MacDiskInspector` GitHub 仓库；
2. 进入 **Settings → Secrets and variables → Actions**；
3. 在 **Repository secrets** 中创建：

   ```text
   CF_PAGES_DEPLOY_HOOK
   ```

4. 值粘贴为 Cloudflare Pages Production Deploy Hook 的完整 URL。

工作流不会回退到硬编码 URL。Secret 缺失、请求网络失败或 Cloudflare 返回非
2xx 状态时，工作流都会失败，不会误报官网部署已触发。

### 可选的线上版本验证

正式域名确定，并且官网公开提供 `/release.json` 后，可以额外配置：

```text
WEBSITE_RELEASE_STATUS_URL
```

它可以保存为 GitHub Actions Repository secret，也可以保存为 Repository
variable；建议值为官网完整的 HTTPS `/release.json` 地址。不要在域名尚未确定
时填写占位 URL。

配置后，工作流会在触发 Deploy Hook 后最多轮询五分钟，并要求 JSON 顶层
`tag` 与刚发布的 GitHub Release tag 完全一致。未配置时，工作流只确认
Cloudflare 接受了部署请求，并明确记录“未执行线上版本验证”；这不代表官网
内容已经上线或版本已经核验。
