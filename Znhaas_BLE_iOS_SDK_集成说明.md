# Znhaas BLE iOS SDK 集成说明

## 1. 概要

本文档仅供内部接入参考，用于为 iOS 应用提供 znhaas 安全帽 BLE SDK 接口说明，禁止外传。

## 2. 业务说明

本文档对应的 SDK 兼容 znhaas 安全帽设备，包含蓝牙状态监听、蓝牙扫描、蓝牙连接、蓝牙监听数据、录制控制等说明。

当前 SDK 已按业务场景固定如下：

- 只扫描蓝牙名称前缀为 `znhaas` 的 BLE 设备
- 设备显示名仅返回后缀编号
  - 例如：`znhaas_23070401` 显示为 `23070401`
- 固定使用 znhaas UART Service
  - Service UUID：`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
  - Write UUID：`6E400002-B5A3-F393-E0A9-E50E24DCCA9E`
  - Notify UUID：`6E400003-B5A3-F393-E0A9-E50E24DCCA9E`
- 封装 5 个录制控制动作
- 控制报文不发送扩展字段

## 3. 环境要求

- iOS 11.0 及以上
- Xcode 15 及以上进行接入与调试更方便
- 设备支持 BLE 4.0 及以上
- 使用 Swift Package Manager 集成

## 4. SDK 集成

### 4.1 添加依赖

本地调试时：

```swift
.package(path: "/ble-sdk-ios")
```

远程发布后：

```swift
.package(url: "https://github.com/zhangzhenglong/ble-sdk-ios.git", from: "1.0.0")
```

### 4.2 引用模块

```swift
import ZnhaasBleSDK
```

### 4.3 Info.plist 权限配置

请在宿主 App 的 `Info.plist` 中添加：

- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`

建议说明文案：

```text
需要使用蓝牙扫描和连接 znhaas 安全帽设备，用于录制控制和状态回传。
```

## 5. iOS 平台说明

### 5.1 无法直接打开蓝牙

iOS 不允许第三方 App 直接开启系统蓝牙。SDK 可监听蓝牙状态，并在状态为关闭时提示业务层引导用户前往系统开启。

### 5.2 无法获取设备 MAC 地址

iOS 不暴露 BLE 设备 MAC 地址，SDK 使用 `UUID identifier` 作为连接标识。

### 5.3 无需定位权限

当前 SDK 仅使用 `CoreBluetooth` 完成扫描与连接，不主动申请定位权限。

## 6. 核心接口说明

### 6.1 初始化 SDK

```swift
final class DemoController: UIViewController {
    private let bleClient = ZnhaasBleClient()

    override func viewDidLoad() {
        super.viewDidLoad()
        bleClient.delegate = self
    }
}
```

### 6.2 蓝牙状态监听

```swift
func bleClient(_ client: ZnhaasBleClient, didUpdateState state: CBManagerState) {
    switch state {
    case .poweredOn:
        print("Bluetooth ready")
    case .poweredOff:
        print("Bluetooth off")
    default:
        break
    }
}
```

### 6.3 开始扫描

```swift
bleClient.startScan(duration: 12)
```

设备发现回调：

```swift
func bleClient(_ client: ZnhaasBleClient, didDiscover device: ZnhaasBleDevice) {
    print(device.displayName)
    print(device.identifier.uuidString)
}
```

### 6.4 停止扫描

```swift
bleClient.stopScan()
```

### 6.5 连接设备

```swift
bleClient.connect(device)
```

连接过程回调：

- `bleClient(_:isConnectingTo:)`
- `bleClient(_:didConnect:)`
- `bleClient(_:didDiscoverServices:for:)`
- `bleClient(_:didBecomeReady:)`
- `bleClient(_:didDisconnect:error:)`

### 6.6 开启固定回传通知

```swift
bleClient.enableFixedNotification { result in
    switch result {
    case .success:
        print("notify enabled")
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

设备数据回调：

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

## 7. 录制控制接口

### 7.1 控制协议

当前 SDK 实际发送给设备的报文格式：

```text
V1|RECORD|ACTION|TIMESTAMP
```

### 7.2 控制动作列表

| 方法 | Action 值 | 说明 |
| --- | --- | --- |
| `startRecord(completion:)` | `1` | 开始录制 |
| `stopRecord(completion:)` | `0` | 停止录制 |
| `queryRecordStatus(completion:)` | `2` | 查询录制状态 |
| `disableVideoKey(completion:)` | `3` | 禁止视频物理按键 |
| `enableVideoKey(completion:)` | `4` | 启用视频物理按键 |

### 7.3 调用示例

```swift
let requestId = bleClient.startRecord { result in
    switch result {
    case .success(let writeResult):
        print(writeResult.requestId ?? "")
        print(writeResult.stringValue ?? "")
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

说明：

- `requestId` 仅用于业务侧日志关联
- `requestId` 不会拼接进设备控制报文

## 8. 常用 API 速查

### 8.1 常量

- `ZnhaasBleClient.targetDeviceNamePrefix`
- `ZnhaasBleClient.fixedServiceUUID`
- `ZnhaasBleClient.fixedWriteCharacteristicUUID`
- `ZnhaasBleClient.fixedNotifyCharacteristicUUID`

### 8.2 工具方法

- `ZnhaasBleClient.isTargetDeviceName(_:)`
- `ZnhaasBleClient.extractDisplayName(_:)`
- `ZnhaasBleClient.buildRequestId(action:)`
- `ZnhaasBleClient.buildRecordCommand(action:requestId:timestamp:)`

## 9. 接入建议

- 建议在 `didBecomeReady` 回调后再发送录制控制命令
- 建议在进入设备列表页面时开始扫描，离开页面时停止扫描
- 建议业务层自行记录 `requestId`、时间戳、用户、设备标识，方便排查控制链路
- 建议在收到断开连接回调后清理 UI 状态

## 10. 注意事项

- 如果蓝牙未授权或已关闭，SDK 会通过错误回调返回原因
- 如果设备没有暴露固定 Write/Notify 特征，SDK 会返回特征未找到错误
- 当前 SDK 只适配 `znhaas` 前缀设备，不处理其他 BLE 外设
- 示例代码位于 `Examples/ExampleUsage.swift`

