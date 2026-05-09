import CoreBluetooth
import Foundation

public struct ZnhaasBleWriteResult {
    public let requestId: String?
    public let serviceUUID: CBUUID
    public let characteristicUUID: CBUUID
    public let data: Data
    public let hexValue: String
    public let stringValue: String?

    public init(
        requestId: String?,
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID,
        data: Data
    ) {
        self.requestId = requestId
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.data = data
        self.hexValue = data.hexString
        self.stringValue = String(data: data, encoding: .utf8)
    }
}

