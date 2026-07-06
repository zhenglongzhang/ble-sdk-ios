# Znhaas BLE iOS SDK

一个面向 `znhaas` 安全帽设备的 iOS BLE SDK，最低支持 `iOS 11`。

当前版本已经按业务场景收敛为专用实现：

- 只扫描蓝牙名称前缀为 `znhaas` 的 BLE 设备
- 扫描结果主显示名只返回后缀编号
  - 例如：`znhaas_23070401` -> `23070401`
- 固定使用 znhaas UART Service
  - Service UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
  - Write UUID: `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`
  - Reply UUID: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`
- 设备业务回复优先使用 Notify/Indicate 监听，v2 回复格式为 `2|R|...`
- 如果 Reply 特征只能 Read，Demo 会在写入成功后读取一次作为诊断兜底
- 按照《蓝牙录制控制协议 v2.0》封装录制控制动作
- 控制命令使用固定 14 位字段：`work_order`、`task_id`、`device_id`
- 基于 iOS 原生 `CoreBluetooth` 实现，不依赖第三方 BLE 库

## 工程结构

- `Sources/ZnhaasBleSDK`
  - SDK 主代码
- `Tests/ZnhaasBleSDKTests`
  - 单元测试
- `DemoApp`
  - 可直接在 Xcode 中运行的 iOS Demo App
- `Examples/ExampleUsage.swift`
  - UIKit 接入示例

## 录制控制协议 v2

协议统一格式：

```text
VERSION|CMD_TYPE|COMMAND|ACTION|REQ_ID|TIMESTAMP|P1|P2|P3|P4|P5|P6|P7|P8\n
```

当前下发命令固定使用：

```text
2|C|COMMAND|ACTION|REQ_ID|TIMESTAMP|work_order|task_id|device_id|||||
```

当前封装动作如下：

1. 停止录制：`COMMAND=0`，`ACTION=0`
2. 开始录制并禁用视频物理按键：`COMMAND=0`，`ACTION=1`
3. 开始录制并启用视频物理按键：`COMMAND=0`，`ACTION=2`
4. 查询状态：`COMMAND=1`，`ACTION=3`

示例：

```text
2|C|0|1|req-1705939230000|1705939230000|WO-20250122|TASK-01|31011500991325140052|||||
2|C|0|2|req-1705939230000|1705939230000|WO-20250122|TASK-01|31011500991325140052|||||
2|C|0|0|req-1705939300000|1705939300000|WO-20250122|TASK-01|31011500991325140052|||||
2|C|1|3|req-1705939400000|1705939400000||||||||
```

## 接入方式

### 1. Swift Package Manager

本地调试时，可以直接引用当前目录：

远程仓库发布后，可改为：

```swift
.package(url: "https://github.com/zhenglongzhang/ble-sdk-ios.git", from: "1.0.0")
```

## Demo App

当前仓库已经内置了一个 WKWebView + H5 Demo 工程：

- Xcode 工程：[ZnhaasBleDemo.xcodeproj](/Users/zhenglongzhang/coding/ble-sdk-ios/DemoApp/ZnhaasBleDemo.xcodeproj)
- 主页控制器：[MainViewController.swift](/Users/zhenglongzhang/coding/ble-sdk-ios/DemoApp/ZnhaasBleDemo/MainViewController.swift:1)
- H5 页面：[znhaas_ble_demo.html](/Users/zhenglongzhang/coding/ble-sdk-ios/DemoApp/ZnhaasBleDemo/znhaas_ble_demo.html:1)

Demo 提供以下能力：

- 扫描 `znhaas` 前缀 BLE 设备
- 点击设备进行连接
- 自动监听固定 Service 下所有支持 Notify/Indicate 的特征
- H5 通过 `window.ZnhaasBleBridge` 调用原生 BLE 能力
- 点击 4 个录制控制按钮发送 v2 命令
- 在页面底部实时查看连接日志、写入结果和设备回复

说明：

- `DemoApp` 当前直接引用 `Sources/ZnhaasBleSDK` 下的 SDK 源码，目的是在较新的 Xcode 环境里仍然保持 Demo 工程最低 `iOS 11`
- SDK 的对外发布形态仍然是根目录下的 Swift Package

打开方式：

1. 用 Xcode 打开 [ZnhaasBleDemo.xcodeproj](/Users/zhenglongzhang/coding/ble-sdk-ios/DemoApp/ZnhaasBleDemo.xcodeproj)
2. 选择真机或 iOS 模拟器作为构建目标
3. 首次运行时允许蓝牙权限
4. 扫描并点击设备后，即可执行控制动作

### 2. Info.plist 权限说明

至少添加以下蓝牙权限文案：

- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`

建议文案：

```text
需要使用蓝牙扫描和连接 znhaas 安全帽设备，用于录制控制和状态回传。
```

## 重要平台差异

- iOS 不提供 BLE 设备的 MAC 地址，SDK 使用 `UUID identifier` 作为设备连接标识
- iOS 不允许 App 直接“打开蓝牙”，只能监听蓝牙状态并引导用户在系统中开启
- iOS BLE 扫描不需要定位权限，但仍需在 `Info.plist` 中声明蓝牙用途

## SDK 用法

### 1. 初始化

```swift
import ZnhaasBleSDK

final class DemoController: UIViewController {
    private let bleClient = ZnhaasBleClient()

    override func viewDidLoad() {
        super.viewDidLoad()
        bleClient.delegate = self
    }
}
```

### 2. 扫描

```swift
bleClient.startScan(duration: 12)
```

回调到：

```swift
func bleClient(_ client: ZnhaasBleClient, didDiscover device: ZnhaasBleDevice) {
    print(device.displayName) // 23070401
    print(device.identifier.uuidString)
}
```

### 3. 连接

```swift
bleClient.connect(device)
```

连接就绪回调：

```swift
func bleClient(_ client: ZnhaasBleClient, didBecomeReady device: ZnhaasBleDevice) {
    client.enableFixedServiceNotifications(completion: nil)
}
```

### 4. 发送录制控制动作

```swift
let requestId = bleClient.startRecord { result in
    switch result {
    case .success(let writeResult):
        print(writeResult.hexValue)
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

如需下发固定业务字段。当前 v2 协议只取 `work_order`、`task_id`、`device_id`：

```swift
let requestId = bleClient.startRecord(extraFields: [
    "work_order": "WO-20250122",
    "task_id": "TASK-01",
    "device_id": "31011500991325140052"
], completion: nil)
```

当前控制方法包括：

- `startRecord(completion:)`
- `stopRecord(completion:)`
- `queryRecordStatus(completion:)`
- `disableVideoKey(completion:)`
- `enableVideoKey(completion:)`
- `startRecord(extraFields:completion:)`
- `stopRecord(extraFields:completion:)`
- `queryRecordStatus(extraFields:completion:)`
- `disableVideoKey(extraFields:completion:)`
- `enableVideoKey(extraFields:completion:)`

`requestId` 用于业务侧日志关联；当前 SDK 实际下发给设备的是 v2 固定 14 位控制报文。

H5 JSBridge 示例：

```js
window.ZnhaasBleBridge.disableVideoKey({
  work_order: 'WO-20250122',
  task_id: 'TASK-01',
  device_id: '31011500991325140052'
})
```

### 5. 监听设备回传

```swift
func bleClient(
    _ client: ZnhaasBleClient,
    didReceive value: Data,
    stringValue: String?,
    hexValue: String,
    serviceUUID: CBUUID,
    characteristicUUID: CBUUID
) {
    print(stringValue ?? "")
    print(hexValue)
}
```

说明：

- v2 业务回复以 `2|R|...` 开头，Demo 会在 `data.response` 中提供结构化字段
- 如果 Demo 显示 `Read fallback value (not ACK)`，说明这是读取到的诊断值，不是设备业务回复

## 关键 API

`ZnhaasBleClient` 当前已经内置业务常量：

- `ZnhaasBleClient.targetDeviceNamePrefix`
- `ZnhaasBleClient.fixedServiceUUID`
- `ZnhaasBleClient.fixedWriteCharacteristicUUID`
- `ZnhaasBleClient.fixedNotifyCharacteristicUUID`

辅助方法：

- `ZnhaasBleClient.isTargetDeviceName(_:)`
- `ZnhaasBleClient.extractDisplayName(_:)`
- `ZnhaasBleClient.buildRequestId(action:)`
- `ZnhaasBleClient.buildRecordCommand(action:requestId:timestamp:extraFields:)`

通知相关：

- `enableFixedNotification(completion:)`
- `enableFixedServiceNotifications(completion:)`
- `disableFixedNotification(completion:)`
- `enableNotification(serviceUUID:characteristicUUID:completion:)`
- `disableNotification(serviceUUID:characteristicUUID:completion:)`
- `readFixedReply(completion:)`
- `read(serviceUUID:characteristicUUID:completion:)`

## 本地验证

- `swift test`
- `xcodebuild -scheme ZnhaasBleSDK -destination "generic/platform=iOS" build`
- `xcodebuild -project DemoApp/ZnhaasBleDemo.xcodeproj -scheme ZnhaasBleDemo -destination "generic/platform=iOS Simulator" build`
