import CoreBluetooth
import AVFoundation
import SystemConfiguration
import UIKit
import WebKit

final class MainViewController: UIViewController {
    private let bridgeName = "ZnhaasBleBridge"
    private let appBridgeName = "ZnhaasAppBridge"
    private var bleClient: ZnhaasBleClient?
    private var devices: [ZnhaasBleDevice] = []
    private var fixedReplySupportsRead = false
    private var pendingReadFallback = false
    private var enabledReplyCharacteristicUUIDs: Set<String> = []
    private var webView: WKWebView!
    private var mainWebViewRecoveryAttempts = 0
    private var mainWebViewActiveRecoveryAttempts = 0
    private var mainWebViewDidFinishInitialLoad = false
    private var pendingScanCodeRequestId: String?
    private var pendingTakePhotoRequestId: String?
    private var pendingTakePhotoMaxWidth: CGFloat = 1600
    private var pendingTakePhotoQuality: CGFloat = 0.8

    override func viewDidLoad() {
        super.viewDidLoad()
        title = configuredDisplayName()
        view.backgroundColor = .white
        setupWebView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        loadConfiguredEntry()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: bridgeName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: appBridgeName)
        bleClient?.release()
    }

    private func ensureBleClient() -> ZnhaasBleClient {
        if let bleClient {
            return bleClient
        }
        let client = ZnhaasBleClient()
        client.delegate = self
        bleClient = client
        return client
    }

    private func setupWebView() {
        let userContentController = WKUserContentController()
        userContentController.add(self, name: bridgeName)
        userContentController.add(self, name: appBridgeName)
        userContentController.addUserScript(WKUserScript(
            source: bridgeBootstrapScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        userContentController.addUserScript(WKUserScript(
            source: h5ViewportLockScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        webView = WKWebView(frame: .zero, configuration: configuration)
        configureH5WebView(webView)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            webView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        ])
    }

    private func loadConfiguredEntry() {
        let webURLString = configuredWebURLString()
        if shouldLoadBundledTestPage(webURLString) {
            loadBundledTestPage()
            return
        }

        guard let url = URL(string: webURLString), ["http", "https"].contains(url.scheme?.lowercased()) else {
            loadConfigError("Invalid APP_WEB_URL: \(webURLString)")
            return
        }
        webView.load(URLRequest(url: url))
    }

    private func configuredWebURLString() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "APP_WEB_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isConfiguredEntryRemote() -> Bool {
        let webURLString = configuredWebURLString()
        guard let url = URL(string: webURLString), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https"].contains(scheme)
    }

    private func configuredDisplayName() -> String {
        let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty || displayName == "$(APP_DISPLAY_NAME)" {
            return "龙湖电梯维保"
        }
        return displayName
    }

    private func shouldLoadBundledTestPage(_ webURLString: String) -> Bool {
        webURLString.isEmpty
            || webURLString == "$(APP_WEB_URL)"
            || webURLString.hasPrefix("file:///ios_bundle/")
            || webURLString == "znhaas_app_tests.html"
    }

    private func loadBundledTestPage() {
        guard let url = Bundle.main.url(forResource: "znhaas_app_tests", withExtension: "html") else {
            webView.loadHTMLString("<h1>znhaas_app_tests.html not found</h1>", baseURL: nil)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func loadConfigError(_ message: String) {
        webView.loadHTMLString("""
        <html><body style="font-family:-apple-system;padding:24px;">
        <h2>App entry config error</h2>
        <p>\(htmlEscaped(message))</p>
        </body></html>
        """, baseURL: nil)
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func recoverMainWebViewIfNeeded(reason: String, error: Error? = nil) {
        if let error, isCancelledNavigationError(error) {
            return
        }
        let retryDelays: [TimeInterval] = [0.8, 2.0, 4.0, 6.0]
        guard mainWebViewRecoveryAttempts < retryDelays.count else {
            return
        }
        let delay = retryDelays[mainWebViewRecoveryAttempts]
        mainWebViewRecoveryAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.webView.stopLoading()
            self.loadConfiguredEntry()
        }
    }

    @objc private func appDidBecomeActive() {
        if bleClient != nil {
            emitStateAfterBluetoothRefresh()
        }
        guard isConfiguredEntryRemote(), mainWebViewDidFinishInitialLoad == false else {
            return
        }
        guard mainWebViewActiveRecoveryAttempts < 3 else {
            return
        }
        mainWebViewActiveRecoveryAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, self.mainWebViewDidFinishInitialLoad == false else {
                return
            }
            self.mainWebViewRecoveryAttempts = 0
            self.webView.stopLoading()
            self.loadConfiguredEntry()
        }
    }

    private func isCancelledNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func bridgeBootstrapScript() -> String {
        """
        (function() {
          if (window.ZnhaasBleBridge && window.ZnhaasBleBridge.__isZnhaasIOSBridge) {
            return;
          }
          var callbacks = {};
          var sequence = 1;
          var latestState = {
            bluetoothInitialized: false,
            bluetoothChecking: true,
            bluetoothEnabled: false,
            scanning: false,
            connected: false
          };
          function send(action, payload) {
            var callbackId = 'ios-cb-' + Date.now() + '-' + (sequence++);
            window.webkit.messageHandlers.\(bridgeName).postMessage({
              callbackId: callbackId,
              action: action,
              payload: payload || {}
            });
            return callbackId;
          }
          function updateLatestState(event) {
            if (!event || typeof event !== 'object') {
              return;
            }
            if (event.type === 'state' || event.type === 'bluetoothStateChanged' || event.type === 'permissionsResult' || event.type === 'enableBluetoothResult') {
              var data = event.data;
              if (data && typeof data === 'object') {
                Object.keys(data).forEach(function(key) {
                  latestState[key] = data[key];
                });
              }
            }
            if (event.type === 'deviceConnecting' || event.type === 'deviceConnected' || event.type === 'deviceReady') {
              latestState.connected = true;
            }
            if (event.type === 'deviceDisconnected') {
              latestState.connected = false;
            }
          }
          window.ZnhaasBleBridge = {
            __isZnhaasIOSBridge: true,
            __updateLatestState: updateLatestState,
            getState: function() { send('getState'); return JSON.stringify(latestState); },
            requestPermissions: function() { return send('requestPermissions'); },
            requestEnableBluetooth: function() { return send('requestEnableBluetooth'); },
            startScan: function(durationMs) { return send('startScan', { durationMs: durationMs }); },
            stopScan: function() { return send('stopScan'); },
            connect: function(identifier) { return send('connect', { identifier: identifier }); },
            disconnect: function() { return send('disconnect'); },
            startRecord: function(extraFields) { return send('startRecord', { extraFields: cleanExtraFields(extraFields) }); },
            startRecordJson: function(extraFieldsJson) { return send('startRecord', { extraFields: cleanExtraFields(parseJsonObject(extraFieldsJson)) }); },
            stopRecord: function(extraFields) { return send('stopRecord', { extraFields: cleanExtraFields(extraFields) }); },
            stopRecordJson: function(extraFieldsJson) { return send('stopRecord', { extraFields: cleanExtraFields(parseJsonObject(extraFieldsJson)) }); },
            queryRecordStatus: function(extraFields) { return send('queryRecordStatus', { extraFields: cleanExtraFields(extraFields) }); },
            queryRecordStatusJson: function(extraFieldsJson) { return send('queryRecordStatus', { extraFields: cleanExtraFields(parseJsonObject(extraFieldsJson)) }); },
            disableVideoKey: function(extraFields) { return send('disableVideoKey', { extraFields: cleanExtraFields(extraFields) }); },
            disableVideoKeyJson: function(extraFieldsJson) { return send('disableVideoKey', { extraFields: cleanExtraFields(parseJsonObject(extraFieldsJson)) }); },
            enableVideoKey: function(extraFields) { return send('enableVideoKey', { extraFields: cleanExtraFields(extraFields) }); },
            enableVideoKeyJson: function(extraFieldsJson) { return send('enableVideoKey', { extraFields: cleanExtraFields(parseJsonObject(extraFieldsJson)) }); },
            writeCommand: function(command) { return send('writeCommand', { command: command }); }
          };
          if (!window.ZnhaasAppBridge || !window.ZnhaasAppBridge.__isZnhaasIOSAppBridge) {
            window.ZnhaasApp = window.ZnhaasApp || {};
            window.ZnhaasApp.__dispatch = function(payload) {
              var event = typeof payload === 'string' ? JSON.parse(payload) : payload;
              try { window.dispatchEvent(new CustomEvent('ZnhaasAppEvent', { detail: event })); } catch (e) {}
              if (typeof window.ZnhaasApp.onNativeEvent === 'function') {
                window.ZnhaasApp.onNativeEvent(event);
              }
            };
            function sendApp(action, payload) {
              var callbackId = 'ios-app-cb-' + Date.now() + '-' + (sequence++);
              window.webkit.messageHandlers.\(appBridgeName).postMessage({
                callbackId: callbackId,
                action: action,
                payload: payload || {}
              });
              return callbackId;
            }
            window.ZnhaasAppBridge = {
              __isZnhaasIOSAppBridge: true,
              scanCode: function(options) { return sendApp('scanCode', options || {}); },
              scanCodeJson: function(optionsJson) { return sendApp('scanCode', parseJsonObject(optionsJson)); },
              takePhoto: function(options) { return sendApp('takePhoto', options || {}); },
              takePhotoJson: function(optionsJson) { return sendApp('takePhoto', parseJsonObject(optionsJson)); },
              getNetworkState: function() { return sendApp('getNetworkState'); },
              openWebView: function(options) {
                if (typeof options === 'string') {
                  return sendApp('openWebView', { url: options });
                }
                return sendApp('openWebView', options || {});
              },
              openWebViewJson: function(optionsJson) { return sendApp('openWebView', parseJsonObject(optionsJson)); }
            };
          }
          function cleanExtraFields(extraFields) {
            if (!extraFields || typeof extraFields !== 'object') {
              return {};
            }
            var cleaned = {};
            Object.keys(extraFields).forEach(function(key) {
              var value = extraFields[key] == null ? '' : String(extraFields[key]).trim();
              if (String(key).trim() && value) {
                cleaned[key] = value;
              }
            });
            return cleaned;
          }
          function parseJsonObject(value) {
            if (!value) {
              return {};
            }
            if (typeof value === 'object') {
              return value;
            }
            if (typeof value !== 'string') {
              return {};
            }
            try {
              var parsed = JSON.parse(value);
              return parsed && typeof parsed === 'object' ? parsed : {};
            } catch (error) {
              return {};
            }
          }
        })();
        """
    }

    private func handle(action: String, payload: [String: Any], callbackId: String?) {
        switch action {
        case "getState":
            emitStateAfterBluetoothRefresh()
        case "requestPermissions":
            emitStateAfterBluetoothRefresh(type: "permissionsResult")
        case "requestEnableBluetooth":
            handleEnableBluetoothRequest(callbackId: callbackId)
        case "startScan":
            let durationMs = payload["durationMs"] as? Double ?? 12_000
            devices.removeAll()
            emit("scanStarted", data: [:])
            ensureBleClient().startScan(duration: max(durationMs / 1000.0, 0.1))
        case "stopScan":
            bleClient?.stopScan()
        case "connect":
            connect(identifierString: payload["identifier"] as? String)
        case "disconnect":
            bleClient?.disconnect()
        case "startRecord":
            let client = ensureBleClient()
            sendRecordAction("startRecord", extraFields: parseExtraFields(payload), perform: client.startRecord(extraFields:completion:))
        case "stopRecord":
            let client = ensureBleClient()
            sendRecordAction("stopRecord", extraFields: parseExtraFields(payload), perform: client.stopRecord(extraFields:completion:))
        case "queryRecordStatus":
            let client = ensureBleClient()
            sendRecordAction("queryRecordStatus", extraFields: parseExtraFields(payload), perform: client.queryRecordStatus(extraFields:completion:))
        case "disableVideoKey":
            let client = ensureBleClient()
            sendRecordAction("disableVideoKey", extraFields: parseExtraFields(payload), perform: client.disableVideoKey(extraFields:completion:))
        case "enableVideoKey":
            let client = ensureBleClient()
            sendRecordAction("enableVideoKey", extraFields: parseExtraFields(payload), perform: client.enableVideoKey(extraFields:completion:))
        case "writeCommand":
            writeCommand(payload["command"] as? String)
        default:
            emitError(source: action, message: "Unknown bridge action: \(action)")
        }

        if let callbackId {
            emitLog("Bridge action handled: \(action), callbackId=\(callbackId)")
        }
    }

    private func emitStateAfterBluetoothRefresh(type: String = "state", extraData: [String: Any] = [:], attempt: Int = 0) {
        let client = ensureBleClient()
        let emitRefreshedState = { [weak self] in
            guard let self = self else { return }
            var data = self.baseState()
            if type == "permissionsResult" {
                data["granted"] = data["hasRequiredPermissions"] as? Bool ?? false
            }
            for (key, value) in extraData {
                data[key] = value
            }
            self.emit(type, data: data)
        }

        if shouldWaitForBluetoothState(client: client), attempt < 20 {
            if attempt == 0 {
                emitRefreshedState()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.emitStateAfterBluetoothRefresh(type: type, extraData: extraData, attempt: attempt + 1)
            }
            return
        }

        emitRefreshedState()
    }

    private func handleEnableBluetoothRequest(callbackId: String?, attempt: Int = 0) {
        let client = ensureBleClient()
        switch client.currentState {
        case .poweredOn:
            let message = "蓝牙已开启"
            emitLog(message)
            emitEnableBluetoothResult(callbackId: callbackId, success: true, code: "poweredOn", message: message)
            emitStateAfterBluetoothRefresh()
        case .poweredOff:
            let message = "iOS 不允许 App 直接开启蓝牙，请从控制中心或系统设置 > 蓝牙手动开启。"
            emitLog(message)
            emitEnableBluetoothResult(callbackId: callbackId, success: false, code: "poweredOff", message: message)
            presentBluetoothPoweredOffGuidance()
            emitStateAfterBluetoothRefresh()
        case .unauthorized:
            let message = "蓝牙权限未授权，请在系统设置中允许本 App 使用蓝牙。"
            emitLog(message)
            emitEnableBluetoothResult(callbackId: callbackId, success: false, code: "unauthorized", message: message)
            presentBluetoothPermissionGuidance()
            emitStateAfterBluetoothRefresh()
        case .unsupported:
            let message = "当前设备不支持蓝牙 BLE。"
            emitLog(message)
            emitEnableBluetoothResult(callbackId: callbackId, success: false, code: "unsupported", message: message)
            emitStateAfterBluetoothRefresh()
        case .unknown, .resetting:
            if attempt == 0 {
                emitLog("正在检查蓝牙状态...")
                emitStateAfterBluetoothRefresh()
            }
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.handleEnableBluetoothRequest(callbackId: callbackId, attempt: attempt + 1)
                }
            } else {
                let message = "蓝牙状态检查超时，请稍后重试。"
                self.emitEnableBluetoothResult(callbackId: callbackId, success: false, code: "stateTimeout", message: message)
            }
        @unknown default:
            let message = "蓝牙状态未知，请稍后重试。"
            emitLog(message)
            emitEnableBluetoothResult(callbackId: callbackId, success: false, code: "unknown", message: message)
            emitStateAfterBluetoothRefresh()
        }
    }

    private func emitEnableBluetoothResult(callbackId: String?, success: Bool, code: String, message: String) {
        var data = baseState()
        data["requestId"] = callbackId ?? makeRequestId(prefix: "enableBluetooth")
        data["success"] = success
        data["code"] = code
        data["message"] = message
        emit("enableBluetoothResult", data: data)
    }

    private func presentBluetoothPoweredOffGuidance() {
        presentBluetoothGuidance(
            title: "蓝牙未开启",
            message: "iOS 不允许 App 直接开启蓝牙。请从屏幕右上角下拉打开控制中心，或进入系统设置 > 蓝牙，手动开启后回到本页面继续操作。",
            settingsURL: URL(string: "App-Prefs:root=Bluetooth")
        )
    }

    private func presentBluetoothPermissionGuidance() {
        presentBluetoothGuidance(
            title: "蓝牙权限未开启",
            message: "请在系统设置中允许“\(configuredDisplayName())”使用蓝牙，然后回到本页面继续操作。",
            settingsURL: URL(string: UIApplication.openSettingsURLString)
        )
    }

    private func presentBluetoothGuidance(title: String, message: String, settingsURL: URL?) {
        if presentedViewController is UIAlertController {
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        if let settingsURL {
            alert.addAction(UIAlertAction(title: "设置", style: .default) { [weak self] _ in
                self?.openSettings(preferredURL: settingsURL)
            })
        }
        present(alert, animated: true)
    }

    private func openSettings(preferredURL: URL) {
        UIApplication.shared.open(preferredURL, options: [:]) { success in
            guard success == false,
                  preferredURL.absoluteString != UIApplication.openSettingsURLString,
                  let fallbackURL = URL(string: UIApplication.openSettingsURLString) else {
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.open(fallbackURL, options: [:], completionHandler: nil)
            }
        }
    }

    private func handleApp(action: String, payload: [String: Any], callbackId: String?) {
        switch action {
        case "scanCode":
            startScanCode(requestId: callbackId ?? makeRequestId(prefix: "scan"))
        case "takePhoto":
            startTakePhoto(requestId: callbackId ?? makeRequestId(prefix: "photo"), payload: payload)
        case "getNetworkState":
            var data = networkState()
            data["requestId"] = callbackId ?? makeRequestId(prefix: "network")
            emitApp("networkState", data: data)
        case "openWebView":
            openWebView(requestId: callbackId ?? makeRequestId(prefix: "webview"), payload: payload)
        default:
            emitApp("error", data: [
                "source": action,
                "message": "Unknown app bridge action: \(action)"
            ])
        }

        if let callbackId {
            emitLog("AppBridge action handled: \(action), callbackId=\(callbackId)")
        }
    }

    private func startScanCode(requestId: String) {
        pendingScanCodeRequestId = requestId
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentScanCodeController(requestId: requestId)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted {
                        self.presentScanCodeController(requestId: requestId)
                    } else {
                        self.emitScanCodeDenied(requestId: requestId)
                    }
                }
            }
        default:
            emitScanCodeDenied(requestId: requestId)
        }
    }

    private func presentScanCodeController(requestId: String) {
        let controller = ZnhaasScanCodeViewController(requestId: requestId)
        controller.onResult = { [weak self] result in
            self?.pendingScanCodeRequestId = nil
            self?.emitApp("scanCodeResult", data: result)
        }
        present(controller, animated: true)
    }

    private func emitScanCodeDenied(requestId: String) {
        pendingScanCodeRequestId = nil
        emitApp("scanCodeResult", data: [
            "requestId": requestId,
            "text": "",
            "format": "",
            "cancelled": true,
            "message": "Camera permission denied."
        ])
    }

    private func startTakePhoto(requestId: String, payload: [String: Any]) {
        pendingTakePhotoRequestId = requestId
        pendingTakePhotoMaxWidth = CGFloat((payload["maxWidth"] as? NSNumber)?.doubleValue ?? 1600)
        let qualityNumber = (payload["quality"] as? NSNumber)?.doubleValue ?? 80
        pendingTakePhotoQuality = CGFloat(max(1, min(100, qualityNumber)) / 100.0)

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            emitApp("takePhotoError", data: [
                "requestId": requestId,
                "cancelled": false,
                "message": "Camera is not available."
            ])
            pendingTakePhotoRequestId = nil
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentTakePhotoController()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted {
                        self.presentTakePhotoController()
                    } else {
                        self.emitTakePhotoDenied(requestId: requestId)
                    }
                }
            }
        default:
            emitTakePhotoDenied(requestId: requestId)
        }
    }

    private func presentTakePhotoController() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        present(picker, animated: true)
    }

    private func emitTakePhotoDenied(requestId: String) {
        pendingTakePhotoRequestId = nil
        emitApp("takePhotoError", data: [
            "requestId": requestId,
            "cancelled": false,
            "message": "Camera permission denied."
        ])
    }

    private func openWebView(requestId: String, payload: [String: Any]) {
        let urlString = (payload["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = resolveWebViewURL(urlString) else {
            emitApp("openWebViewResult", data: [
                "requestId": requestId,
                "success": false,
                "url": urlString,
                "message": "Invalid or unsupported url."
            ])
            return
        }
        let controller = ZnhaasAppWebViewController(url: url, pageTitle: title.isEmpty ? "新页面" : title)
        navigationController?.pushViewController(controller, animated: true)
        emitApp("openWebViewResult", data: [
            "requestId": requestId,
            "success": true,
            "url": urlString
        ])
    }

    private func resolveWebViewURL(_ urlString: String) -> URL? {
        guard urlString.isEmpty == false else {
            return nil
        }
        if let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) {
            return url
        }
        let name = (urlString as NSString).deletingPathExtension
        let ext = (urlString as NSString).pathExtension.isEmpty ? "html" : (urlString as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    private func networkState() -> [String: Any] {
        ZnhaasReachability.currentState()
    }

    private func makeRequestId(prefix: String) -> String {
        "\(prefix)-\(Int64(Date().timeIntervalSince1970 * 1000))"
    }

    private func connect(identifierString: String?) {
        guard let identifierString = identifierString, let identifier = UUID(uuidString: identifierString) else {
            emitError(source: "connect", message: "Device identifier is empty or invalid.")
            return
        }
        fixedReplySupportsRead = false
        pendingReadFallback = false
        enabledReplyCharacteristicUUIDs.removeAll()
        emitLog("Connecting to \(identifier.uuidString)")
        ensureBleClient().connect(identifier: identifier)
    }

    private func writeCommand(_ command: String?) {
        guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines), command.isEmpty == false else {
            emitError(source: "writeCommand", message: "Command is empty.")
            return
        }
        emit("commandDispatched", data: [
            "action": "writeCommand",
            "requestId": NSNull(),
            "command": command
        ])
        _ = ensureBleClient().writeFixedASCIICommand(command, requestId: nil) { [weak self] result in
            self?.handleWriteResult("writeCommand", result: result)
        }
    }

    private func sendRecordAction(
        _ action: String,
        extraFields: [String: String],
        perform: ([String: String], ZnhaasBleWriteCompletion?) -> String
    ) {
        let requestId = perform(extraFields) { [weak self] result in
            self?.handleWriteResult(action, result: result)
        }
        let timestamp = requestTimestamp(from: requestId)
        let recordAction = recordAction(for: action)
        let command = ZnhaasBleClient.buildRecordCommand(
            action: recordAction,
            requestId: requestId,
            timestamp: timestamp,
            extraFields: extraFields
        )
        emit("commandDispatched", data: [
            "action": action,
            "requestId": requestId,
            "command": command,
            "extraFields": extraFields
        ])
    }

    private func handleWriteResult(_ action: String, result: Result<ZnhaasBleWriteResult, ZnhaasBleError>) {
        switch result {
        case .success(let writeResult):
            emit("writeSuccess", data: [
                "action": action,
                "requestId": writeResult.requestId ?? "",
                "serviceUuid": writeResult.serviceUUID.uuidString,
                "characteristicUuid": writeResult.characteristicUUID.uuidString,
                "value": writeResult.stringValue ?? "",
                "hexValue": writeResult.hexValue
            ])
            if writeResult.characteristicUUID == ZnhaasBleClient.fixedWriteCharacteristicUUID,
               hasReplyListener() == false,
               fixedReplySupportsRead {
                scheduleReadFixedReply()
            }
        case .failure(let error):
            emit("writeError", data: [
                "action": action,
                "message": error.localizedDescription
            ])
        }
    }

    private func parseExtraFields(_ payload: [String: Any]) -> [String: String] {
        guard let raw = payload["extraFields"] as? [String: Any] else {
            return [:]
        }
        var fields: [String: String] = [:]
        for (key, value) in raw {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedKey.isEmpty == false, normalizedValue.isEmpty == false {
                fields[normalizedKey] = normalizedValue
            }
        }
        return fields
    }

    private func requestTimestamp(from requestId: String) -> Int64 {
        let suffix = requestId.replacingOccurrences(of: "req-", with: "")
        return Int64(suffix) ?? Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func recordAction(for action: String) -> ZnhaasRecordAction {
        switch action {
        case "startRecord":
            return .startRecord
        case "stopRecord":
            return .stopRecord
        case "queryRecordStatus":
            return .queryStatus
        case "disableVideoKey":
            return .disableVideoKey
        case "enableVideoKey":
            return .enableVideoKey
        default:
            return .queryStatus
        }
    }

    private func parseV2Response(_ value: String) -> [String: Any]? {
        let rawParts = value.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
        guard let parts = normalizeV2ResponseParts(rawParts) else {
            return nil
        }
        guard parts.count >= 14, parts[0] == "2", parts[1] == "R" else {
            return nil
        }
        let statusCode = parts[13]
        var response: [String: Any] = [
            "version": parts[0],
            "cmdType": parts[1],
            "command": parts[2],
            "commandText": commandText(parts[2]),
            "action": parts[3],
            "actionText": actionText(parts[3]),
            "requestId": parts[4],
            "timestamp": parts[5],
            "workOrder": parts[6],
            "taskId": parts[7],
            "deviceId": parts[8],
            "battery": parts[9],
            "rssi": parts[10],
            "filePath": parts[11],
            "bucketName": parts[12],
            "statusCode": statusCode,
            "statusText": statusText(statusCode),
            "success": statusCode == "0"
        ]
        if parts[2] == "1", parts[11].isEmpty == false {
            response["recordingState"] = parts[11]
            response["recording"] = parts[11] == "1"
        }
        return response
    }

    private func normalizeV2ResponseParts(_ rawParts: [String]) -> [String]? {
        guard rawParts.count >= 14 else {
            return nil
        }
        if rawParts.count == 14 {
            return rawParts
        }
        var parts = Array(repeating: "", count: 14)
        for index in 0..<min(9, rawParts.count) {
            parts[index] = rawParts[index]
        }
        if rawParts[safe: 2] == "1", rawParts[safe: 3] == "3" {
            let tailStart = rawParts.count - 5
            parts[9] = rawParts[safe: tailStart] ?? ""
            parts[10] = rawParts[safe: tailStart + 1] ?? ""
            parts[11] = rawParts[safe: tailStart + 2] ?? ""
            parts[12] = rawParts[safe: tailStart + 3] ?? ""
            parts[13] = rawParts[safe: tailStart + 4] ?? ""
            return parts
        }
        for index in 9..<min(13, rawParts.count) {
            parts[index] = rawParts[index]
        }
        parts[13] = rawParts.last ?? ""
        return parts
    }

    private func commandText(_ command: String) -> String {
        switch command {
        case "0":
            return "RECORD"
        case "1":
            return "STATUS"
        default:
            return "UNKNOWN"
        }
    }

    private func actionText(_ action: String) -> String {
        switch action {
        case "0":
            return "STOP_RECORD"
        case "1":
            return "START_RECORD_DISABLE_KEY"
        case "2":
            return "START_RECORD_ENABLE_KEY"
        case "3":
            return "QUERY_STATUS"
        default:
            return "UNKNOWN"
        }
    }

    private func statusText(_ statusCode: String) -> String {
        switch statusCode {
        case "0":
            return "SUCCESS"
        case "1":
            return "FAILED"
        case "2":
            return "PARAM_ERROR"
        default:
            return "UNKNOWN"
        }
    }

    private func hasReplyListener() -> Bool {
        enabledReplyCharacteristicUUIDs.isEmpty == false
    }

    private func scheduleReadFixedReply() {
        emitLog("Scheduling read fallback in 200ms...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else {
                return
            }
            self.pendingReadFallback = true
            self.bleClient?.readFixedReply { [weak self] result in
                if case .failure(let error) = result {
                    self?.pendingReadFallback = false
                    self?.emitError(source: "readFixedReply", message: error.localizedDescription)
                }
            }
        }
    }

    private func baseState() -> [String: Any] {
        let client = bleClient
        let state = client?.currentState
        let permission = bluetoothPermissionState(centralState: state)
        var data: [String: Any] = [
            "bluetoothSupported": true,
            "bluetoothInitialized": client != nil,
            "bluetoothEnabled": state == .poweredOn,
            "bluetoothChecking": state == .unknown || state == .resetting,
            "bluetoothStatusText": bluetoothStateText(state),
            "hasRequiredPermissions": permission.granted,
            "bluetoothAuthorization": permission.authorization,
            "bluetoothAuthorizationText": permission.text,
            "scanning": client?.isScanning ?? false,
            "connected": client?.connectedDevice != nil,
            "serviceUuid": ZnhaasBleClient.fixedServiceUUID.uuidString,
            "writeUuid": ZnhaasBleClient.fixedWriteCharacteristicUUID.uuidString,
            "replyUuid": ZnhaasBleClient.fixedNotifyCharacteristicUUID.uuidString
        ]
        if let state {
            data["stateCode"] = state.rawValue
            data["stateText"] = bluetoothStateText(state)
        }
        return data
    }

    private func shouldWaitForBluetoothState(client: ZnhaasBleClient) -> Bool {
        let permission = bluetoothPermissionState(centralState: client.currentState)
        switch client.currentState {
        case .unknown, .resetting:
            return true
        default:
            return permission.authorization == "checking"
        }
    }

    private func bluetoothPermissionState(centralState: CBManagerState?) -> ZnhaasBlePermissionState {
        let authorization: String
        if #available(iOS 13.1, *) {
            switch CBManager.authorization {
            case .allowedAlways:
                authorization = "allowedAlways"
            case .denied:
                authorization = "denied"
            case .restricted:
                authorization = "restricted"
            case .notDetermined:
                authorization = "notDetermined"
            @unknown default:
                authorization = "unknown"
            }
        } else {
            authorization = "legacy"
        }
        return ZnhaasBleClient.resolvePermissionState(
            systemAuthorization: authorization,
            centralState: centralState
        )
    }

    private func bluetoothStateText(_ state: CBManagerState?) -> String {
        guard let state else {
            return "未检查"
        }
        switch state {
        case .poweredOn:
            return "已开启"
        case .poweredOff:
            return "未开启"
        case .unauthorized:
            return "未授权"
        case .unsupported:
            return "设备不支持"
        case .unknown, .resetting:
            return "检查中"
        @unknown default:
            return "未知"
        }
    }

    private func deviceToJson(_ device: ZnhaasBleDevice) -> [String: Any] {
        [
            "name": device.name ?? "",
            "displayName": device.displayName,
            "address": device.identifier.uuidString,
            "identifier": device.identifier.uuidString,
            "rssi": device.rssi,
            "bondState": "unknown"
        ]
    }

    private func emitDeviceEvent(_ type: String, device: ZnhaasBleDevice) {
        emit(type, data: ["device": deviceToJson(device)])
    }

    private func emitLog(_ message: String) {
        emit("log", data: ["message": message])
    }

    private func emitError(source: String, message: String) {
        emit("error", data: [
            "source": source,
            "message": message
        ])
    }

    private func emit(_ type: String, data: [String: Any]) {
        var event: [String: Any] = [
            "type": type,
            "data": data,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if !JSONSerialization.isValidJSONObject(event) {
            event["data"] = ["message": "Invalid event payload"]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: event, options: []),
              let json = String(data: jsonData, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(
                "(function(event) { window.ZnhaasBleBridge&&window.ZnhaasBleBridge.__updateLatestState&&window.ZnhaasBleBridge.__updateLatestState(event); window.ZnhaasBle&&window.ZnhaasBle.__dispatch&&window.ZnhaasBle.__dispatch(event); })(\(json));",
                completionHandler: nil
            )
        }
    }

    private func emitApp(_ type: String, data: [String: Any]) {
        var event: [String: Any] = [
            "type": type,
            "data": data,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if !JSONSerialization.isValidJSONObject(event) {
            event["data"] = ["message": "Invalid event payload"]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: event, options: []),
              let json = String(data: jsonData, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(
                "window.ZnhaasApp&&window.ZnhaasApp.__dispatch&&window.ZnhaasApp.__dispatch(\(json));",
                completionHandler: nil
            )
        }
    }

    private func imageResult(from image: UIImage, requestId: String) -> [String: Any]? {
        let normalized = image.normalizedOrientation()
        let scaled = normalized.scaledToMaxSide(pendingTakePhotoMaxWidth)
        guard let data = scaled.jpegData(compressionQuality: pendingTakePhotoQuality) else {
            return nil
        }
        let base64 = data.base64EncodedString()
        return [
            "requestId": requestId,
            "cancelled": false,
            "image": [
                "base64": base64,
                "dataUrl": "data:image/jpeg;base64,\(base64)",
                "mimeType": "image/jpeg",
                "fileName": "photo_\(Int64(Date().timeIntervalSince1970 * 1000)).jpg",
                "width": Int(scaled.size.width),
                "height": Int(scaled.size.height),
                "sizeBytes": data.count
            ]
        ]
    }

    private func propertiesText(_ properties: CBCharacteristicProperties) -> String {
        var labels: [String] = []
        if properties.contains(.read) {
            labels.append("READ")
        }
        if properties.contains(.write) {
            labels.append("WRITE")
        }
        if properties.contains(.writeWithoutResponse) {
            labels.append("WRITE_NO_RESPONSE")
        }
        if properties.contains(.notify) {
            labels.append("NOTIFY")
        }
        if properties.contains(.indicate) {
            labels.append("INDICATE")
        }
        if labels.isEmpty {
            return "NONE(\(properties.rawValue))"
        }
        return "\(labels.joined(separator: "|")) (\(properties.rawValue))"
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}

private func configureH5WebView(_ webView: WKWebView) {
    webView.allowsLinkPreview = false
    webView.backgroundColor = .white
    webView.isOpaque = false
    let scrollView = webView.scrollView
    scrollView.backgroundColor = .white
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.bounces = false
    scrollView.alwaysBounceVertical = false
    scrollView.alwaysBounceHorizontal = false
    scrollView.bouncesZoom = false
    scrollView.minimumZoomScale = 1.0
    scrollView.maximumZoomScale = 1.0
    scrollView.zoomScale = 1.0
    scrollView.pinchGestureRecognizer?.isEnabled = false
}

private func h5ViewportLockScript() -> String {
    """
    (function() {
      function installInteractionLock() {
        if (!document.documentElement) { return; }
        var css = [
          'html, body { -webkit-text-size-adjust: 100%; -webkit-touch-callout: none; -webkit-user-select: none; user-select: none; }',
          'body { overscroll-behavior: none; }',
          'a, button { -webkit-tap-highlight-color: transparent; }',
          'input, textarea { -webkit-touch-callout: none; -webkit-user-select: none; user-select: none; }'
        ].join('\\n');
        var style = document.getElementById('znhaas-ios-webview-lock');
        if (!style && document.head) {
          style = document.createElement('style');
          style.id = 'znhaas-ios-webview-lock';
          document.head.appendChild(style);
        }
        if (style) {
          style.textContent = css;
        }
      }
      function lockViewport() {
        if (!document.head) { return; }
        var content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no, viewport-fit=cover';
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        meta.setAttribute('content', content);
        if (document.documentElement && document.documentElement.style) {
          document.documentElement.style.webkitTextSizeAdjust = '100%';
        }
        installInteractionLock();
      }
      document.addEventListener('contextmenu', function(event) { event.preventDefault(); }, true);
      document.addEventListener('selectstart', function(event) {
        var tag = event.target && event.target.tagName ? event.target.tagName.toLowerCase() : '';
        if (tag !== 'input' && tag !== 'textarea') {
          event.preventDefault();
        }
      }, true);
      installInteractionLock();
      lockViewport();
      document.addEventListener('DOMContentLoaded', lockViewport);
      window.addEventListener('load', lockViewport);
    })();
    """
}

extension MainViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        mainWebViewDidFinishInitialLoad = true
        mainWebViewRecoveryAttempts = 0
        mainWebViewActiveRecoveryAttempts = 0
        emitLog("H5 demo ready. iOS JSBridge installed.")
        emit("state", data: baseState())
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        recoverMainWebViewIfNeeded(reason: "didFail", error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        recoverMainWebViewIfNeeded(reason: "didFailProvisionalNavigation", error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recoverMainWebViewIfNeeded(reason: "webContentProcessDidTerminate")
    }
}

extension MainViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }
        let payload = body["payload"] as? [String: Any] ?? [:]
        let callbackId = body["callbackId"] as? String
        if message.name == bridgeName {
            handle(action: action, payload: payload, callbackId: callbackId)
        } else if message.name == appBridgeName {
            handleApp(action: action, payload: payload, callbackId: callbackId)
        }
    }
}

extension MainViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        let requestId = pendingTakePhotoRequestId ?? makeRequestId(prefix: "photo")
        pendingTakePhotoRequestId = nil
        picker.dismiss(animated: true) { [weak self] in
            self?.emitApp("takePhotoResult", data: [
                "requestId": requestId,
                "cancelled": true
            ])
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let requestId = pendingTakePhotoRequestId ?? makeRequestId(prefix: "photo")
        pendingTakePhotoRequestId = nil
        guard let image = info[.originalImage] as? UIImage else {
            picker.dismiss(animated: true) { [weak self] in
                self?.emitApp("takePhotoError", data: [
                    "requestId": requestId,
                    "cancelled": false,
                    "message": "Unable to read captured image."
                ])
            }
            return
        }

        let result = imageResult(from: image, requestId: requestId)
        picker.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            if let result {
                self.emitApp("takePhotoResult", data: result)
            } else {
                self.emitApp("takePhotoError", data: [
                    "requestId": requestId,
                    "cancelled": false,
                    "message": "Unable to encode captured image."
                ])
            }
        }
    }
}

extension MainViewController: ZnhaasBleClientDelegate {
    func bleClient(_ client: ZnhaasBleClient, didUpdateState state: CBManagerState) {
        var data = baseState()
        data["stateCode"] = state.rawValue
        data["stateText"] = bluetoothStateText(state)
        data["enabled"] = state == .poweredOn
        emit("bluetoothStateChanged", data: data)
    }

    func bleClientDidStartScan(_ client: ZnhaasBleClient) {
        emit("scanStarted", data: [:])
    }

    func bleClient(_ client: ZnhaasBleClient, didDiscover device: ZnhaasBleDevice) {
        devices = client.scannedDevices
        emit("deviceFound", data: ["device": deviceToJson(device)])
    }

    func bleClient(_ client: ZnhaasBleClient, didStopScan devices: [ZnhaasBleDevice]) {
        self.devices = devices
        emit("scanStopped", data: [
            "devices": devices.map(deviceToJson),
            "count": devices.count
        ])
    }

    func bleClient(_ client: ZnhaasBleClient, didFailScan error: ZnhaasBleError) {
        emitError(source: "scan", message: error.localizedDescription)
    }

    func bleClient(_ client: ZnhaasBleClient, isConnectingTo device: ZnhaasBleDevice) {
        emitDeviceEvent("deviceConnecting", device: device)
    }

    func bleClient(_ client: ZnhaasBleClient, didConnect device: ZnhaasBleDevice) {
        emitDeviceEvent("deviceConnected", device: device)
    }

    func bleClient(_ client: ZnhaasBleClient, didDiscoverServices services: [CBService], for device: ZnhaasBleDevice) {
        emitLog("Services discovered for \(device.displayName): \(services.count)")
    }

    func bleClient(_ client: ZnhaasBleClient, didDiscoverCharacteristics characteristics: [CBCharacteristic], for service: CBService, device: ZnhaasBleDevice) {
        guard service.uuid == ZnhaasBleClient.fixedServiceUUID else {
            return
        }
        fixedReplySupportsRead = false
        enabledReplyCharacteristicUUIDs.removeAll()

        for characteristic in characteristics {
            emitLog("Fixed service characteristic [\(characteristic.uuid.uuidString)] properties: \(propertiesText(characteristic.properties))")
            if characteristic.uuid == ZnhaasBleClient.fixedNotifyCharacteristicUUID {
                fixedReplySupportsRead = characteristic.properties.contains(.read)
            }
        }
    }

    func bleClient(_ client: ZnhaasBleClient, didBecomeReady device: ZnhaasBleDevice) {
        emitDeviceEvent("deviceReady", device: device)
        client.enableFixedServiceNotifications { [weak self] result in
            switch result {
            case .success:
                self?.emitLog("Reply listener enabled.")
            case .failure(let error):
                self?.emitError(source: "notify", message: error.localizedDescription)
            }
        }
    }

    func bleClient(_ client: ZnhaasBleClient, didDisconnect device: ZnhaasBleDevice?, error: Error?) {
        fixedReplySupportsRead = false
        pendingReadFallback = false
        enabledReplyCharacteristicUUIDs.removeAll()
        if let device = device {
            emitDeviceEvent("deviceDisconnected", device: device)
        } else {
            emit("deviceDisconnected", data: [:])
        }
        if let error {
            emitError(source: "disconnect", message: error.localizedDescription)
        }
    }

    func bleClient(_ client: ZnhaasBleClient, didEnableNotifyFor serviceUUID: CBUUID, characteristicUUID: CBUUID) {
        if serviceUUID == ZnhaasBleClient.fixedServiceUUID {
            enabledReplyCharacteristicUUIDs.insert(characteristicUUID.uuidString)
        }
        emit("replyListenerEnabled", data: [
            "serviceUuid": serviceUUID.uuidString,
            "characteristicUuid": characteristicUUID.uuidString
        ])
    }

    func bleClient(_ client: ZnhaasBleClient, didDisableNotifyFor serviceUUID: CBUUID, characteristicUUID: CBUUID) {
        if serviceUUID == ZnhaasBleClient.fixedServiceUUID {
            enabledReplyCharacteristicUUIDs.remove(characteristicUUID.uuidString)
        }
        emit("replyListenerDisabled", data: [
            "serviceUuid": serviceUUID.uuidString,
            "characteristicUuid": characteristicUUID.uuidString
        ])
    }

    func bleClient(
        _ client: ZnhaasBleClient,
        didReceive value: Data,
        stringValue: String?,
        hexValue: String,
        serviceUUID: CBUUID,
        characteristicUUID: CBUUID
    ) {
        let ascii = stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isReadFallbackValue = pendingReadFallback && characteristicUUID == ZnhaasBleClient.fixedNotifyCharacteristicUUID
        let response = parseV2Response(ascii)
        let isV2Response = response != nil
        let isAck = isV2Response || ascii.hasPrefix("V1|ACK|")
        var data: [String: Any] = [
            "serviceUuid": serviceUUID.uuidString,
            "characteristicUuid": characteristicUUID.uuidString,
            "value": ascii,
            "hexValue": hexValue,
            "isAck": isAck,
            "isV2Response": isV2Response,
            "isReadFallback": isReadFallbackValue
        ]
        if let response {
            data["response"] = response
        }
        emit(isAck ? "deviceAck" : "deviceReply", data: data)
        if isReadFallbackValue {
            pendingReadFallback = false
        }
    }

    func bleClient(_ client: ZnhaasBleClient, didFailWith error: ZnhaasBleError, device: ZnhaasBleDevice?) {
        let deviceData: Any = device.map { deviceToJson($0) } ?? [:]
        emit("connectionError", data: [
            "device": deviceData,
            "message": error.localizedDescription
        ])
    }
}

private final class ZnhaasScanCodeViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onResult: (([String: Any]) -> Void)?

    private let requestId: String
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didFinish = false

    init(requestId: String) {
        self.requestId = requestId
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            finish(cancelled: true, message: "Camera is not available.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            finish(cancelled: true, message: "Scanner output is not available.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = output.availableMetadataObjectTypes

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
    }

    private func setupOverlay() {
        let frameView = UIView()
        frameView.layer.borderColor = UIColor.white.cgColor
        frameView.layer.borderWidth = 2
        frameView.layer.cornerRadius = 18
        frameView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(frameView)

        let tipLabel = UILabel()
        tipLabel.text = "请将二维码/条码放入框内"
        tipLabel.textColor = .white
        tipLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        tipLabel.textAlignment = .center
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tipLabel)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            frameView.widthAnchor.constraint(equalToConstant: 250),
            frameView.heightAnchor.constraint(equalToConstant: 250),
            frameView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            frameView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            tipLabel.topAnchor.constraint(equalTo: frameView.bottomAnchor, constant: 28),
            tipLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            tipLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            cancelButton.widthAnchor.constraint(equalToConstant: 72),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func cancelTapped() {
        finish(cancelled: true, message: nil)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didFinish,
              let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let value = object.stringValue,
              value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        finish(text: value, format: formatText(object.type), cancelled: false, message: nil)
    }

    private func finish(cancelled: Bool, message: String?) {
        finish(text: "", format: "", cancelled: cancelled, message: message)
    }

    private func finish(text: String, format: String, cancelled: Bool, message: String?) {
        guard !didFinish else {
            return
        }
        didFinish = true
        if session.isRunning {
            session.stopRunning()
        }
        var result: [String: Any] = [
            "requestId": requestId,
            "text": text,
            "format": format,
            "cancelled": cancelled
        ]
        if let message, !message.isEmpty {
            result["message"] = message
        }
        dismiss(animated: true) { [onResult] in
            onResult?(result)
        }
    }

    private func formatText(_ type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .qr:
            return "QR_CODE"
        case .ean13:
            return "EAN_13"
        case .ean8:
            return "EAN_8"
        case .code128:
            return "CODE_128"
        case .code39:
            return "CODE_39"
        case .code93:
            return "CODE_93"
        case .pdf417:
            return "PDF417"
        case .aztec:
            return "AZTEC"
        case .dataMatrix:
            return "DATA_MATRIX"
        case .upce:
            return "UPC_E"
        default:
            return type.rawValue
        }
    }
}

private final class ZnhaasAppWebViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private let url: URL
    private let pageTitle: String
    private let appBridgeName = "ZnhaasAppBridge"
    private var webView: WKWebView!
    private var pendingTakePhotoRequestId: String?
    private var pendingTakePhotoMaxWidth: CGFloat = 1600
    private var pendingTakePhotoQuality: CGFloat = 0.8

    init(url: URL, pageTitle: String) {
        self.url = url
        self.pageTitle = pageTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = pageTitle
        view.backgroundColor = .white
        setupWebView()
        loadURL()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: appBridgeName)
    }

    private func setupWebView() {
        let controller = WKUserContentController()
        controller.add(self, name: appBridgeName)
        controller.addUserScript(WKUserScript(source: appBridgeScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: h5ViewportLockScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        configureH5WebView(webView)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            webView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        ])
    }

    private func loadURL() {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    private func appBridgeScript() -> String {
        """
        (function() {
          if (window.ZnhaasAppBridge && window.ZnhaasAppBridge.__isZnhaasIOSAppBridge) { return; }
          var sequence = 1;
          window.ZnhaasApp = window.ZnhaasApp || {};
          window.ZnhaasApp.__dispatch = function(payload) {
            var event = typeof payload === 'string' ? JSON.parse(payload) : payload;
            try { window.dispatchEvent(new CustomEvent('ZnhaasAppEvent', { detail: event })); } catch (e) {}
            if (typeof window.ZnhaasApp.onNativeEvent === 'function') {
              window.ZnhaasApp.onNativeEvent(event);
            }
          };
          function send(action, payload) {
            var callbackId = 'ios-app-cb-' + Date.now() + '-' + (sequence++);
            window.webkit.messageHandlers.\(appBridgeName).postMessage({ callbackId: callbackId, action: action, payload: payload || {} });
            return callbackId;
          }
          window.ZnhaasAppBridge = {
            __isZnhaasIOSAppBridge: true,
            scanCode: function(options) { return send('scanCode', options || {}); },
            scanCodeJson: function(optionsJson) { return send('scanCode', parseJsonObject(optionsJson)); },
            takePhoto: function(options) { return send('takePhoto', options || {}); },
            takePhotoJson: function(optionsJson) { return send('takePhoto', parseJsonObject(optionsJson)); },
            getNetworkState: function() { return send('getNetworkState'); },
            openWebView: function(options) {
              if (typeof options === 'string') { return send('openWebView', { url: options }); }
              return send('openWebView', options || {});
            },
            openWebViewJson: function(optionsJson) { return send('openWebView', parseJsonObject(optionsJson)); }
          };
          function parseJsonObject(value) {
            if (!value) { return {}; }
            if (typeof value === 'object') { return value; }
            if (typeof value !== 'string') { return {}; }
            try {
              var parsed = JSON.parse(value);
              return parsed && typeof parsed === 'object' ? parsed : {};
            } catch (error) {
              return {};
            }
          }
        })();
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == appBridgeName,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }
        let payload = body["payload"] as? [String: Any] ?? [:]
        let callbackId = body["callbackId"] as? String ?? "ios-app-cb-\(Int64(Date().timeIntervalSince1970 * 1000))"
        if action == "scanCode" {
            startScanCode(requestId: callbackId)
        } else if action == "takePhoto" {
            startTakePhoto(requestId: callbackId, payload: payload)
        } else if action == "getNetworkState" {
            var data = networkState()
            data["requestId"] = callbackId
            emitApp("networkState", data: data)
        } else if action == "openWebView" {
            openWebView(requestId: callbackId, payload: payload)
        }
    }

    private func startScanCode(requestId: String) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentScanCodeController(requestId: requestId)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.presentScanCodeController(requestId: requestId)
                    } else {
                        self?.emitScanCodeDenied(requestId: requestId)
                    }
                }
            }
        default:
            emitScanCodeDenied(requestId: requestId)
        }
    }

    private func presentScanCodeController(requestId: String) {
        let controller = ZnhaasScanCodeViewController(requestId: requestId)
        controller.onResult = { [weak self] result in
            self?.emitApp("scanCodeResult", data: result)
        }
        present(controller, animated: true)
    }

    private func emitScanCodeDenied(requestId: String) {
        emitApp("scanCodeResult", data: [
            "requestId": requestId,
            "text": "",
            "format": "",
            "cancelled": true,
            "message": "Camera permission denied."
        ])
    }

    private func startTakePhoto(requestId: String, payload: [String: Any]) {
        pendingTakePhotoRequestId = requestId
        pendingTakePhotoMaxWidth = CGFloat((payload["maxWidth"] as? NSNumber)?.doubleValue ?? 1600)
        let qualityNumber = (payload["quality"] as? NSNumber)?.doubleValue ?? 80
        pendingTakePhotoQuality = CGFloat(max(1, min(100, qualityNumber)) / 100.0)

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            emitApp("takePhotoError", data: [
                "requestId": requestId,
                "cancelled": false,
                "message": "Camera is not available."
            ])
            pendingTakePhotoRequestId = nil
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentTakePhotoController()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.presentTakePhotoController()
                    } else {
                        self?.emitTakePhotoDenied(requestId: requestId)
                    }
                }
            }
        default:
            emitTakePhotoDenied(requestId: requestId)
        }
    }

    private func presentTakePhotoController() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        present(picker, animated: true)
    }

    private func emitTakePhotoDenied(requestId: String) {
        pendingTakePhotoRequestId = nil
        emitApp("takePhotoError", data: [
            "requestId": requestId,
            "cancelled": false,
            "message": "Camera permission denied."
        ])
    }

    private func openWebView(requestId: String, payload: [String: Any]) {
        let urlString = (payload["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = resolveWebViewURL(urlString) else {
            emitApp("openWebViewResult", data: [
                "requestId": requestId,
                "success": false,
                "url": urlString,
                "message": "Invalid or unsupported url."
            ])
            return
        }
        let controller = ZnhaasAppWebViewController(url: url, pageTitle: title.isEmpty ? "新页面" : title)
        navigationController?.pushViewController(controller, animated: true)
        emitApp("openWebViewResult", data: [
            "requestId": requestId,
            "success": true,
            "url": urlString
        ])
    }

    private func resolveWebViewURL(_ urlString: String) -> URL? {
        guard urlString.isEmpty == false else {
            return nil
        }
        if let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) {
            return url
        }
        let name = (urlString as NSString).deletingPathExtension
        let ext = (urlString as NSString).pathExtension.isEmpty ? "html" : (urlString as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    private func networkState() -> [String: Any] {
        ZnhaasReachability.currentState()
    }

    private func imageResult(from image: UIImage, requestId: String) -> [String: Any]? {
        let normalized = image.normalizedOrientation()
        let scaled = normalized.scaledToMaxSide(pendingTakePhotoMaxWidth)
        guard let data = scaled.jpegData(compressionQuality: pendingTakePhotoQuality) else {
            return nil
        }
        let base64 = data.base64EncodedString()
        return [
            "requestId": requestId,
            "cancelled": false,
            "image": [
                "base64": base64,
                "dataUrl": "data:image/jpeg;base64,\(base64)",
                "mimeType": "image/jpeg",
                "fileName": "photo_\(Int64(Date().timeIntervalSince1970 * 1000)).jpg",
                "width": Int(scaled.size.width),
                "height": Int(scaled.size.height),
                "sizeBytes": data.count
            ]
        ]
    }

    private func emitApp(_ type: String, data: [String: Any]) {
        var event: [String: Any] = [
            "type": type,
            "data": data,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if !JSONSerialization.isValidJSONObject(event) {
            event["data"] = ["message": "Invalid event payload"]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: event, options: []),
              let json = String(data: jsonData, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript("window.ZnhaasApp&&window.ZnhaasApp.__dispatch&&window.ZnhaasApp.__dispatch(\(json));", completionHandler: nil)
        }
    }
}

extension ZnhaasAppWebViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        let requestId = pendingTakePhotoRequestId ?? "ios-app-cb-\(Int64(Date().timeIntervalSince1970 * 1000))"
        pendingTakePhotoRequestId = nil
        picker.dismiss(animated: true) { [weak self] in
            self?.emitApp("takePhotoResult", data: [
                "requestId": requestId,
                "cancelled": true
            ])
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let requestId = pendingTakePhotoRequestId ?? "ios-app-cb-\(Int64(Date().timeIntervalSince1970 * 1000))"
        pendingTakePhotoRequestId = nil
        guard let image = info[.originalImage] as? UIImage else {
            picker.dismiss(animated: true) { [weak self] in
                self?.emitApp("takePhotoError", data: [
                    "requestId": requestId,
                    "cancelled": false,
                    "message": "Unable to read captured image."
                ])
            }
            return
        }

        let result = imageResult(from: image, requestId: requestId)
        picker.dismiss(animated: true) { [weak self] in
            if let result {
                self?.emitApp("takePhotoResult", data: result)
            } else {
                self?.emitApp("takePhotoError", data: [
                    "requestId": requestId,
                    "cancelled": false,
                    "message": "Unable to encode captured image."
                ])
            }
        }
    }
}

private enum ZnhaasReachability {
    static func currentState() -> [String: Any] {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        let flags: SCNetworkReachabilityFlags? = withUnsafePointer(to: &zeroAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                guard let reachability = SCNetworkReachabilityCreateWithAddress(nil, addressPointer) else {
                    return nil
                }
                var flags = SCNetworkReachabilityFlags()
                return SCNetworkReachabilityGetFlags(reachability, &flags) ? flags : nil
            }
        }

        let connected = isReachable(flags)
        let cellular = flags?.contains(.isWWAN) == true
        return [
            "connected": connected,
            "type": connected ? (cellular ? "cellular" : "wifi") : "none",
            "validated": connected,
            "metered": connected && cellular
        ]
    }

    private static func isReachable(_ flags: SCNetworkReachabilityFlags?) -> Bool {
        guard let flags, flags.contains(.reachable) else {
            return false
        }
        if flags.contains(.connectionRequired) == false {
            return true
        }
        return flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic)
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? self
    }

    func scaledToMaxSide(_ maxSide: CGFloat) -> UIImage {
        guard maxSide > 0 else {
            return self
        }
        let largest = max(size.width, size.height)
        guard largest > maxSide else {
            return self
        }
        let scale = maxSide / largest
        let newSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
        draw(in: CGRect(origin: .zero, size: newSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return scaled ?? self
    }
}
