import WorkProxyCore

struct SystemProxyActionApplier: ProxyActionApplying {
    let store: (any SettingsStoring)?
    let setup: Networksetup

    init(setup: Networksetup = Networksetup(), store: (any SettingsStoring)? = nil) {
        self.store = store
        self.setup = setup
    }

    func apply(_ action: ProxyAction, endpoint: ProxyEndpoint) async throws {
        let flClash = try store?.load().flClash
        let services = try setup.services()
        let controller = SystemProxyController(setup: setup)
        try controller.apply(action == .on, endpoint: endpoint, to: services)
        if let flClash {
            do {
                try await FlClashController().setTUN(action == .on, configuration: flClash)
            } catch {
                throw FlClashControlError.message("系统代理已更新，但 TUN 切换未确认：\(error.localizedDescription)")
            }
        }
    }
}
