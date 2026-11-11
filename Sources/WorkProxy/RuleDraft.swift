import Foundation
import WorkProxyCore

// MARK: - Rule draft

enum RuleNetworkKind: String, CaseIterable, Hashable {
    case wifi
    case wired
}

struct RuleDraft {
    var name = ""
    var networkKind: RuleNetworkKind = .wifi
    var ssid = ""
    var interfaceName = ""
    var action: ProxyAction = .on
    var enabled = true
    var usePlace = false
    var placeLabel = ""
    var placeAddress: String?
    var latitude = 0.0
    var longitude = 0.0
    var radius = 500.0
    var hasPlaceCoordinates = false

    init(rule: Rule?, currentNetwork: NetworkIdentity?) {
        guard let rule else {
            if let network = currentNetwork {
                switch network.kind {
                case .wifi:
                    networkKind = .wifi
                    ssid = network.ssid ?? ""
                case .wired:
                    networkKind = .wired
                    interfaceName = network.interfaceName
                case .other:
                    break
                }
            }
            return
        }
        name = rule.name
        action = rule.action
        enabled = rule.enabled
        switch rule.network {
        case let .wifi(value):
            networkKind = .wifi
            ssid = value
        case let .wired(value):
            networkKind = .wired
            interfaceName = value
        }
        if let place = rule.place {
            usePlace = true
            placeLabel = place.label
            placeAddress = place.address
            latitude = place.latitude
            longitude = place.longitude
            radius = place.radiusMeters
            hasPlaceCoordinates = true
        }
    }

    func makeRule(id: UUID) -> Rule? {
        let network: RuleNetwork
        switch networkKind {
        case .wifi:
            let value = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            network = .wifi(ssid: value)
        case .wired:
            guard !interfaceName.isEmpty else { return nil }
            network = .wired(interfaceName: interfaceName)
        }

        let place: PlaceCondition?
        if usePlace {
            guard hasPlaceCoordinates else { return nil }
            place = PlaceCondition(
                label: placeLabel.isEmpty ? "地点" : placeLabel,
                address: placeAddress,
                latitude: latitude,
                longitude: longitude,
                radiusMeters: radius
            )
        } else {
            place = nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "\(network.displayName) · \(action.displayName)" : trimmedName
        return Rule(id: id, name: resolvedName, network: network,
                    place: place, action: action, enabled: enabled)
    }
}

