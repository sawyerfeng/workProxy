import SwiftUI
import WorkProxyCore

struct FlClashSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var enabled: Bool
    @State private var address: String
    @State private var secret: String
    @State private var message: String?
    @State private var checking = false

    init(model: AppModel) {
        self.model = model
        _enabled = State(initialValue: model.settings.flClash != nil)
        _address = State(initialValue: model.settings.flClash?.address ?? "http://127.0.0.1:9090")
        _secret = State(initialValue: model.settings.flClash?.secret ?? "")
    }

    var body: some View {
        Toggle("系统代理与 TUN 同步开关", isOn: $enabled)
        if enabled {
            TextField("HTTP 控制器地址", text: $address)
                .help("使用客户端的 HTTP 外部控制器端口，不是代理端口")
            SecureField("控制器密钥", text: $secret)
                .help("密钥保存在仅当前用户可读的本地设置文件中")
        }
        HStack {
            Button("保存联动设置") {
                let config = enabled ? FlClashSettings(
                    address: address.trimmingCharacters(in: .whitespacesAndNewlines), secret: secret) : nil
                message = model.setFlClash(config)
                    ? "已保存，下次执行规则时生效。" : model.lastError
            }
            if enabled {
                Button("测试连接") {
                    checking = true
                    let config = FlClashSettings(
                        address: address.trimmingCharacters(in: .whitespacesAndNewlines), secret: secret)
                    Task { @MainActor in
                        defer { checking = false }
                        do {
                            let active = try await FlClashController().tunEnabled(config)
                            message = active ? "连接成功，TUN 当前已开启。" : "连接成功，TUN 当前已关闭。"
                        } catch {
                            message = "连接失败：\(error.localizedDescription)"
                        }
                    }
                }
                .disabled(checking)
            }
        }
        if let message { Text(message).font(.caption).textSelection(.enabled) }
    }
}
