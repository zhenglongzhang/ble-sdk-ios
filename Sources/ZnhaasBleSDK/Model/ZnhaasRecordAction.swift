import Foundation

public enum ZnhaasRecordAction: CaseIterable {
    case startRecord
    case stopRecord
    case queryStatus
    case disableVideoKey
    case enableVideoKey

    public var commandCode: String {
        switch self {
        case .queryStatus:
            return "1"
        default:
            return "0"
        }
    }

    public var code: String {
        switch self {
        case .stopRecord:
            return "0"
        case .startRecord, .disableVideoKey:
            return "1"
        case .enableVideoKey:
            return "2"
        case .queryStatus:
            return "3"
        }
    }

    public var title: String {
        switch self {
        case .startRecord:
            return "Start Record"
        case .stopRecord:
            return "Stop Record"
        case .queryStatus:
            return "Query Status"
        case .disableVideoKey:
            return "Disable Video Key"
        case .enableVideoKey:
            return "Enable Video Key"
        }
    }
}
