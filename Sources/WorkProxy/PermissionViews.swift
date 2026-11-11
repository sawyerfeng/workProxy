import AppKit
import CoreLocation
import SwiftUI
import UserNotifications

extension UNAuthorizationStatus {
    var permissionLabel: String {
        switch self {
        case .notDetermined: return "未申请"
        case .denied: return "未授权"
        case .authorized, .provisional: return "已授权"
        @unknown default: return "未知"
        }
    }
}

struct LocationPermissionRow: View {
    @ObservedObject var service: LocationService

    private var status: String {
        if !CLLocationManager.locationServicesEnabled() { return "系统定位已关闭" }
        switch service.authorizationStatus {
        case .notDetermined: return "未申请"
        case .denied: return "未授权"
        case .restricted: return "系统限制"
        case .authorizedAlways, .authorizedWhenInUse: return "已授权"
        @unknown default: return "未知"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label("定位", systemImage: "location")
                Text("用于读取 Wi-Fi 名称与匹配地点")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status).font(.caption).foregroundStyle(.secondary)
            Button(service.authorizationStatus == .notDetermined && CLLocationManager.locationServicesEnabled()
                   ? "允许定位" : "系统设置") {
                if service.authorizationStatus == .notDetermined && CLLocationManager.locationServicesEnabled() {
                    service.requestAuthorization()
                } else {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                }
            }
            .buttonStyle(.borderless)
        }
    }
}
