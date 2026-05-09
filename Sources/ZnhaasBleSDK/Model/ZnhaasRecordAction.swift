import Foundation

public enum ZnhaasRecordAction: String, CaseIterable {
    case startRecord = "1"
    case stopRecord = "0"
    case queryStatus = "2"
    case disableVideoKey = "3"
    case enableVideoKey = "4"

    public var code: String {
        rawValue
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

