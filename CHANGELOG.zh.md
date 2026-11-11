# 更新记录

## 0.1.0 - 2026-11-12

首个公开版本：按网络与地点规则切换 macOS 系统代理，支持菜单栏手动操作和可选 Mihomo TUN 联动。

### 下载与安装

- **workProxy-0.1.0-macos-arm64.dmg**：适用于 Apple Silicon（M 系列）Mac，macOS 13+。打开后将 workProxy.app 拖入 Applications。
- **workProxy-0.1.0-source.zip**：本次发布标签对应的源码，含构建脚本与测试。
- **SHA256SUMS.txt**：安装包与源码 ZIP 的 SHA-256 校验值。
- GitHub 页面附带的 Source code ZIP / tar.gz 也对应本次发布标签。

### 功能

- 按 Wi-Fi 名称、有线接口及可选地点范围匹配规则，拖动排序调整优先级。
- 网络稳定后自动切换；菜单栏支持手动开启、关闭以及恢复自动规则。
- 可配置本机 Mihomo HTTP 控制器，同步开关系统代理与 TUN，并核验结果。
- 原生 SwiftUI 主窗口与菜单栏界面、Dock 图标、深浅色适配。
- 启动时提示尚未申请的权限，设置中显示状态并提供系统设置入口。
- 提供系统代理状态查询及直接开关的命令行入口。

### 验证与限制

- Swift 测试与 release 构建通过；DMG 校验、挂载内容和应用签名完整性已检查。
- 应用采用本机临时签名，**没有 Developer ID 签名及 Apple 公证**；首次打开可能被 macOS 安全检查拦截。
- 安装包仅含 arm64 架构；未验证 Intel、最低系统版本和全新设备上的首次授权流程。
- Clash Verge Rev 联动尚未实机验证。客户端重启或重载可能覆盖 TUN 状态，workProxy 不持续守护。
- 系统代理和 TUN 切换并非原子操作；失败时请查看界面提示。
- 控制器密钥保存在本地 settings.json 中，不使用钥匙串，请勿分享该文件。
