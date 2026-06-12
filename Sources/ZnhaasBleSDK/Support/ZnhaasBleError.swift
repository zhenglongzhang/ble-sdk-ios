import CoreBluetooth
import Foundation

public enum ZnhaasBleError: LocalizedError {
    case bluetoothUnavailable
    case bluetoothUnsupported
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case bluetoothResetting
    case scanFailed(String)
    case invalidDeviceIdentifier(UUID)
    case deviceNotFound(UUID)
    case notConnected
    case serviceNotFound(CBUUID)
    case characteristicNotFound(CBUUID)
    case notifyNotSupported(CBUUID)
    case readNotSupported(CBUUID)
    case writeNotSupported(CBUUID)
    case connectionFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case notifyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth state is unavailable."
        case .bluetoothUnsupported:
            return "Bluetooth LE is not supported on this device."
        case .bluetoothUnauthorized:
            return "Bluetooth permission is not authorized."
        case .bluetoothPoweredOff:
            return "Bluetooth is powered off."
        case .bluetoothResetting:
            return "Bluetooth is resetting."
        case .scanFailed(let reason):
            return "Scan failed: \(reason)"
        case .invalidDeviceIdentifier(let identifier):
            return "Invalid device identifier: \(identifier.uuidString)"
        case .deviceNotFound(let identifier):
            return "Device was not found: \(identifier.uuidString)"
        case .notConnected:
            return "No BLE device is connected."
        case .serviceNotFound(let uuid):
            return "Service was not found: \(uuid.uuidString)"
        case .characteristicNotFound(let uuid):
            return "Characteristic was not found: \(uuid.uuidString)"
        case .notifyNotSupported(let uuid):
            return "Characteristic does not support notify: \(uuid.uuidString)"
        case .readNotSupported(let uuid):
            return "Characteristic does not support read: \(uuid.uuidString)"
        case .writeNotSupported(let uuid):
            return "Characteristic does not support write: \(uuid.uuidString)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .writeFailed(let reason):
            return "Write failed: \(reason)"
        case .readFailed(let reason):
            return "Read failed: \(reason)"
        case .notifyFailed(let reason):
            return "Notify failed: \(reason)"
        }
    }

    static func from(state: CBManagerState) -> ZnhaasBleError {
        switch state {
        case .unsupported:
            return .bluetoothUnsupported
        case .unauthorized:
            return .bluetoothUnauthorized
        case .poweredOff:
            return .bluetoothPoweredOff
        case .resetting:
            return .bluetoothResetting
        case .poweredOn:
            return .bluetoothUnavailable
        case .unknown:
            return .bluetoothUnavailable
        @unknown default:
            return .bluetoothUnavailable
        }
    }
}
