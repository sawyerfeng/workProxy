# 客户端控制验证记录

> 2026-11-11 起已被 [系统代理直控研究](system-proxy-direct-control.md) 取代。第一版不再操作客户端界面，也不控制 TUN；本文仅保留为历史记录，相关客户端原型代码已删除。

日期：2026-11-10。任务 01 进行中，**尚未达到验收门槛**。

## 环境与已执行验证

- macOS 27.3（26C5035r），Apple Silicon；Xcode 提供 Swift 6.4。
- 应用部署目标 macOS 13；没有在 macOS 13 或 Intel 上运行。
- 本机安装 Clash Verge 2.5.8，bundle ID 为 `io.github.clash-verge-rev.clash-verge-rev`。
- `swift test --disable-sandbox`：5 项测试、0 失败。覆盖 4 种开关组合间的 16 条转换、重复设置、先关闭再开启、延迟回读、部分失败、回读超时只写一次、客户端不可读时无写操作。使用假客户端，不代表 AX 控制通过。
- `./scripts/build-app.sh`：Release 构建成功，产出 `dist/workProxy.app`，本机临时签名；`codesign --verify --strict` 通过。
- 初次 Release 构建在沙盒中因 `dsymutil` 的 `Operation not permitted` 失败；获工具审批后在沙盒外完成，未更改网络设置。
- 原生窗口已启动并目视检查；未记录初态时三个切换按钮和恢复按钮禁用。
- 在沙盒外执行打包应用的 `--inspect`，及在窗口点击“读取状态”：均检测不到运行中的 Clash Verge，返回失败提示；客户端未被启动。
- 只读系统快照：HTTP、HTTPS、SOCKS 开启，PAC、自动发现关闭；存在多个已启用的 utun 接口。没有读取代理地址、订阅、密钥或精确位置。这些现象不归属到 Clash Verge，也不证明其 TUN 已开启。
- 本轮没有点击客户端开关，没有改变系统代理或 TUN；用户确认测试窗口后已点击 workProxy 的辅助功能授权入口，尚未代替用户授予隐私权限，也未申请通知权限。

## 实现与证据边界

使用 Apple [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement) 访问指定客户端的 `AXExtrasMenuBar`，只匹配托盘直属菜单里的系统代理/TUN 项。读取勾选状态，再按需要点击；无法唯一识别或读取时中止，不猜测。

菜单名称和勾选开关的设计来自 Clash Verge v2.5.8 源码（commit `4337bd85758d54d7b9044b2da3c9ac1176eae1f3`）：

- [tray/mod.rs](https://github.com/clash-verge-rev/clash-verge-rev/blob/4337bd85758d54d7b9044b2da3c9ac1176eae1f3/src-tauri/src/core/tray/mod.rs)：`CheckMenuItem`，菜单回调调用对应切换函数。
- [中文菜单](https://github.com/clash-verge-rev/clash-verge-rev/blob/4337bd85758d54d7b9044b2da3c9ac1176eae1f3/crates/clash-verge-i18n/locales/zh.yml)：`系统代理` / `TUN 模式`。
- [英文菜单](https://github.com/clash-verge-rev/clash-verge-rev/blob/4337bd85758d54d7b9044b2da3c9ac1176eae1f3/crates/clash-verge-i18n/locales/en.yml)、[繁体中文菜单](https://github.com/clash-verge-rev/clash-verge-rev/blob/4337bd85758d54d7b9044b2da3c9ac1176eae1f3/crates/clash-verge-i18n/locales/zhtw.yml)。

这是待验证实现假设，尚未在运行中的客户端证明 `AXExtrasMenuBar`、展开动作及勾选属性可用。若路径不成立，先记录实际 AX 结构与错误，再选择替代方案。

系统代理证据通过 Apple [SCDynamicStoreCopyProxies](https://developer.apple.com/documentation/systemconfiguration/scdynamicstorecopyproxies(_:)) 读取全局开关，不写入系统设置。TUN 仅列出已启用 utun 接口，始终标记未验证；后续需将目标内核的运行状态、接口和路由变化相互对应，不能直接按接口数量判成功。

## 待执行矩阵

在明确测试窗口，先记录并留存初态，结束后恢复初态。客户端启动与系统隐私授权由用户完成。

| 项目 | 当前状态 |
|---|---|
| 菜单栏工具构建、签名、窗口启动 | 已验证当前机器 |
| 未运行客户端不自动启动 | 已验证当前机器 |
| 已运行客户端：后台读取菜单及勾选状态 | 待测 |
| 三种目标＋重复目标，客户端与系统一致 | 待测 |
| 辅助功能拒绝、撤销、开关禁用 | 待测；只有假客户端失败测试 |
| TUN 权限失败、部分完成 | 待测；只有假客户端部分失败测试 |
| 超时不重复点击 | 假客户端测试通过，真实客户端待测 |
| 已授权时单次失败通知与菜单栏提示 | 菜单栏提示已实现，通知待测 |
| 保存初态、恢复初态（含两项同时开启） | 假客户端转换通过，真实客户端待测 |
| 客户端重载后仍一致 | 待测 |
| FlClash | 尚未实现，受任务 01 阻塞 |

用户已确认“现在测试，结束后恢复初态”。确认后 09:59 的只读检查仍显示 Clash Verge 未运行；等待用户手动启动并授权后继续。未发布子任务，未提交或推送本地文件。下一步先验证正在运行的 Clash Verge 的只读菜单路径，再按已获准测试窗口切换；不得据当前测试推进到“客户端已可靠控制”的结论。
