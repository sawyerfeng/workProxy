# 发布 workProxy

1. 更新 `Resources/Info.plist` 的短版本号和递增的构建号，并更新 `CHANGELOG.zh.md`、README 和 `site/index.html` 的下载链接、版本号；功能或配置流程变化时同步 `site/guide.html`。
2. 运行 `swift test --disable-sandbox`，通过 PR 合入 main。
3. 在干净的 main 检出中运行 `./scripts/package-release.sh`。
4. 对合入后的提交创建 `v<版本>` 标签，发布 `dist/release/<版本>/` 中的 DMG、应用 ZIP、源码 ZIP、`appcast.xml` 和 `SHA256SUMS.txt`。GitHub Release 必须是正式版本，以便 `releases/latest/download/appcast.xml` 指向它。
5. 下载发布附件并核对 SHA-256；使用较旧的测试副本验证更新提示、下载、签名校验和安装重启。

自动更新使用 Sparkle 2。公钥提交于 `Resources/Info.plist`，私钥保存在维护者本机登录钥匙串的 Sparkle 签名条目中，账户为 `io.github.sawyerfeng.workproxy`。发布脚本会核对公钥、签名更新归档及 appcast，并验证签名。

保管好这个钥匙串条目；不要把私钥放进 Git、发布附件、日志或 issue。迁移电脑时使用 Sparkle 官方 `generate_keys -x` / `-f` 在受保护的位置导出、导入。没有 Developer ID 签名时，丢失这个私钥会影响已有安装的后续更新。

`appcast.xml` 及归档签名验证后不可编辑。应用 ZIP 必须保留 framework 的符号链接和可执行权限，构建及打包脚本使用 `ditto` 完成此操作。
