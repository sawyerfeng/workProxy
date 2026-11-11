# 系统层直接控制 macOS 系统代理的可行性

调查时间：2026-11-11。目的：确认能否在不操作 Clash Verge / FlClash 界面的前提下，按网络环境开关代理。

## 结论

- **系统代理**：可以。`networksetup` / SystemConfiguration 能直接读写 HTTP、HTTPS、SOCKS 代理开关，不需要辅助功能权限，不需要客户端配合。
- **TUN**：不可以。TUN 是代理客户端内核创建的 `utun` 接口与路由，macOS 没有面向第三方 TUN 的统一开/关 API。要关 TUN 必须由客户端执行。
- **按 Wi-Fi 名称自动切换**：macOS 没有原生能力。系统代理只能按网络服务（Wi-Fi / 有线接口）或按 Location 配置，不能绑定 SSID。自动切换仍需要一个监听网络变化的小工具。
- 因此，只做"系统代理开/关"时，客户端 UI 自动化（AX）可以完全去掉；一旦要求 TUN，客户端适配无法删除。

## 实测记录（均已恢复原状）

环境：macOS 27.3，Apple Silicon。当前活动接口 `en7`（USB 网卡），`Wi-Fi` 未承载默认路由。

只读现状：

- `networksetup -getwebproxy|-getsecurewebproxy|-getsocksfirewallproxy`：所有网络服务的代理均为关闭。
- 两个客户端都把代理端口配置为 `127.0.0.1:7897`。
- Clash Verge 主程序未运行，仅有 `clash-verge-service` 常驻；FlClash 与 FlClashCore 在运行，但 `7897` 与 `7900` **没有监听**（内核未启动）。
- `scutil --proxy`：`HTTPEnable/HTTPSEnable/SOCKSEnable` 均为 0。

写权限验证（非活动服务 `Tailscale`，不影响当前流量）：

```
networksetup -setwebproxystate "Tailscale" on    # exit 0，无 sudo、无密码弹窗
networksetup -getwebproxy "Tailscale"            # Enabled: Yes, 127.0.0.1:7897
networksetup -setwebproxystate "Tailscale" off   # exit 0
networksetup -getwebproxy "Tailscale"            # Enabled: No
```

`man networksetup`：修改网络设置至少需要 admin 权限；若开启"访问系统级偏好设置需要管理员密码"，则需要 root。本账号属于 `admin` 组。**重启或重新登录后的首次写入是否弹窗尚未验证**，当前登录会话中无需密码。

`scselect`：

- `scselect` 列出两个 Location：`未命名`（当前）和 `Automatic`。
- `scselect <当前 UUID>` 返回 `CurrentSet updated to ...`，exit 0。
- 尚未执行跨 Location 切换，避免真实改变网络配置。

现有两个 Location 的差异（只读 `preferences.plist`）：

- `未命名`：`Wi-Fi`、`USB 10/100/1000 LAN 2` 等服务的代理关闭；服务顺序中有线排在 Wi-Fi 前。
- `Automatic`：`Wi-Fi`、`USB 10/100/1000 LAN` 的 HTTP/HTTPS/SOCKS 全部开启，指向 `127.0.0.1:7897`；服务顺序中 Wi-Fi 排在 USB 网卡前。

## 直接写系统代理的实现要点

1. **活动服务映射**：用 `networksetup -listnetworkserviceorder` 把主接口（如 `en7`）映射到服务名（如 `USB 10/100/1000 LAN 2`）；`networksetup` 只接受服务名。
2. **开启**：
   - 先确认代理端点可连接（默认 `127.0.0.1:7897`）；不可连接时不得开启，否则流量指向死端口。
   - 显式写入地址与端口：`-setwebproxy` / `-setsecurewebproxy` / `-setsocksfirewallproxy`（这三个命令本身就会开启代理）。
   - 现有配置里的端口可能是过期的（`USB 10/100/1000 LAN 2` 存的是 `7900`），不能只调 `-set...proxystate on`。
3. **关闭**：对相应服务执行 `-setwebproxystate off`、`-setsecurewebproxystate off`、`-setsocksfirewallproxystate off`。
4. **作用范围**：客户端通常对所有服务统一设置。工具可以对所有已启用服务写入，或只写当前活动服务；只写活动服务在下次换网时由规则重新应用。
5. **回读**：写完必须用 `-get...` 或 `scutil --proxy` 验证，不能只看命令退出码。

## Location + scselect 方案

优点：不需要逐次授权；切换是系统原生动作。

缺点：

- 切换 Location 会立即重配整套网络配置，不只是代理。
- 两个 Location 的服务顺序可以不同，双连接时主接口可能改变。
- DNS、IPv4/IPv6 等设置会随 Location 走，后续维护需要两边同步。
- 仍然需要一个工具按 SSID 调用 `scselect`。

## PAC 方案

`-setautoproxyurl` 可指向本地 PAC 文件，PAC 内用 `myIpAddress()` 判断当前网段并返回 `PROXY` 或 `DIRECT`。

- 优点：配置一次后无需监听网络事件。
- 缺点：按 IP 网段而非 SSID 判断；只对遵循系统代理的应用生效；TUN 开启时无效；排错困难。不建议作为主方案。

## 与客户端的冲突

- Clash Verge 2.5.10：`enable_proxy_guard: false`、`enable_system_proxy: false`、`enable_tun_mode: false`、`enable_auto_launch: true`。
- FlClash：`networkProps.systemProxy: false`、`vpnProps.enable: true`、`vpnProps.systemProxy: true`、`autoRun: false`、`autoLaunch: true`、`tun.enable: false`。
- 客户端启动或重载时可能按自身配置重新应用系统代理，覆盖工具写入；若客户端守护开启，还会持续纠正。稳定使用需要关闭守护或接受竞态。
- TUN 开启时，系统代理关闭不等于流量直连，这是系统层方案无法覆盖的语义缺口。

## 对需求的影响

- 可把第一版简化为"按网络规则开/关系统代理"，删除客户端 AX 适配、版本允许列表、菜单读取与回读。
- 若保留"仅 TUN / 全部关闭（含 TUN）"，客户端控制仍是必需项，当前未验证的 AX 路径不能删除。
- 开启系统代理前探测端点、失败不重试、单次通知等既有约束仍然适用。
