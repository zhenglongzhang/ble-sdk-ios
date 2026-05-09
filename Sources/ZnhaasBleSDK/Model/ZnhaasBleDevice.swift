import Foundation

public struct ZnhaasBleDevice: Hashable, Identifiable {
    private static let targetPrefix = "znhaas"

    public let identifier: UUID
    public let name: String?
    public let displayName: String
    public let rssi: Int
    public let lastSeenAt: Date

    public var id: UUID {
        identifier
    }

    public init(
        identifier: UUID,
        name: String?,
        rssi: Int,
        lastSeenAt: Date = Date()
    ) {
        self.identifier = identifier
        self.name = name
        self.displayName = Self.toDisplayName(name)
        self.rssi = rssi
        self.lastSeenAt = lastSeenAt
    }

    public var isZnhaasDevice: Bool {
        Self.isTargetDeviceName(name)
    }

    public static func isTargetDeviceName(_ deviceName: String?) -> Bool {
        guard let trimmed = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return false
        }
        return trimmed.lowercased().hasPrefix(targetPrefix)
    }

    public static func toDisplayName(_ deviceName: String?) -> String {
        guard let trimmed = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return "Unknown device"
        }

        guard isTargetDeviceName(trimmed) else {
            return trimmed
        }

        var suffix = String(trimmed.dropFirst(targetPrefix.count))
        if suffix.hasPrefix("_") || suffix.hasPrefix("-") {
            suffix.removeFirst()
        }
        return suffix.isEmpty ? trimmed : suffix
    }
}

