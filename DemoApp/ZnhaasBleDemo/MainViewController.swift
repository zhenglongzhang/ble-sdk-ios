import CoreBluetooth
import UIKit

final class MainViewController: UIViewController {
    private let bleClient = ZnhaasBleClient()
    private var devices: [ZnhaasBleDevice] = []
    private var selectedDevice: ZnhaasBleDevice?

    private let stateLabel = UILabel()
    private let connectedLabel = UILabel()
    private let scanButton = UIButton(type: .system)
    private let stopScanButton = UIButton(type: .system)
    private let disconnectButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let logTextView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        bleClient.delegate = self
        setupView()
        updateBluetoothState(bleClient.currentState)
        appendLog("Demo ready. Only scans znhaas BLE devices.")
    }

    deinit {
        bleClient.release()
    }

    private func setupView() {
        title = "Znhaas BLE Demo"
        view.backgroundColor = ColorPalette.background
        navigationController?.navigationBar.prefersLargeTitles = true

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])

        contentStack.addArrangedSubview(makeStatusCard())
        contentStack.addArrangedSubview(makeDevicesCard())
        contentStack.addArrangedSubview(makeCommandCard())
        contentStack.addArrangedSubview(makeLogCard())
    }

    private func makeStatusCard() -> UIView {
        let card = makeCard()

        let titleLabel = makeSectionTitle("Bluetooth")
        stateLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        stateLabel.textColor = ColorPalette.secondaryText
        stateLabel.numberOfLines = 0

        connectedLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        connectedLabel.textColor = ColorPalette.secondaryText
        connectedLabel.numberOfLines = 0
        connectedLabel.text = "Connected: none"

        configurePrimaryButton(scanButton, title: "Start Scan")
        scanButton.addTarget(self, action: #selector(startScanTapped), for: .touchUpInside)

        configureSecondaryButton(stopScanButton, title: "Stop Scan")
        stopScanButton.addTarget(self, action: #selector(stopScanTapped), for: .touchUpInside)

        configureSecondaryButton(disconnectButton, title: "Disconnect")
        disconnectButton.addTarget(self, action: #selector(disconnectTapped), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [scanButton, stopScanButton, disconnectButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, stateLabel, connectedLabel, buttonStack])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func makeDevicesCard() -> UIView {
        let card = makeCard()

        let titleLabel = makeSectionTitle("Devices")
        let hintLabel = UILabel()
        hintLabel.font = UIFont.systemFont(ofSize: 12)
        hintLabel.textColor = ColorPalette.secondaryText
        hintLabel.numberOfLines = 0
        hintLabel.text = "Tap a device to connect. Display name strips znhaas prefix, for example znhaas_23070401 -> 23070401."

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(DeviceCell.self, forCellReuseIdentifier: DeviceCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 68
        tableView.tableFooterView = UIView()
        tableView.backgroundColor = .clear
        tableView.layer.cornerRadius = 12
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = ColorPalette.border.cgColor

        let stack = UIStackView(arrangedSubviews: [titleLabel, hintLabel, tableView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            tableView.heightAnchor.constraint(equalToConstant: 240)
        ])

        return card
    }

    private func makeCommandCard() -> UIView {
        let card = makeCard()

        let titleLabel = makeSectionTitle("Commands")
        let hintLabel = UILabel()
        hintLabel.font = UIFont.systemFont(ofSize: 12)
        hintLabel.textColor = ColorPalette.secondaryText
        hintLabel.numberOfLines = 0
        hintLabel.text = "After connection is ready, the demo will auto-enable fixed notify UUID 6E400003..."

        let startButton = makeCommandButton(title: "Start Record", action: #selector(startRecordTapped))
        let stopButton = makeCommandButton(title: "Stop Record", action: #selector(stopRecordTapped))
        let queryButton = makeCommandButton(title: "Query Status", action: #selector(queryStatusTapped))
        let disableButton = makeCommandButton(title: "Disable Video Key", action: #selector(disableVideoKeyTapped))
        let enableButton = makeCommandButton(title: "Enable Video Key", action: #selector(enableVideoKeyTapped))

        let row1 = UIStackView(arrangedSubviews: [startButton, stopButton])
        row1.axis = .horizontal
        row1.spacing = 12
        row1.distribution = .fillEqually

        let row2 = UIStackView(arrangedSubviews: [queryButton, disableButton])
        row2.axis = .horizontal
        row2.spacing = 12
        row2.distribution = .fillEqually

        let row3 = UIStackView(arrangedSubviews: [enableButton, UIView()])
        row3.axis = .horizontal
        row3.spacing = 12
        row3.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, hintLabel, row1, row2, row3])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func makeLogCard() -> UIView {
        let card = makeCard()

        let titleLabel = makeSectionTitle("Runtime Log")
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logTextView.isEditable = false
        logTextView.backgroundColor = ColorPalette.logBackground
        logTextView.textColor = ColorPalette.logText
        logTextView.font = UIFont(name: "Menlo", size: 12) ?? UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        logTextView.layer.cornerRadius = 12
        logTextView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)

        let stack = UIStackView(arrangedSubviews: [titleLabel, logTextView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            logTextView.heightAnchor.constraint(equalToConstant: 220)
        ])

        return card
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = ColorPalette.cardBackground
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = ColorPalette.border.cgColor
        return card
    }

    private func makeSectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        label.textColor = ColorPalette.primaryText
        label.text = title
        return label
    }

    private func configurePrimaryButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = ColorPalette.primaryButton
        button.layer.cornerRadius = 12
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    private func configureSecondaryButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(ColorPalette.primaryButton, for: .normal)
        button.backgroundColor = ColorPalette.secondaryButton
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = ColorPalette.primaryButton.cgColor
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    private func makeCommandButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        configureSecondaryButton(button, title: title)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func updateBluetoothState(_ state: CBManagerState) {
        runOnMain {
            self.stateLabel.text = "State: \(self.describe(state: state))"
        }
    }

    private func updateConnectedDevice(_ device: ZnhaasBleDevice?) {
        runOnMain {
            if let device {
                self.connectedLabel.text = "Connected: \(device.displayName) (\(device.identifier.uuidString))"
            } else {
                self.connectedLabel.text = "Connected: none"
            }
        }
    }

    private func appendLog(_ message: String) {
        runOnMain {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let entry = "[\(formatter.string(from: Date()))] \(message)\n"
            self.logTextView.text = (self.logTextView.text ?? "") + entry
            let length = self.logTextView.text.count
            if length > 0 {
                self.logTextView.scrollRangeToVisible(NSRange(location: length - 1, length: 1))
            }
        }
    }

    private func reloadDevices() {
        runOnMain {
            self.devices = self.bleClient.scannedDevices.sorted { lhs, rhs in
                if lhs.displayName == rhs.displayName {
                    return lhs.identifier.uuidString < rhs.identifier.uuidString
                }
                return lhs.displayName < rhs.displayName
            }
            self.tableView.reloadData()
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func connect(to device: ZnhaasBleDevice) {
        selectedDevice = device
        updateConnectedDevice(nil)
        appendLog("Connecting to \(device.displayName) \(device.identifier.uuidString)")
        bleClient.connect(device)
    }

    private func sendAction(_ title: String, perform: (@escaping ZnhaasBleWriteCompletion) -> String) {
        let requestId = perform { [weak self] result in
            switch result {
            case .success(let writeResult):
                self?.appendLog("\(title) success, requestId=\(writeResult.requestId ?? "-"), payload=\(writeResult.stringValue ?? "")")
            case .failure(let error):
                self?.appendLog("\(title) failed: \(error.localizedDescription)")
            }
        }
        appendLog("\(title) dispatched, requestId=\(requestId)")
    }

    private func describe(state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported"
        case .unauthorized:
            return "unauthorized"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        @unknown default:
            return "unknown(\(state.rawValue))"
        }
    }

    @objc
    private func startScanTapped() {
        devices.removeAll()
        tableView.reloadData()
        appendLog("Start scanning znhaas devices for 12 seconds...")
        bleClient.startScan(duration: 12)
    }

    @objc
    private func stopScanTapped() {
        bleClient.stopScan()
        appendLog("Stop scan requested.")
    }

    @objc
    private func disconnectTapped() {
        bleClient.disconnect()
        appendLog("Disconnect requested.")
    }

    @objc
    private func startRecordTapped() {
        sendAction("Start record") { [weak self] completion in
            guard let self else { return "" }
            return self.bleClient.startRecord(completion: completion)
        }
    }

    @objc
    private func stopRecordTapped() {
        sendAction("Stop record") { [weak self] completion in
            guard let self else { return "" }
            return self.bleClient.stopRecord(completion: completion)
        }
    }

    @objc
    private func queryStatusTapped() {
        sendAction("Query status") { [weak self] completion in
            guard let self else { return "" }
            return self.bleClient.queryRecordStatus(completion: completion)
        }
    }

    @objc
    private func disableVideoKeyTapped() {
        sendAction("Disable video key") { [weak self] completion in
            guard let self else { return "" }
            return self.bleClient.disableVideoKey(completion: completion)
        }
    }

    @objc
    private func enableVideoKeyTapped() {
        sendAction("Enable video key") { [weak self] completion in
            guard let self else { return "" }
            return self.bleClient.enableVideoKey(completion: completion)
        }
    }
}

extension MainViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        devices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DeviceCell.reuseIdentifier, for: indexPath)
        guard let deviceCell = cell as? DeviceCell else {
            return cell
        }

        let device = devices[indexPath.row]
        deviceCell.textLabel?.text = device.displayName
        deviceCell.detailTextLabel?.text = "\(device.identifier.uuidString)\nRSSI: \(device.rssi)"
        deviceCell.accessoryType = selectedDevice?.identifier == device.identifier ? .checkmark : .disclosureIndicator
        return deviceCell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let device = devices[indexPath.row]
        connect(to: device)
        tableView.reloadData()
    }
}

extension MainViewController: ZnhaasBleClientDelegate {
    func bleClient(_ client: ZnhaasBleClient, didUpdateState state: CBManagerState) {
        updateBluetoothState(state)
        appendLog("Bluetooth state changed: \(describe(state: state))")
    }

    func bleClientDidStartScan(_ client: ZnhaasBleClient) {
        appendLog("Scan started.")
    }

    func bleClient(_ client: ZnhaasBleClient, didDiscover device: ZnhaasBleDevice) {
        reloadDevices()
        appendLog("Discovered: \(device.displayName) rssi=\(device.rssi)")
    }

    func bleClient(_ client: ZnhaasBleClient, didStopScan devices: [ZnhaasBleDevice]) {
        reloadDevices()
        appendLog("Scan stopped. matched devices=\(devices.count)")
    }

    func bleClient(_ client: ZnhaasBleClient, didFailScan error: ZnhaasBleError) {
        appendLog("Scan failed: \(error.localizedDescription)")
    }

    func bleClient(_ client: ZnhaasBleClient, isConnectingTo device: ZnhaasBleDevice) {
        appendLog("Connecting: \(device.displayName)")
    }

    func bleClient(_ client: ZnhaasBleClient, didConnect device: ZnhaasBleDevice) {
        appendLog("Connected: \(device.displayName)")
    }

    func bleClient(_ client: ZnhaasBleClient, didDiscoverServices services: [CBService], for device: ZnhaasBleDevice) {
        appendLog("Services discovered for \(device.displayName): \(services.count)")
    }

    func bleClient(_ client: ZnhaasBleClient, didBecomeReady device: ZnhaasBleDevice) {
        selectedDevice = device
        updateConnectedDevice(device)
        tableView.reloadData()
        appendLog("Device ready: \(device.displayName). Enabling fixed notify...")
        client.enableFixedNotification { [weak self] result in
            switch result {
            case .success:
                self?.appendLog("Fixed notify enabled.")
            case .failure(let error):
                self?.appendLog("Enable notify failed: \(error.localizedDescription)")
            }
        }
    }

    func bleClient(_ client: ZnhaasBleClient, didDisconnect device: ZnhaasBleDevice?, error: Error?) {
        updateConnectedDevice(nil)
        if let device {
            appendLog("Disconnected: \(device.displayName)")
        } else {
            appendLog("Disconnected.")
        }
        if let error {
            appendLog("Disconnect error: \(error.localizedDescription)")
        }
    }

    func bleClient(_ client: ZnhaasBleClient, didEnableNotifyFor serviceUUID: CBUUID, characteristicUUID: CBUUID) {
        appendLog("Notify enabled: \(serviceUUID.uuidString) / \(characteristicUUID.uuidString)")
    }

    func bleClient(_ client: ZnhaasBleClient, didDisableNotifyFor serviceUUID: CBUUID, characteristicUUID: CBUUID) {
        appendLog("Notify disabled: \(serviceUUID.uuidString) / \(characteristicUUID.uuidString)")
    }

    func bleClient(
        _ client: ZnhaasBleClient,
        didReceive value: Data,
        stringValue: String?,
        hexValue: String,
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID
    ) {
        appendLog("Notify received: string=\(stringValue ?? "") hex=\(hexValue)")
    }

    func bleClient(_ client: ZnhaasBleClient, didFailWith error: ZnhaasBleError, device: ZnhaasBleDevice?) {
        appendLog("BLE error: \(error.localizedDescription)")
    }
}

private enum ColorPalette {
    static let background = dynamicColor(light: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1), dark: .black)
    static let cardBackground = dynamicColor(light: .white, dark: UIColor(white: 0.12, alpha: 1))
    static let primaryText = dynamicColor(light: .black, dark: .white)
    static let secondaryText = dynamicColor(light: .darkGray, dark: UIColor(white: 0.8, alpha: 1))
    static let border = dynamicColor(light: UIColor(white: 0.85, alpha: 1), dark: UIColor(white: 0.25, alpha: 1))
    static let primaryButton = UIColor(red: 0.10, green: 0.53, blue: 0.95, alpha: 1)
    static let secondaryButton = dynamicColor(light: UIColor(red: 0.93, green: 0.97, blue: 1.0, alpha: 1), dark: UIColor(red: 0.14, green: 0.20, blue: 0.28, alpha: 1))
    static let logBackground = dynamicColor(light: UIColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1), dark: UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1))
    static let logText = UIColor(red: 0.75, green: 0.94, blue: 0.81, alpha: 1)

    private static func dynamicColor(light: UIColor, dark: UIColor) -> UIColor {
        if #available(iOS 13.0, *) {
            return UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? dark : light
            }
        }
        return light
    }
}
