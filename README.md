# Znhaas BLE iOS SDK

一个面向 `znhaas` 安全帽设备的 iOS BLE SDK，最低支持 `iOS 11`。

当前版本已经按业务场景收敛为专用实现：

- 只扫描蓝牙名称前缀为 `znhaas` 的 BLE 设备
- 扫描结果主显示名只返回后缀编号
  - 例如：`znhaas_23070401` -> `23070401`
- 固定使用 znhaas UART Service
  - Service UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
  - Write UUID: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`
  - Notify UUID: `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`
- 按照业务控制协议封装 5 个控制动作
- 发送命令时不追加扩展字段
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

## 5 个控制动作

协议统一格式：

```text
V1|RECORD|ACTION|TIMESTAMP
```

当前封装的 5 个动作如下：

1. 开始录制：`ACTION = 1`
2. 停止录制：`ACTION = 0`
3. 查询状态：`ACTION = 2`
4. 禁止视频物理按键：`ACTION = 3`
5. 启用视频物理按键：`ACTION = 4`

示例：

```text
V1|RECORD|1|1715155200000
V1|RECORD|0|1715155205000
V1|RECORD|2|1715155210000
V1|RECORD|3|1715155215000
V1|RECORD|4|1715155220000
```

## 接入方式

### 1. Swift Package Manager

本地调试时，可以直接引用当前目录：

远程仓库发布后，可改为：

```swift
.package(url: "https://github.com/zhenglongzhang/ble-sdk-ios.git", from: "1.0.0")
```

## Demo App

当前仓库已经内置了一个原生 UIKit Demo 工程：

- Xcode 工程：[ZnhaasBleDemo.xcodeproj](/Users/zhenglongzhang/coding/ble-sdk-ios/DemoApp/ZnhaasBleDemo.xcodeproj)
- 主页控制器：[MainViewController.swift](/Users/zhenglongzhang/coding/ble-sdk-ios/DemoApp/ZnhaasBleDemo/MainViewController.swift:1)

Demo 提供以下能力：

- 扫描 `znhaas` 前缀 BLE 设备
- 点击设备进行连接
- 自动开启固定 Notify 特征监听
- 点击 5 个录制控制按钮发送命令
- 在页面底部实时查看连接日志、写入结果和设备回传

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
    client.enableFixedNotification(completion: nil)
}
```

### 4. 发送 5 个控制动作

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

当前控制方法包括：

- `startRecord(completion:)`
- `stopRecord(completion:)`
- `queryRecordStatus(completion:)`
- `disableVideoKey(completion:)`
- `enableVideoKey(completion:)`

`requestId` 用于业务侧日志关联；当前 SDK 实际下发给设备的控制报文格式为 `V1|RECORD|ACTION|TIMESTAMP`。

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
- `ZnhaasBleClient.buildRecordCommand(action:requestId:timestamp:)`

通知相关：

- `enableFixedNotification(completion:)`
- `disableFixedNotification(completion:)`
- `enableNotification(serviceUUID:characteristicUUID:completion:)`
- `disableNotification(serviceUUID:characteristicUUID:completion:)`

## 本地验证

- `swift test`
- `xcodebuild -scheme ZnhaasBleSDK -destination "generic/platform=iOS" build`
- `xcodebuild -project DemoApp/ZnhaasBleDemo.xcodeproj -scheme ZnhaasBleDemo -destination "generic/platform=iOS Simulator" build`
