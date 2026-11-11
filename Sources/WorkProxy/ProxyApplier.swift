import WorkProxyCore

struct SystemProxyActionApplier: ProxyActionApplying {
    let setup: Networksetup

    init(setup: Networksetup = Networksetup()) {
        self.setup = setup
    }

    func apply(_ action: ProxyAction, endpoint: ProxyEndpoint) async throws {
        let services = try setup.services()
        let controller = SystemProxyController(setup: setup)
        try controller.apply(action == .on, endpoint: endpoint, to: services)
    }
}
