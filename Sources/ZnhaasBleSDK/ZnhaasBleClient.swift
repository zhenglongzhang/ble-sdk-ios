import CoreBluetooth
import Foundation

public typealias ZnhaasBleWriteCompletion = (Result<ZnhaasBleWriteResult, ZnhaasBleError>) -> Void
public typealias ZnhaasBleNotifyCompletion = (Result<Void, ZnhaasBleError>) -> Void
public typealias ZnhaasBleReadCompletion = (Result<Void, ZnhaasBleError>) -> Void

public final class ZnhaasBleClient: NSObject {
    public static let targetDeviceNamePrefix = "znhaas"
    public static let fixedServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    public static let fixedWriteCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    public static let fixedNotifyCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

    private struct PendingWrite {
        let requestId: String?
        let serviceUUID: CBUUID
        let characteristicUUID: CBUUID
        let data: Data
        let completion: ZnhaasBleWriteCompletion?
    }

    private struct PendingNotify {
        let serviceUUID: CBUUID
        let characteristicUUID: CBUUID
        let enable: Bool
        let completion: ZnhaasBleNotifyCompletion?
    }

    private struct PendingRead {
        let serviceUUID: CBUUID
        let characteristicUUID: CBUUID
        let completion: ZnhaasBleReadCompletion?
    }

    public weak var delegate: ZnhaasBleClientDelegate?

    public var currentState: CBManagerState {
        centralManager.state
    }

    public var isBluetoothEnabled: Bool {
        centralManager.state == .poweredOn
    }

    public var isScanning: Bool {
        centralManager.isScanning
    }

    public var scannedDevices: [ZnhaasBleDevice] {
        discoveredDevices.values.sorted { lhs, rhs in
            if lhs.displayName == rhs.displayName {
                return lhs.identifier.uuidString < rhs.identifier.uuidString
            }
            return lhs.displayName < rhs.displayName
        }
    }

    public var connectedDevice: ZnhaasBleDevice? {
        guard let peripheral = currentPeripheral else {
            return nil
        }
        return discoveredDevices[peripheral.identifier] ?? makeDevice(from: peripheral, advertisedName: nil, rssi: nil)
    }

    private let callbackQueue: DispatchQueue
    private let centralManager: CBCentralManager
    private var stopScanWorkItem: DispatchWorkItem?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var discoveredDevices: [UUID: ZnhaasBleDevice] = [:]
    private var currentPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var pendingWrites: [String: [PendingWrite]] = [:]
    private var pendingNotifyOperations: [String: PendingNotify] = [:]
    private var pendingReadOperations: [String: [PendingRead]] = [:]

    public init(
        delegate: ZnhaasBleClientDelegate? = nil,
        queue: DispatchQueue? = nil,
        restoreIdentifier: String? = nil
    ) {
        self.delegate = delegate
        self.callbackQueue = queue ?? DispatchQueue(label: "com.znhaas.sdk.ble")
        if let restoreIdentifier {
            self.centralManager = CBCentralManager(
                delegate: nil,
                queue: self.callbackQueue,
                options: [CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier]
            )
        } else {
            self.centralManager = CBCentralManager(delegate: nil, queue: self.callbackQueue)
        }
        super.init()
        self.centralManager.delegate = self
    }

    deinit {
        stopScanWorkItem?.cancel()
    }

    public static func isTargetDeviceName(_ deviceName: String?) -> Bool {
        ZnhaasBleDevice.isTargetDeviceName(deviceName)
    }

    public static func extractDisplayName(_ deviceName: String?) -> String {
        ZnhaasBleDevice.toDisplayName(deviceName)
    }

    public static func buildRequestId(action: ZnhaasRecordAction) -> String {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        return "req-\(timestamp)"
    }

    public static func buildRecordCommand(
        action: ZnhaasRecordAction,
        requestId: String,
        timestamp: Int64,
        extraFields: [String: String]? = nil
    ) -> String {
        var fields = [
            "2",
            "C",
            action.commandCode,
            action.code,
            sanitizeRecordValue(requestId),
            String(timestamp)
        ]
        if action == .queryStatus {
            fields.append(contentsOf: ["", "", ""])
        } else {
            fields.append(recordField(extraFields, keys: ["work_order", "workOrder", "work-order"]))
            fields.append(recordField(extraFields, keys: ["task_id", "taskId", "task-id"]))
            fields.append(recordField(extraFields, keys: ["device_id", "deviceId", "device-id"]))
        }
        while fields.count < 14 {
            fields.append("")
        }
        return fields.joined(separator: "|") + "\n"
    }

    private static func recordField(_ extraFields: [String: String]?, keys: [String]) -> String {
        guard let extraFields else {
            return ""
        }
        for key in keys {
            if let value = extraFields[key] {
                return sanitizeRecordValue(value)
            }
        }
        return ""
    }

    private static func sanitizeRecordValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    public func startScan(duration: TimeInterval = 10, allowDuplicates: Bool = false) {
        guard currentState == .poweredOn else {
            notifyScanFailed(ZnhaasBleError.from(state: currentState))
            return
        }

        stopScan(notifyStopped: false)
        discoveredPeripherals.removeAll()
        discoveredDevices.removeAll()

        let options = [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
        centralManager.scanForPeripherals(withServices: nil, options: options)
        emit { delegate in
            delegate.bleClientDidStartScan(self)
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.stopScan()
        }
        stopScanWorkItem = workItem
        callbackQueue.asyncAfter(deadline: .now() + max(duration, 0), execute: workItem)
    }

    public func stopScan() {
        stopScan(notifyStopped: true)
    }

    public func connect(_ device: ZnhaasBleDevice) {
        connect(identifier: device.identifier)
    }

    public func connect(identifier: UUID) {
        guard currentState == .poweredOn else {
            notifyFailure(ZnhaasBleError.from(state: currentState), device: nil)
            return
        }

        let peripheral = resolvePeripheral(identifier: identifier)
        guard let peripheral else {
            notifyFailure(.deviceNotFound(identifier), device: nil)
            return
        }

        stopScan(notifyStopped: false)
        currentPeripheral = peripheral
        writeCharacteristic = nil
        notifyCharacteristic = nil
        peripheral.delegate = self

        let device = makeDevice(from: peripheral, advertisedName: discoveredDevices[identifier]?.name, rssi: nil)
        emit { delegate in
            delegate.bleClient(self, isConnectingTo: device)
        }
        centralManager.connect(peripheral, options: nil)
    }

    public func disconnect() {
        guard let peripheral = currentPeripheral else {
            return
        }
        let device = discoveredDevices[peripheral.identifier] ?? makeDevice(from: peripheral, advertisedName: nil, rssi: nil)
        emit { delegate in
            delegate.bleClient(self, isDisconnectingFrom: device)
        }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    public func enableFixedNotification(completion: ZnhaasBleNotifyCompletion? = nil) {
        enableNotification(
            serviceUUID: Self.fixedServiceUUID,
            characteristicUUID: Self.fixedNotifyCharacteristicUUID,
            completion: completion
        )
    }

    public func enableFixedServiceNotifications(completion: ZnhaasBleNotifyCompletion? = nil) {
        guard let service = findService(uuid: Self.fixedServiceUUID) else {
            let error = ZnhaasBleError.serviceNotFound(Self.fixedServiceUUID)
            completeNotify(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        let characteristics = service.characteristics ?? []
        let notifiable = characteristics.filter { characteristic in
            characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
        }

        guard notifiable.isEmpty == false else {
            let error = ZnhaasBleError.notifyNotSupported(Self.fixedServiceUUID)
            completeNotify(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        notifiable.enumerated().forEach { index, characteristic in
            enableNotification(
                serviceUUID: Self.fixedServiceUUID,
                characteristicUUID: characteristic.uuid,
                completion: index == 0 ? completion : nil
            )
        }
    }

    public func disableFixedNotification(completion: ZnhaasBleNotifyCompletion? = nil) {
        disableNotification(
            serviceUUID: Self.fixedServiceUUID,
            characteristicUUID: Self.fixedNotifyCharacteristicUUID,
            completion: completion
        )
    }

    public func enableNotification(
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID,
        completion: ZnhaasBleNotifyCompletion? = nil
    ) {
        guard let peripheral = currentPeripheral, peripheral.state == .connected else {
            completeNotify(completion, with: .failure(.notConnected))
            notifyFailure(.notConnected, device: connectedDevice)
            return
        }
        guard let characteristic = findCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID) else {
            let error = ZnhaasBleError.characteristicNotFound(characteristicUUID)
            completeNotify(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }
        let supportsNotify = characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
        guard supportsNotify else {
            let error = ZnhaasBleError.notifyNotSupported(characteristicUUID)
            completeNotify(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        let key = buildKey(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        pendingNotifyOperations[key] = PendingNotify(
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            enable: true,
            completion: completion
        )
        peripheral.setNotifyValue(true, for: characteristic)
    }

    public func disableNotification(
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID,
        completion: ZnhaasBleNotifyCompletion? = nil
    ) {
        guard let peripheral = currentPeripheral, peripheral.state == .connected else {
            completeNotify(completion, with: .failure(.notConnected))
            notifyFailure(.notConnected, device: connectedDevice)
            return
        }
        guard let characteristic = findCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID) else {
            let error = ZnhaasBleError.characteristicNotFound(characteristicUUID)
            completeNotify(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        let key = buildKey(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        pendingNotifyOperations[key] = PendingNotify(
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            enable: false,
            completion: completion
        )
        peripheral.setNotifyValue(false, for: characteristic)
    }

    public func read(
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID,
        completion: ZnhaasBleReadCompletion? = nil
    ) {
        guard let peripheral = currentPeripheral, peripheral.state == .connected else {
            let error = ZnhaasBleError.notConnected
            completeRead(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        guard let characteristic = findCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID) else {
            let error = ZnhaasBleError.characteristicNotFound(characteristicUUID)
            completeRead(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        guard characteristic.properties.contains(.read) else {
            let error = ZnhaasBleError.readNotSupported(characteristicUUID)
            completeRead(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        let key = buildKey(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        pendingReadOperations[key, default: []].append(PendingRead(
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            completion: completion
        ))
        peripheral.readValue(for: characteristic)
    }

    public func readFixedReply(completion: ZnhaasBleReadCompletion? = nil) {
        read(
            serviceUUID: Self.fixedServiceUUID,
            characteristicUUID: Self.fixedNotifyCharacteristicUUID,
            completion: completion
        )
    }

    public func write(
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID,
        data: Data,
        requestId: String? = nil,
        completion: ZnhaasBleWriteCompletion? = nil
    ) {
        guard let peripheral = currentPeripheral, peripheral.state == .connected else {
            let error = ZnhaasBleError.notConnected
            completeWrite(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        guard let characteristic = findCharacteristic(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID) else {
            let error = ZnhaasBleError.characteristicNotFound(characteristicUUID)
            completeWrite(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        let supportsWriteWithResponse = characteristic.properties.contains(.write)
        let supportsWriteWithoutResponse = characteristic.properties.contains(.writeWithoutResponse)
        guard supportsWriteWithResponse || supportsWriteWithoutResponse else {
            let error = ZnhaasBleError.writeNotSupported(characteristicUUID)
            completeWrite(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return
        }

        let result = ZnhaasBleWriteResult(
            requestId: requestId,
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            data: data
        )

        if supportsWriteWithResponse {
            let key = buildKey(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
            pendingWrites[key, default: []].append(PendingWrite(
                requestId: requestId,
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID,
                data: data,
                completion: completion
            ))
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            return
        }

        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        completeWrite(completion, with: .success(result))
    }

    @discardableResult
    public func writeFixedASCIICommand(
        _ command: String,
        requestId: String? = nil,
        completion: ZnhaasBleWriteCompletion? = nil
    ) -> String? {
        guard let payload = command.data(using: .utf8) else {
            let error = ZnhaasBleError.writeFailed("Command cannot be encoded with UTF-8.")
            completeWrite(completion, with: .failure(error))
            notifyFailure(error, device: connectedDevice)
            return requestId
        }

        write(
            serviceUUID: Self.fixedServiceUUID,
            characteristicUUID: Self.fixedWriteCharacteristicUUID,
            data: payload,
            requestId: requestId,
            completion: completion
        )
        return requestId
    }

    @discardableResult
    public func startRecord(completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.startRecord, completion: completion)
    }

    @discardableResult
    public func startRecord(extraFields: [String: String], completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.startRecord, extraFields: extraFields, completion: completion)
    }

    @discardableResult
    public func stopRecord(completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.stopRecord, completion: completion)
    }

    @discardableResult
    public func stopRecord(extraFields: [String: String], completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.stopRecord, extraFields: extraFields, completion: completion)
    }

    @discardableResult
    public func queryRecordStatus(completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.queryStatus, completion: completion)
    }

    @discardableResult
    public func queryRecordStatus(extraFields: [String: String], completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.queryStatus, extraFields: extraFields, completion: completion)
    }

    @discardableResult
    public func disableVideoKey(completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.disableVideoKey, completion: completion)
    }

    @discardableResult
    public func disableVideoKey(extraFields: [String: String], completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.disableVideoKey, extraFields: extraFields, completion: completion)
    }

    @discardableResult
    public func enableVideoKey(completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.enableVideoKey, completion: completion)
    }

    @discardableResult
    public func enableVideoKey(extraFields: [String: String], completion: ZnhaasBleWriteCompletion? = nil) -> String {
        sendRecordAction(.enableVideoKey, extraFields: extraFields, completion: completion)
    }

    public func release() {
        stopScan(notifyStopped: false)
        stopScanWorkItem?.cancel()
        stopScanWorkItem = nil
        pendingWrites.removeAll()
        pendingNotifyOperations.removeAll()
        pendingReadOperations.removeAll()
        writeCharacteristic = nil
        notifyCharacteristic = nil
        if let peripheral = currentPeripheral, peripheral.state != .disconnected {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        currentPeripheral = nil
        discoveredDevices.removeAll()
        discoveredPeripherals.removeAll()
        delegate = nil
    }

    @discardableResult
    private func sendRecordAction(
        _ action: ZnhaasRecordAction,
        extraFields: [String: String]? = nil,
        completion: ZnhaasBleWriteCompletion? = nil
    ) -> String {
        let requestId = Self.buildRequestId(action: action)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let command = Self.buildRecordCommand(
            action: action,
            requestId: requestId,
            timestamp: timestamp,
            extraFields: extraFields
        )
        writeFixedASCIICommand(command, requestId: requestId, completion: completion)
        return requestId
    }

    private func stopScan(notifyStopped: Bool) {
        let wasScanning = centralManager.isScanning
        if wasScanning {
            centralManager.stopScan()
        }
        stopScanWorkItem?.cancel()
        stopScanWorkItem = nil

        if notifyStopped && wasScanning {
            let devices = scannedDevices
            emit { delegate in
                delegate.bleClient(self, didStopScan: devices)
            }
        }
    }

    private func resolvePeripheral(identifier: UUID) -> CBPeripheral? {
        if let peripheral = discoveredPeripherals[identifier] {
            return peripheral
        }
        return centralManager.retrievePeripherals(withIdentifiers: [identifier]).first
    }

    private func makeDevice(from peripheral: CBPeripheral, advertisedName: String?, rssi: NSNumber?) -> ZnhaasBleDevice {
        let knownDevice = discoveredDevices[peripheral.identifier]
        let resolvedName = advertisedName ?? peripheral.name ?? knownDevice?.name
        let resolvedRssi = rssi?.intValue ?? knownDevice?.rssi ?? 0
        let device = ZnhaasBleDevice(identifier: peripheral.identifier, name: resolvedName, rssi: resolvedRssi)
        discoveredDevices[peripheral.identifier] = device
        return device
    }

    private func findService(uuid: CBUUID) -> CBService? {
        currentPeripheral?.services?.first(where: { $0.uuid == uuid })
    }

    private func findCharacteristic(serviceUUID: CBUUID, characteristicUUID: CBUUID) -> CBCharacteristic? {
        guard let service = findService(uuid: serviceUUID) else {
            return nil
        }
        return service.characteristics?.first(where: { $0.uuid == characteristicUUID })
    }

    private func buildKey(serviceUUID: CBUUID, characteristicUUID: CBUUID) -> String {
        "\(serviceUUID.uuidString)#\(characteristicUUID.uuidString)"
    }

    private func emit(_ callback: @escaping (ZnhaasBleClientDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let delegate = self.delegate else {
                return
            }
            callback(delegate)
        }
    }

    private func completeWrite(
        _ completion: ZnhaasBleWriteCompletion?,
        with result: Result<ZnhaasBleWriteResult, ZnhaasBleError>
    ) {
        guard let completion else {
            return
        }
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func completeNotify(
        _ completion: ZnhaasBleNotifyCompletion?,
        with result: Result<Void, ZnhaasBleError>
    ) {
        guard let completion else {
            return
        }
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func completeRead(
        _ completion: ZnhaasBleReadCompletion?,
        with result: Result<Void, ZnhaasBleError>
    ) {
        guard let completion else {
            return
        }
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func notifyScanFailed(_ error: ZnhaasBleError) {
        emit { delegate in
            delegate.bleClient(self, didFailScan: error)
        }
    }

    private func notifyFailure(_ error: ZnhaasBleError, device: ZnhaasBleDevice?) {
        emit { delegate in
            delegate.bleClient(self, didFailWith: error, device: device)
        }
    }

    private func clearConnectionState() {
        pendingWrites.removeAll()
        pendingNotifyOperations.removeAll()
        pendingReadOperations.removeAll()
        writeCharacteristic = nil
        notifyCharacteristic = nil
    }
}

extension ZnhaasBleClient: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emit { delegate in
            delegate.bleClient(self, didUpdateState: central.state)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let resolvedName = advertisedName ?? peripheral.name
        guard Self.isTargetDeviceName(resolvedName) else {
            return
        }

        discoveredPeripherals[peripheral.identifier] = peripheral
        let device = makeDevice(from: peripheral, advertisedName: resolvedName, rssi: RSSI)
        emit { delegate in
            delegate.bleClient(self, didDiscover: device)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        currentPeripheral = peripheral
        peripheral.delegate = self
        let device = makeDevice(from: peripheral, advertisedName: nil, rssi: nil)
        emit { delegate in
            delegate.bleClient(self, didConnect: device)
        }
        peripheral.discoverServices([Self.fixedServiceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let device = discoveredDevices[peripheral.identifier] ?? makeDevice(from: peripheral, advertisedName: nil, rssi: nil)
        clearConnectionState()
        currentPeripheral = nil
        let reason = error?.localizedDescription ?? "Unknown reason."
        notifyFailure(.connectionFailed(reason), device: device)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let device = discoveredDevices[peripheral.identifier]
        clearConnectionState()
        if currentPeripheral?.identifier == peripheral.identifier {
            currentPeripheral = nil
        }
        emit { delegate in
            delegate.bleClient(self, didDisconnect: device, error: error)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            peripherals.forEach { peripheral in
                discoveredPeripherals[peripheral.identifier] = peripheral
                _ = makeDevice(from: peripheral, advertisedName: nil, rssi: nil)
            }
        }
    }
}

extension ZnhaasBleClient: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let device = discoveredDevices[peripheral.identifier] ?? makeDevice(from: peripheral, advertisedName: nil, rssi: nil)
        if let error {
            notifyFailure(.connectionFailed(error.localizedDescription), device: device)
            return
        }

        let services = peripheral.services ?? []
        emit { delegate in
            delegate.bleClient(self, didDiscoverServices: services, for: device)
        }

        guard let service = services.first(where: { $0.uuid == Self.fixedServiceUUID }) else {
            notifyFailure(.serviceNotFound(Self.fixedServiceUUID), device: device)
            return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let device = discoveredDevices[peripheral.identifier] ?? makeDevice(from: peripheral, advertisedName: nil, rssi: nil)
        if let error {
            notifyFailure(.connectionFailed(error.localizedDescription), device: device)
            return
        }

        let characteristics = service.characteristics ?? []
        writeCharacteristic = characteristics.first(where: { $0.uuid == Self.fixedWriteCharacteristicUUID })
        notifyCharacteristic = characteristics.first(where: { $0.uuid == Self.fixedNotifyCharacteristicUUID })

        emit { delegate in
            delegate.bleClient(self, didDiscoverCharacteristics: characteristics, for: service, device: device)
        }

        guard writeCharacteristic != nil else {
            notifyFailure(.characteristicNotFound(Self.fixedWriteCharacteristicUUID), device: device)
            return
        }

        emit { delegate in
            delegate.bleClient(self, didBecomeReady: device)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let serviceUUID = characteristic.service?.uuid ?? Self.fixedServiceUUID
        let characteristicUUID = characteristic.uuid
        let key = buildKey(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        let pending = pendingNotifyOperations.removeValue(forKey: key)

        if let error {
            let wrappedError = ZnhaasBleError.notifyFailed(error.localizedDescription)
            completeNotify(pending?.completion, with: .failure(wrappedError))
            notifyFailure(wrappedError, device: connectedDevice)
            return
        }

        if characteristic.isNotifying {
            completeNotify(pending?.completion, with: .success(()))
            emit { delegate in
                delegate.bleClient(self, didEnableNotifyFor: serviceUUID, characteristicUUID: characteristicUUID)
            }
        } else {
            completeNotify(pending?.completion, with: .success(()))
            emit { delegate in
                delegate.bleClient(self, didDisableNotifyFor: serviceUUID, characteristicUUID: characteristicUUID)
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let serviceUUID = characteristic.service?.uuid ?? Self.fixedServiceUUID
        let characteristicUUID = characteristic.uuid
        let key = buildKey(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        var readQueue = pendingReadOperations[key] ?? []
        let pendingRead = readQueue.isEmpty ? nil : readQueue.removeFirst()
        pendingReadOperations[key] = readQueue.isEmpty ? nil : readQueue

        if let error {
            let wrappedError = pendingRead == nil
                ? ZnhaasBleError.notifyFailed(error.localizedDescription)
                : ZnhaasBleError.readFailed(error.localizedDescription)
            completeRead(pendingRead?.completion, with: .failure(wrappedError))
            notifyFailure(wrappedError, device: connectedDevice)
            return
        }

        let value = characteristic.value ?? Data()
        let stringValue = String(data: value, encoding: .utf8)
        let hexValue = value.hexString

        emit { delegate in
            delegate.bleClient(
                self,
                didReceive: value,
                stringValue: stringValue,
                hexValue: hexValue,
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID
            )
        }
        completeRead(pendingRead?.completion, with: .success(()))
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let serviceUUID = characteristic.service?.uuid ?? Self.fixedServiceUUID
        let characteristicUUID = characteristic.uuid
        let key = buildKey(serviceUUID: serviceUUID, characteristicUUID: characteristicUUID)
        var queue = pendingWrites[key] ?? []
        let pending = queue.isEmpty ? nil : queue.removeFirst()
        pendingWrites[key] = queue.isEmpty ? nil : queue

        if let error {
            let wrappedError = ZnhaasBleError.writeFailed(error.localizedDescription)
            completeWrite(pending?.completion, with: .failure(wrappedError))
            notifyFailure(wrappedError, device: connectedDevice)
            return
        }

        if let pending {
            let result = ZnhaasBleWriteResult(
                requestId: pending.requestId,
                serviceUUID: pending.serviceUUID,
                characteristicUUID: pending.characteristicUUID,
                data: pending.data
            )
            completeWrite(pending.completion, with: .success(result))
        }
    }
}
