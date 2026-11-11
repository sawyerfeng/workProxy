# workProxy 交接

更新时间：2026-11-11。下一会话先读此文件，再读总规格与任务草稿。用户已要求继续开发；本轮完成了任务 01 的验证原型。用户随后明确确认“现在测试，结束后恢复初态”；子任务发布仍未获确认。

## 2026-11-11：系统层直控可行性（优先阅读）

用户提出“有没有不碰特定软件的设置方法，只按网络环境开关代理”。结论已实测并记录在 `docs/research/system-proxy-direct-control.md`：

- **系统代理可以直接控**，不需要辅助功能、不需要操作客户端。`networksetup` 可读写 HTTP/HTTPS/SOCKS 开关，本机当前会话实测无需 sudo、无密码弹窗，随后已恢复 Tailscale 原状。
- **TUN 不能客户端无关地控制**。TUN 是客户端内核创建的 utun 与路由，系统层没有统一开关。
- macOS **没有按 SSID 自动切代理的原生能力**；只能按网络服务或 Location 配置，自动切换仍需本工具监听网络事件。
- 本机已有两个 Location：`未命名`（代理全关，当前）与 `Automatic`（Wi-Fi/有线代理开启，指向 127.0.0.1:7897）；两者服务顺序不同，切换 Location 会整套重配网络。
- 当前 FlClash 在运行但 7897/7900 无监听；开启系统代理前必须探测端点，否则会断网。
- 现有服务里 `USB 10/100/1000 LAN 2` 存的是旧端口 7900，开启时必须显式写入地址与端口，不能只调 `-set...proxystate on`。
- 客户端启动/重载可能按自身配置覆盖系统代理：Verge `enable_proxy_guard: false`、`enable_system_proxy: false`、`enable_tun_mode: false`、`enable_auto_launch: true`；FlClash `systemProxy: false`、`tun.enable: false`、`autoLaunch: true`。

已确认（2026-11-11）：第一版只做“系统代理开/关”，直接改系统代理；TUN 不控制，客户端 AX 代码已删除。

## 2026-11-11 全量实现（优先阅读）

已按 issue #1 的功能面实现，范围按上述决定裁剪：

- 核心：规则模型、规则引擎、JSON 持久化、3 秒稳定状态机、定位降级、暂停/恢复、睡眠/唤醒、失败通知一次。
- 应用：`networksetup` 直控、端点探测、活动服务映射、`NWPathMonitor` + CoreWLAN SSID、CoreLocation 定位与地址搜索、`SMAppService` 登录项。
- 界面：菜单栏状态、设置窗口、规则增删改/排序、地点搜索与半径、端点、暂停、登录项、权限入口。
- Wi-Fi 规则名称改为下拉选择：读取系统保存过的网络（`networksetup -listpreferredwirelessnetworks <Wi-Fi 接口>`，当前连接排在最前），保留“手动输入”兜底和“刷新列表”。已用构建出的二进制执行 `--wifi-networks` 实测，能列出本机保存的网络。
- 界面按 issue #2 重构为 `NavigationSplitView`：概览、规则、设置、关于四栏；概览含状态卡片、系统代理实际状态、端点可达性、最近决策和定位权限提示；规则列表支持悬停操作、右键菜单、拖动排序和搜索；规则编辑器改为分组表单 + 底部取消/保存 + 就地校验；菜单栏菜单加入图标、状态行和快捷键。
- 新增应用图标生成脚本 `scripts/make-app-icon.swift` 与 `Resources/AppIcon.icns`；构建脚本把图标复制到 `Contents/Resources`，`Info.plist` 使用 `CFBundleIconFile`。
- 已用窗口截图验证概览、规则列表和规则编辑器（深色模式），布局、侧边栏、工具栏、搜索框、分段控件均正常；设置页与关于页为标准 Form，未单独截图。
- CLI：`--status / --on / --off / --endpoint / --wifi-networks`。
- 测试：57 项通过（规则、状态机、持久化、系统代理、Wi-Fi 列表解析）。
- 端到端：用“en7 → 关闭系统代理”临时规则启动验证，配置成功解码并执行；系统代理保持关闭。测试配置已删除，应用已退出。
- 未验证：真实“开启系统代理”（当前 7897 无监听）、定位权限真实授权、连上 Wi-Fi 时的 CoreWLAN SSID 读取（当前机器走有线 en7；下拉列表本身不依赖定位，已实测）、真实 TUN 场景、`/Applications` 下的登录项注册、IPv6/双栈。
- 未发布子任务；代码已提交并推送。

## 最新进展与方向（2026-11-10，保留）

- 用户当前询问能否绕开客户端、直接在系统层开关代理。系统代理可以通过 SystemConfiguration / networksetup 操作；TUN 没有适用于任意第三方内核的统一开关。尚未确认移除自动 TUN，不要擅自缩减已确认规格。
- 实际运行的 Clash Verge 已更新为 **2.5.10**。原型版本允许列表加入 2.5.10，界面标签同步更新，Release 构建通过；2.5.10 官方源码仍采用同名勾选菜单与相应切换回调。
- 用户已授权实机测试并要求结束后恢复初态，后又明确让代理代为处理桌面授权。macOS 27 将辅助功能列表改名为“设备控制和数据访问”；已用 CUA 移除旧 workProxy 项、重新添加 `dist/workProxy.app`。GUI 原型确认授权有效；终端运行 `--inspect` 仍会因调用责任进程不同提示缺少权限，不要据此再让用户重复授权 GUI。
- `agent-desktop` CLI 实际存在于 `/opt/homebrew/bin/agent-desktop`，已阅读其内置 desktop/platform 指南。它自身未获辅助功能权限；没有另行授权该工具，桌面操作使用现有 CUA。
- 闭合托盘的 AX 状态为 `AXMenuBar → AXMenuBarItem`，无子菜单，只暴露 `AXPress`。AXPress 返回成功，但连续 2 秒子菜单数量仍为 0。`AXShowMenu` 返回 -25206（actionUnsupported）。向客户端 PID 发送右键事件的实验也未自行展开菜单；代码中的 `openContextMenu` 是**未通过验证的实验**，不能当成可靠方案。
- 用户手动右键展开菜单后，读取到 `AXMenu → AXMenuItem`，`系统代理`、`TUN 模式` 名称和结构正确。原型“记录初态”成功，客户端为 **system=false、tun=false**；之后执行“全部关闭”成功，是同状态无写入验证。尚未实际启用系统代理或 TUN，也未完成三态测试。
- 原型记录初态时（11:00 前后），macOS HTTP/HTTPS/SOCKS 代理为 **开启**，PAC/自动发现关闭；FlClash 与 Clash Verge 同时运行，尚未确认系统代理来源。与此前 10:34 的全关快照不同，**不要用旧快照覆盖用户后来状态**。本轮操作未改变这些代理开关，无需为了“恢复”而主动改动它们。
- `docs/research/evidence/verge-2.5.10-before.json` 是 10:34 的只读证据（偏好文件关闭、系统代理关闭），不能当作 11:00 测试窗口的恢复数据。
- CUA 展示的 Clash Verge 窗口是空白，但用户明确说其本机界面正常。不能归因为客户端启动异常。读取其偏好只提取四项非敏感字段：tray_event=tray_menu、system=false、tun=false、proxy_guard=false；未修改配置、读取订阅或记录密钥。
- 为诊断，通过 LLDB 附加**自己的 WorkProxy 原型**检查 AX；调试会话均已 detach。临时探针位于 `/private/tmp/workproxy-*.lldb`，不是产品依赖。
- 下一步优先回答/落实系统代理直控方向，明确 TUN 是否仍需自动控制；不要再次重复菜单权限排查。未发布子任务。

## 当前状态

- 工作目录：`/Users/sawyerfeng/money/workPorxy`（本地目录拼写 Porxy，远程仓库为 Proxy）。
- GitHub：<https://github.com/sawyerfeng/workProxy>。
- 已初始化 Git，当前 main；origin 已关联远程，系统 Git 配置会将 HTTPS URL 映射为 SSH。首个提交与功能分支已推送。
- 已发布完整规格：<https://github.com/sawyerfeng/workProxy/issues/1>，标签 `ready-for-agent`。
- 用户已经确认总规格及测试边界；总 issue 无需再次请求批准。
- 已用 to-tickets 整理 7 项任务，逐项验收标准在 `docs/tickets/01.md` 至 `07.md`，目录在 `docs/tickets/README.md`。
- 7 项任务尚未获用户确认拆分，尚未发布；远程目前只有总 issue #1。
- 已实现完整第一版（系统代理范围）：规则引擎、3 秒稳定状态机、Wi-Fi/有线/地点规则、暂停、登录启动、睡眠唤醒、菜单栏与设置窗口、端点配置、失败通知。客户端 AX/FlClash 适配已删除。
- issue #2（界面优化）已实现并验证，随功能分支提交；PR 合并后关闭。
- `./scripts/build-app.sh` 生成 `dist/workProxy.app`（本机临时签名），`codesign --verify --strict` 通过。最低部署 macOS 13，实际只在 macOS 27.3 / Apple Silicon 构建启动。
- `swift test --disable-sandbox`：57 项通过。端到端验证使用临时“en7 → 关闭系统代理”规则，配置成功加载并执行；**真实开启仍未验证**，因为当前 7897 无监听。
- 应用已退出，临时测试配置已删除；系统代理保持全关。
- TUN 不在第一版控制范围；不要在文档或验收中宣称工具能关闭 TUN。
- 代码与文档已提交并推送（见本次 PR）。

## 需求真源

完整规格：`docs/spec-draft.md`（文件名虽有 draft，但内容及测试边界已确认并发布为 #1）。

> 2026-11-11 范围变更：第一版只控制系统代理，已删除客户端选择、AX 操作与 TUN 控制；下方原始规格中与客户端/TUN 相关的条目不再作为第一版验收项。网络规则、地点、暂停、登录启动、唤醒等行为仍按原规格实现。

核心行为：

- macOS 菜单栏常驻＋规则设置窗口；两款客户端均需支持，设置中选定当前控制对象。
- 目标状态：全部关闭／仅系统代理／仅 TUN。关闭时客户端仍运行。
- Wi-Fi 按名称，有线按选定接口；跟随系统主要物理连接。
- 第一版包含地址搜索＋可调半径；地点是网络规则附加条件，不独立触发。
- 规则可排序，取第一条匹配；新增地点规则默认优先于同网络普通规则。
- 未匹配保持状态且不提示，不撤销先前动作。尊重手动修改，不持续纠正。
- 新连接稳定 3 秒后执行；断线不足 3 秒回同网络不执行，达到 3 秒后重连重新匹配。
- 可能命中地点规则时最多等定位 5 秒；无可用定位则跳过地点规则继续匹配，迟到结果不补执行。
- 软件启动应用一次；同网络唤醒不重复，异网络唤醒执行。
- 暂停不改变代理，恢复开始应用当前规则；默认登录启动且可关闭。
- 客户端未运行不启动，后来手动启动也不补执行。
- 失败一次通知＋菜单栏状态，不无限重试。允许必要的一次性授权。

## 技术调查结论与限制

Apple 平台研究在 `docs/research/macos-platform-feasibility.md`，有一手来源。

- 已采用 Swift/SwiftUI，Swift 6+，最低部署版本暂定 macOS 13（仅当前机器验证）。
- macOS 的 SSID 读取也需要定位权限，拒绝定位可能导致纯 Wi-Fi 名称规则不可用；不能仅降级地点规则而假设 SSID 可读。
- TUN 会引起路由和网络回调，必须比较底层物理网络身份，避免自己触发自己。3 秒防抖不替代事件去重。
- Mac 定位精度与返回时间不保证；检查时间戳与精度，5 秒只是等待上限。
- Mihomo 的 TUN API 不是客户端系统代理接口；直接改 macOS 代理可能与客户端状态/代理守护冲突，直接改运行配置可能被重载覆盖。
- 已实现辅助功能读取菜单开关再操作客户端的原型，但尚未实测运行中的客户端，不能承诺后台可用或控制可靠。读取 `AXExtrasMenuBar`、直属菜单的 `AXMenuItemMarkChar` 后才按需点击；路径不可读时中止。
- 用户机器已读取到 Clash Verge 2.5.8、FlClash 0.9.2。验证应记录客户端显示与系统实际状态，不只看请求成功。
- 实机切换可能影响联网，应明确测试窗口并保存/恢复初始状态；本轮没有运行此类操作。

调查时临时克隆的源码（可能被系统清理，不是项目依赖）：

- `/private/tmp/workproxy-verge-research`：v2.5.8，commit `4337bd85758d54d7b9044b2da3c9ac1176eae1f3`。
- `/private/tmp/workproxy-flclash-research`：v0.9.2，commit `7fd417fb9a9a277c6a9339a8ac87f907df7c25f7`。
- Verge：`src-tauri/src/utils/server.rs` 暴露的本地路由不是代理开关 API；`src-tauri/src/cmd/verge.rs` 的 patch 是内部 Tauri 命令。`core/proxy_control.rs` 有代理守护，托盘提供系统代理/TUN 菜单。
- FlClash：`lib/common/link.dart` 处理配置导入，不是开关协议；`lib/common/tray.dart` 有两类开关。`lib/common/proxy.dart`、`plugins/proxy/lib/src/macos_proxy.dart`、`lib/providers/actions/setup.dart` 分别管理系统代理与内核设置。
- 未把客户端完整调查另存独立报告；以上是已阅读源码的摘要，不是运行测试证据。

## 待确认的 7 项拆分

| 编号 | 任务 | 依赖 |
|---|---|---|
| 1 | 验证 Clash Verge 三种代理状态控制 | 无 |
| 2 | 支持 FlClash 并保存客户端选择 | 1 |
| 3 | 按 Wi-Fi 名称规则自动切换代理 | 1、2 |
| 4 | 支持有线规则与双连接优先级 | 3 |
| 5 | 为网络规则加入地址搜索与地点范围 | 3 |
| 6 | 完善暂停、登录启动与睡眠唤醒 | 3 |
| 7 | 交付可安装第一版并验证完整使用流程 | 4、5、6 |

上次最后的问题是：确认按这 7 项及依赖发布，还是合并/细分。用户随后只要求 handoff，因此仍保留为待确认。

## 下一步

0. 范围已定：只系统代理，直接改系统代理。任务 01/02/03/07 已按此修订。下一步等客户端内核监听 7897 后，执行一次真实开启/关闭并恢复初态；随后实现网络规则引擎（Wi-Fi 名称 → 开/关系统代理）。
1. 若用户确认拆分或明确让继续发布，读取 `to-tickets` 技能并发布 7 个子任务，按依赖顺序创建。每项引用父 issue #1 并添加 `ready-for-agent`，记录真实编号。
2. 优先使用 GitHub 原生子任务/阻塞关系；查当前 API 后操作，不能把草稿序号当 GitHub issue 编号。保留正文 Blocked by 方便阅读，不关闭或改写总 issue 正文。
3. 任务 1 的最小可运行原型已经准备好，先做正在运行的 Clash Verge 的只读菜单路径验证。用户需手动启动客户端并授权 workProxy；原型不会自动启动客户端。只有明确测试窗口后才真实切换，留存初态，测试后恢复。
4. 当前原型仅允许 Clash Verge 2.5.8；三种目标、重复目标、权限失败、重载一致性、TUN 实际效果均待实机验证。若 AX 路径失败先调查实际结构，不要继续写完整规则界面。任务 01 未完成，任务 02 仍被阻塞。
5. 代码与文档已按用户授权提交并推送。

## 工具与本地约定

- to-spec：`/Users/sawyerfeng/.agents/skills/to-spec/SKILL.md`。总规格与测试边界的确认要求已满足。
- to-tickets：`/Users/sawyerfeng/.agents/skills/to-tickets/SKILL.md`。明确要求用户批准拆分后才发布。任务草稿已准备好，不要重新采访已有需求。
- 用户提供 CodeGraph 规则：仓库根存在 `.codegraph/` 时先用 CodeGraph 定位/理解代码；目前不存在，不要擅自索引。
- GitHub CLI `gh` 在沙盒里访问本机代理会失败，可能误报 token 无效；经审批的 `require_escalated` 调用成功，`sawyerfeng` 对目标仓库有 ADMIN 权限。不要要求用户重新登录或粘贴 token。
- GitHub connector 登录为 SkullCN，对此仓库只有读取权限；发布使用本机 gh，避免混用身份。
- 已成功使用 `gh issue create --body-file ...`、`gh label create`；仓库现有 `ready-for-agent` 标签无需重复创建。
- `but` 在本次 PATH 中未找到；不要假设 GitButler 已安装。使用原生 Git 初始化和关联 remote。
- 新会话如需提交/开发，按可用技能及仓库新出现的指令执行。没有用户要求时不主动创建子代理。
- 首次 Release 构建的 `dsymutil` 在沙盒内报 `Operation not permitted`，使用获审批的沙盒外构建成功。Debug 测试可在沙盒内运行，SwiftPM 用户缓存不可写的警告未影响测试。
- 原型已通过 CUA 启动，已检查客户端未运行的失败提示；最后重新打开后停留在初始验证窗口。未点击权限按钮或任何客户端开关。若更改代码后重建，需要重新启动原型才会使用新二进制；重建临时签名也可能需要重新授权。
- 用户已确认短时实机测试窗口：“现在测试，结束后恢复初态”。应继续检查客户端及授权，先记录初态、测试后恢复；无需再次请求同一测试授权。
- 获准后再次运行 `--inspect`（2026-11-10 09:59 本地时间），确认 Clash Verge 未运行，尚未切换代理。随后点击原型“辅助功能授权”入口，未代替用户更改系统隐私授权。等待用户手动启动 Clash Verge 2.5.8 并完成 workProxy 的辅助功能授权后继续；不要再次问是否允许该测试。

## 快速继续提示词

“阅读 HANDOFF.md、docs/spec-draft.md 和 docs/tickets/README.md，接着 workProxy 工作。总规格已发布为 sawyerfeng/workProxy#1；7 项子任务目前仅为本地草稿。先根据我这次的明确指令处理发布，再从客户端控制验证开始，不要重复需求访谈或把源码研究当成实机验证。”
