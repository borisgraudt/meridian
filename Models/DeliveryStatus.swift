import Foundation

enum DeliveryStatus: String, Codable {
    case sending
    case sent
    case delivered
    case read
    case failed

    var icon: String {
        switch self {
        case .sending:   return "clock"
        case .sent:      return "checkmark"
        case .delivered: return "checkmark.2"
        case .read:      return "checkmark.2"
        case .failed:    return "exclamationmark.circle"
        }
    }

    /// Blue tint for "read", default for others.
    var isRead: Bool { self == .read }
}
