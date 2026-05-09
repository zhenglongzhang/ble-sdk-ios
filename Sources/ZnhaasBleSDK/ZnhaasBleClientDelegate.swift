import CoreBluetooth
import Foundation

public protocol ZnhaasBleClientDelegate: AnyObject {
    func bleClient(_ client: ZnhaasBleClient, didUpdateState state: CBManagerState)
    func bleClientDidStartScan(_ client: ZnhaasBleClient)
    func bleClient(_ client: ZnhaasBleClient, didDiscover device: ZnhaasBleDevice)
    func bleClient(_ client: ZnhaasBleClient, didStopScan devices: [ZnhaasBleDevice])
    func bleClient(_ client: ZnhaasBleClient, didFailScan error: ZnhaasBleError)
    func bleClient(_ client: ZnhaasBleClient, isConnectingTo device: ZnhaasBleDevice)
    func bleClient(_ client: ZnhaasBleClient, didConnect device: ZnhaasBleDevice)
    func bleClient(_ client: ZnhaasBleClient, didDiscoverServices services: [CBService], for device: ZnhaasBleDevice)
    func bleClient(_ client: ZnhaasBleClient, didBecomeReady device: ZnhaasBleDevice)
    func bleClient(_ client: ZnhaasBleClient, isDisconnectingFrom device: ZnhaasBleDevice)
    func bleClient(_ client: ZnhaasBleClient, didDisconnect device: ZnhaasBleDevice?, error: Error?)
    func bleClient(_ client: ZnhaasBleClient, didEnableNotifyFor serviceUUID: CBUUID, characteristicUUID: CBUUID)
    func bleClient(_ client: ZnhaasBleClient, didDisableNotifyFor serviceUUID: CBUUID, characteristicUUID: CBUUID)
    func bleClient(
        _ client: ZnhaasBleClient,
        didReceive value: Data,
        stringValue: String?,
        hexValue: String,
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID
    )
    func bleClient(_ client: ZnhaasBleClient, didFailWith error: ZnhaasBleError, device: ZnhaasBleDevice?)
}

public extension ZnhaasBleClientDelegate {
    func bleClient(_ client: ZnhaasBleClient, didUpdateState state: CBManagerState) {}
    func bleClientDidStartScan(_ client: ZnhaasBleClient) {}
    func bleClient(_ client: ZnhaasBleClient, didDiscover device: ZnhaasBleDevice) {}
    func bleClient(_ client: ZnhaasBleClient, didStopScan devices: [ZnhaasBleDevice]) {}
    func bleClient(_ client: ZnhaasBleClient, didFailScan error: ZnhaasBleError) {}
    func bleClient(_ client: ZnhaasBleClient, isConnectingTo device: ZnhaasBleDevice) {}
    func bleClient(_ client: ZnhaasBleClient, didConnect device: ZnhaasBleDevice) {}
    func bleClient(_ client: ZnhaasBleClient, didDiscoverServices services: [CBService], for device: ZnhaasBleDevice) {}
    func bleClient(_ client: ZnhaasBleClient, didBecomeReady device: ZnhaasBleDevice) {}
    func bleClient(_ client: ZnhaasBleClient, isDisconnectingFrom device: ZnhaasBleDevice) {}
    func bleClient(_ client: ZnhaasBleClient, didDisconnect device: ZnhaasBleDevice?, error: Error?) {}
    func bleClient(_ client: ZnhaasBleClient, didEnableNotifyFor serviceUUID: CBUUID, characteristicUUID: CBUUID) {}
    func bleClient(_ client: ZnhaasBleClient, didDisableNotifyFor serviceUUID: CBUUID, characteristicUUID: CBUUID) {}
    func bleClient(
        _ client: ZnhaasBleClient,
        didReceive value: Data,
        stringValue: String?,
        hexValue: String,
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID
    ) {}
    func bleClient(_ client: ZnhaasBleClient, didFailWith error: ZnhaasBleError, device: ZnhaasBleDevice?) {}
}

