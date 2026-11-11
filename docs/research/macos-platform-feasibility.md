# macOS 平台可行性

核验日期：2026-11-10。范围为 Apple 官方文档及 Apple DTS 明确答复；未运行原型、未改变系统设置，未测试具体 macOS/硬件/客户端组合。当前仓库为空，未发现本地 AGENTS.md 或 .codegraph。

## 判断

网络事件监听、Wi-Fi 名称读取、地址搜索、定位条件、菜单栏及登录启动均有公开 API，平台层面可行。最需实测的是 **TUN 开关后的底层物理网络识别**、**定位授权与返回时延/精度**。不应把它们描述为已验证可靠。

## 网络与 TUN 反馈循环

- `NWPathMonitor` 提供网络变化回调，可作为重新采样网络状态的入口；`NWInterface` 提供接口类型、名称和索引。[NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor/)、[NWInterface](https://developer.apple.com/documentation/network/nwinterface)
- `NWPath.availableInterfaces` 是按偏好顺序排列的可用接口列表；`usesInterfaceType` 的官方说明明确包括直接路由、经过隧道后使用物理接口、以及多个接口都可能可用。因此不能将一个布尔 `usesInterfaceType(.wifi)` 当作“唯一主网络”的证据，也不能把所有 path 回调都判定为物理网络切换。[usesInterfaceType](https://developer.apple.com/documentation/network/nwpath/usesinterfacetype(_:))
- `SCDynamicStore` 可读取当前网络状态，并按键或键模式订阅变化；适合作为网络服务/链路状态的补充信号。[SCDynamicStore](https://developer.apple.com/documentation/systemconfiguration/scdynamicstore-gb2)
- **实现推断与验证要求：**维护 Wi-Fi SSID/所选有线接口构成的物理网络身份及连接状态；路由、DNS、代理设置改变只触发重采样，身份未变不执行规则。过滤隧道接口并不自动解决多接口优先级，应在 Wi-Fi＋以太网＋TUN 同时存在时验证底层接口选择，包含 IPv4/IPv6 不同路径；必要时结合系统网络服务状态。不能只取默认路由的接口名称，因为代理本身可能改变路由。3 秒防抖不能替代身份去重。
- **实现推断：**有线规则保存所选网络服务标识及接口信息，不只保存可修改的显示名称；拔插、不同扩展坞、重建网络服务后的稳定性需要实测。

## Wi-Fi 名称与权限

- `CWWiFiClient`/`CWInterface` 可查询 Wi-Fi 并订阅事件；Apple 建议复用一个客户端，沙盒应用可使用客户端提供的接口对象。[Core WLAN](https://developer.apple.com/documentation/CoreWLAN)
- Apple DTS 确认 Sonoma 中访问 SSID 需要定位权限，是有意变更。[macOS get SSID changes?](https://developer.apple.com/forums/thread/732431)
- **对规格的影响：**定位权限被拒绝时，不仅地点条件可能不可用，纯 Wi-Fi 名称匹配也可能不可用。应显示权限状态并保持代理原状；可识别的纯有线规则仍按规则处理。不能承诺“拒绝定位后仍可按 Wi-Fi 名称运行”。
- 首次授权应由有正常 app 身份的应用流程完成；菜单栏、登录启动、权限撤销后的实际行为需要用最终签名的 app 验证，不能拿临时 shell 脚本的权限结果代表最终 app。

## 定位与地址搜索

- Mac 的定位根据附近 Wi-Fi 信息估计，不保证每次都有位置或达到固定精度。[Apple Support](https://support.apple.com/en-gb/guide/mac-help/mh27621/mac)
- Apple 明确建议检查位置时间戳，也可依据位置精度接受或拒绝位置结果。5 秒应是应用的等待截止时间，不是系统保证能定位的 SLA。[Getting the User’s Location](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/CoreLocation/CoreLocation.html)、[location](https://developer.apple.com/documentation/corelocation/cllocationmanager/location)
- `horizontalAccuracy` 表示坐标不确定性半径，负值表示无效。**建议（待实现定值）：**过滤过旧位置；精度不足以区分圈内外时归为位置不可用，按既定规则跳过地点条件。不要将缓存到的旧位置当成刚刚到达地点的证据。[CLLocation 初始化参数定义](https://developer.apple.com/documentation/corelocation/cllocation/init(coordinate:altitude:horizontalaccuracy:verticalaccuracy:course:speed:timestamp:))
- `MKLocalSearch` 支持按名称、地址或地点类型搜索，结果提供坐标；服务需要网络。用户搜索、选择结果后保存中心坐标与半径，网络切换时无需再次地址搜索。[Enabling Search](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/EnablingSearch/EnablingSearch.html)
- 不需要持续地理围栏监听，因为本产品仅在网络触发时检查位置。地址搜索质量、国内地址结果与 Core Location 坐标距离判定需实测，不应引入未经验证的第三方坐标转换。

## 界面、启动及版本选择

- SwiftUI `MenuBarExtra` 提供常驻菜单栏入口，可搭配设置窗口；`LSUIElement=true` 可隐藏 Dock/应用切换器图标。[MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- macOS 13 起 `SMAppService` 支持登录项管理，`mainApp` 可注册主应用。注册仍受用户授权/系统设置控制，UI 要显示真实状态，不能把偏好值当作注册成功。[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- **架构建议：**Swift＋SwiftUI 原生 app；最低支持版本可先定 macOS 13 或更高，最终取决于用户设备与测试矩阵。位置权限、系统通知权限与代理客户端必要权限分开处理；不因代理客户端需要权限就默认让整个 app 常驻 root。

## 原型必须证明

1. 最终 app 授权后读到 SSID，拒绝/撤销授权后按预期降级。
2. Wi-Fi↔有线，双连接优先级变化，同名 Wi-Fi 断线 2 秒/4 秒，以及睡眠唤醒。
3. TUN 开/关和系统代理修改不会产生第二次规则执行；操作等待定位期间又切网，旧任务必须失效。
4. 地点范围、定位无结果/过旧/低精度、5 秒超时和迟到回调，不重复接管。
5. 登录项被系统禁用、菜单栏 app 退出、恢复自动化时状态与规格一致。
