import CoreBluetooth
import Foundation
import UIKit
import ZnhaasBleSDK

final class ExampleViewController: UIViewController {
    private let bleClient = ZnhaasBleClient()
    private var devices: [ZnhaasBleDevice] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        bleClient.delegate = self
    }

    @IBAction func scanTapped(_ sender: UIButton) {
        bleClient.startScan(duration: 12)
    }

    @IBAction func disconnectTapped(_ sender: UIButton) {
        bleClient.disconnect()
    }

    @IBAction func startRecordTapped(_ sender: UIButton) {
        bleClient.disableVideoKey(extraFields: [
            "work_order": "WO-20250122",
            "task_id": "TASK-01",
            "device_id": "31011500991325140052"
        ]) { result in
            switch result {
            case .success(let writeResult):
                print("start record and disable key success: \(writeResult.stringValue ?? "")")
            case .failure(let error):
                print("start record and disable key failed: \(error.localizedDescription)")
            }
        }
    }

    @IBAction func stopRecordTapped(_ sender: UIButton) {
        bleClient.stopRecord(completion: nil)
    }

    @IBAction func queryStatusTapped(_ sender: UIButton) {
        bleClient.queryRecordStatus(completion: nil)
    }

    @IBAction func disableVideoKeyTapped(_ sender: UIButton) {
        bleClient.disableVideoKey(completion: nil)
    }

    @IBAction func enableVideoKeyTapped(_ sender: UIButton) {
        bleClient.enableVideoKey(completion: nil)
    }
}

extension ExampleViewController: ZnhaasBleClientDelegate {
    func bleClient(_ client: ZnhaasBleClient, didUpdateState state: CBManagerState) {
        print("Bluetooth state changed: \(state.rawValue)")
    }

    func bleClient(_ client: ZnhaasBleClient, didDiscover device: ZnhaasBleDevice) {
        if devices.contains(device) == false {
            devices.append(device)
        }
        if let first = devices.first {
            client.connect(first)
        }
    }

    func bleClient(_ client: ZnhaasBleClient, didBecomeReady device: ZnhaasBleDevice) {
        client.enableFixedServiceNotifications { result in
            print("reply listener result: \(result)")
        }
    }

    func bleClient(
        _ client: ZnhaasBleClient,
        didReceive value: Data,
        stringValue: String?,
        hexValue: String,
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID
    ) {
        let ascii = stringValue ?? ""
        if ascii.hasPrefix("2|R|") {
            print("device v2 response: \(ascii)")
        } else {
            print("device reply: \(ascii)")
        }
        print("reply hex: \(hexValue)")
    }

    func bleClient(_ client: ZnhaasBleClient, didFailWith error: ZnhaasBleError, device: ZnhaasBleDevice?) {
        print("BLE error: \(error.localizedDescription)")
    }
}
