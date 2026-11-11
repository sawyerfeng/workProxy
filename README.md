<div align="center">

# workProxy

**换个网络，代理自动切换。**

一个按 Wi-Fi、有线网络与地点规则切换代理的 macOS 小工具。

![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![UI](https://img.shields.io/badge/UI-SwiftUI-438EFF)

[介绍网站](https://sawyerfeng.github.io/workProxy/) · [快速开始](#快速开始) · [使用方式](#使用方式) · [TUN 联动](#clash--mihomo-联动) · [常见问题](#常见问题)

</div>

## 为什么需要它

公司网络需要关闭代理，回到家又要打开；同名 Wi-Fi 在不同地点还可能需要不同的设置。workProxy 把这些操作变成规则，网络切换后自动执行，也能从菜单栏随时接管。

它需要配合已有的代理客户端使用，不提供代理服务器、节点或订阅。

## 功能

- **按网络切换**：匹配 Wi-Fi 名称或有线接口，自动开启、关闭系统代理。
- **按地点细分**：搜索地址、查看地图并设置半径，区分不同地点的同名网络。
- **规则按顺序匹配**：拖动调整优先级，取第一条符合条件的已启用规则。
- **菜单栏手动控制**：直接开启、关闭代理；手动操作暂停规则，点击“恢复自动”重新匹配。
- **可选 TUN 联动**：通过本机 Mihomo HTTP 控制接口同步切换 TUN，并回读状态确认。
- **原生 macOS 界面**：SwiftUI 主窗口、Dock 图标和菜单栏入口，支持深浅色与减少动态效果。
- **权限状态可见**：启动时申请尚未决定的权限，在设置里查看状态或前往系统设置重新授权。

## 快速开始

### 下载安装包

前往 [GitHub Releases](https://github.com/sawyerfeng/workProxy/releases/latest)，下载 `workProxy-0.1.0-macos-arm64.dmg`，打开后将 **workProxy.app** 拖入 **Applications**。

当前安装包面向 **Apple Silicon（M 系列）Mac**，最低系统版本 macOS 13；Intel Mac 可尝试从源码构建，尚未实机验证。安装包使用临时签名，未经过 Apple 公证，首次打开可能被系统安全检查拦截。

Release 同时提供源码 ZIP 与 SHA-256 校验文件。

### 从源码构建

需要 **macOS 13+、Swift 6 工具链及 Xcode 或 Command Line Tools**。项目没有第三方 Swift 包依赖。

```sh
git clone https://github.com/sawyerfeng/workProxy.git
cd workProxy
git switch master
./scripts/build-app.sh
open dist/workProxy.app
```

构建产物位于 `dist/workProxy.app`。需要登录时自动启动，可将应用移到 `/Applications` 或 `~/Applications`，再在设置中启用“登录时启动”。更新后请先退出旧实例，再打开新版本。

当前构建使用本机临时签名，未经过 Apple 公证。最低部署目标为 macOS 13，不代表所有系统版本和设备均已实测。

## 使用方式

1. **启动代理客户端**，在 workProxy 设置中填入它的代理地址，例如 `127.0.0.1:7897`。实际端口以客户端为准。
2. **允许定位权限**，用于读取 Wi-Fi 名称和匹配地点。通知权限可选，仅用于执行失败提醒。
3. **添加规则**，选择网络及“开启 / 关闭系统代理”；需要时添加地点条件。新规则默认启用，名称可自动生成。
4. **调整优先级**，把更具体的地点规则放在普通网络规则前面。列表开关用于启停规则，编辑按钮和右键菜单用于管理。
5. **交给自动切换**。保存规则不会立即改变代理；下次网络事件会匹配，也可在“运行详情”中立即应用。

| 操作 | 行为 |
| --- | --- |
| 菜单栏“开启 / 关闭” | 立即执行并暂停自动规则；配置联动后同步操作 TUN |
| “暂停”自动切换 | 只暂停规则，不改变当前代理 |
| “恢复自动” | 立即重新匹配当前网络 |
| 没有匹配的规则 | 保持现状 |

网络变化稳定 **3 秒**后执行，避免短暂断线引发反复切换。启动时匹配一次；同网络唤醒不重复执行。地点只是网络规则的附加条件，移动位置本身不会触发切换；定位不可用时会跳过地点规则，继续匹配后续规则。

## Clash / Mihomo 联动

默认只控制 macOS 系统代理。需要一并控制 TUN 时：

1. 在 FlClash、Clash Verge Rev 等 Mihomo 客户端中启用 **HTTP 外部控制器**，并确保客户端具备运行 TUN 的权限。
2. 打开 workProxy 的 **设置 → Clash / Mihomo 联动**。
3. 填写实际控制器地址和密钥，点击“测试连接”，启用同步开关并保存。

> **控制器端口与代理端口不同。** `http://127.0.0.1:9090` 只是地址示例，请以客户端配置为准。

执行时先更新系统代理，再通过 `PATCH /configs` 切换 TUN，最后通过 `GET /configs` 确认结果。若第二步失败，会明确提示“系统代理已更新，但 TUN 切换未确认”；两项操作并非原子事务。

联动只接受本机 HTTP 地址，不跟随重定向。它修改核心的运行状态，不改客户端的持久设置；客户端重启、切换订阅或重载配置可能覆盖状态，界面开关也可能不同步。建议关闭客户端的系统代理守护，避免相互覆盖。**Clash Verge Rev 的兼容性基于 Mihomo API，当前尚未实机验证。**

## 权限与数据

| 项目 | 用途 |
| --- | --- |
| 定位 | 读取 Wi-Fi 名称、检查地点条件 |
| 通知 | 规则执行失败时提醒；拒绝不影响规则执行 |
| 登录项 | 可选，使用 macOS `SMAppService` 注册 |

设置中的权限区域会显示授权状态。已拒绝的权限需要在系统设置中重新开启，返回应用后会刷新。

规则、网络名称、地点坐标及控制器密钥保存在：

```text
~/Library/Application Support/workProxy/settings.json
```

配置保存时设置为仅当前用户可读写（`0600`）。**密钥以明文存于本地配置，不使用钥匙串；反馈问题时不要上传该文件。** 地址搜索与地图展示使用 Apple 系统服务，需要网络。配置文件损坏时会隔离原文件并使用默认设置。

## 常见问题

### 为什么关闭系统代理后仍能访问代理网络？

TUN、独立 VPN 和应用自己的代理设置可以绕过系统代理。启用 Mihomo 联动可同步关闭指定核心的 TUN，但 workProxy 不负责关闭其他 VPN 或浏览器代理插件。菜单栏状态显示的是系统代理状态，不代表所有流量的实际路径。

### 为什么代理没有打开？

开启前会检查配置的代理端口是否能建立 TCP 连接。确认客户端核心正在运行，地址、端口填写正确。TUN 联动还需要可访问的控制器及正确密钥。

### 为什么显示部分开启？

不同代理类型可能处于不同状态。PAC 和自动代理发现目前只读，不随开关修改，因此开启它们时不能显示为“全部关闭”。

### 它会持续接管我的网络吗？

不会。它在规则触发或手动操作时执行，不持续纠正外部修改。仅修改当前 macOS 网络位置中的网络服务，不调整 DNS、服务顺序或其他网络位置。系统代理写入可能受账户权限或设备管理策略限制。

### 有哪些尚未验证的场景？

真实 TUN 与物理网络切换、IPv6 / 双栈路径、不同 macOS 版本及首次系统授权流程仍需更多实机验证。网络识别以系统 IPv4 主接口为主，并排除 `utun` 等虚拟接口。

## 命令行

```sh
# 查看网络与系统代理状态
dist/workProxy.app/Contents/MacOS/WorkProxy --status

# 直接控制系统代理
dist/workProxy.app/Contents/MacOS/WorkProxy --on --endpoint 127.0.0.1:7897
dist/workProxy.app/Contents/MacOS/WorkProxy --off

# 列出当前与已保存的 Wi-Fi 名称
dist/workProxy.app/Contents/MacOS/WorkProxy --wifi-networks
```

命令行开关不经过规则引擎，也不联动 TUN。`--on` 的端口探测失败时拒绝写入并返回非零退出码。

## 开发与反馈

```sh
swift test --disable-sandbox
./scripts/build-app.sh
```

- `Sources/WorkProxy`：原生界面、系统服务、Mihomo 控制接口。
- `Sources/WorkProxyCore`：规则模型、匹配引擎、网络状态机、配置存储。
- `Tests`：规则、网络事件、持久化、系统代理、控制接口及界面数据逻辑测试。

欢迎通过 [Issues](https://github.com/sawyerfeng/workProxy/issues) 反馈问题。请附 macOS 版本、客户端版本、复现步骤及脱敏错误信息。提交改动前请运行测试；网络切换和系统授权需要另外进行实机检查。

更多设计背景见 [规则规格](docs/spec-draft.md) 与 [系统代理控制研究](docs/research/system-proxy-direct-control.md)；历史设计记录可能与当前界面不同，以代码和本文说明为准。


### 介绍网站

静态网站位于 `site/`，无构建依赖。GitHub Actions 在 `master` 上的网页文件更新时部署到 [GitHub Pages](https://sawyerfeng.github.io/workProxy/)。

本地预览：

```sh
python3 -m http.server 8765 --directory site
```

浏览器打开 http://localhost:8765 。`scripts/check-site.js` 可在该页面的浏览器控制台执行，检查交互演示、状态保留、锚点和布局；请分别在桌面及移动视口运行。网页演示不会操作系统网络。
