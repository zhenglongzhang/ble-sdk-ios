# 工单 H5 AppBridge iOS 接入说明

## 1. 概要

本文档用于说明 iOS Demo WKWebView 中提供给工单 H5 使用的 `ZnhaasAppBridge` 能力。当前 iOS 侧已支持扫码、拍照、有网无网判断、打开新的 WebView，最低支持 iOS 11。

App 只负责代理系统能力并把结果回传给 H5，图片上传、业务鉴权、工单字段处理由 H5 自行完成。

## 2. H5 可调用方法

```js
window.ZnhaasAppBridge.scanCode()
window.ZnhaasAppBridge.takePhoto()
window.ZnhaasAppBridge.getNetworkState()
window.ZnhaasAppBridge.openWebView({ url, title })

window.ZnhaasAppBridge.scanCode({
  source: 'work-order'
})

window.ZnhaasAppBridge.takePhoto({
  maxWidth: 1600,
  quality: 80
})

window.ZnhaasAppBridge.openWebView({
  url: 'https://www.longfor.com',
  title: '工单详情'
})
```

iOS 基于 `WKScriptMessageHandler` 实现，调用方法会立即返回本次请求的 `requestId`，真实结果通过事件回调返回。建议客户 H5 统一监听事件，不依赖同步返回值。

## 3. 原生事件回调

SDK 会将异步结果派发给 H5：

```js
window.ZnhaasApp = {
  onNativeEvent(event) {
    console.log(event.type, event.data)
  }
}
```

同时也会派发浏览器事件：

```js
window.addEventListener('ZnhaasAppEvent', function (event) {
  console.log(event.detail.type, event.detail.data)
})
```

事件通用结构如下：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `type` | `string` | 事件名称 |
| `data` | `object` | 事件数据 |
| `timestamp` | `number` | 原生派发事件的毫秒时间戳 |

## 4. 扫码

### 4.1 调用

```js
const requestId = window.ZnhaasAppBridge.scanCode()
```

### 4.2 返回事件

事件名：`scanCodeResult`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `requestId` | `string` | 本次扫码请求 ID |
| `text` | `string` | 扫码文本结果，用户取消时为空字符串 |
| `format` | `string` | 码类型，例如 `QR_CODE`、`CODE_128`、`EAN_13` |
| `cancelled` | `boolean` | 是否取消 |
| `message` | `string` | 可选，异常或权限拒绝说明 |

### 4.3 Mock 数据

```json
{
  "type": "scanCodeResult",
  "data": {
    "requestId": "ios-app-cb-1705939230000-1",
    "text": "WO-20250122",
    "format": "QR_CODE",
    "cancelled": false
  },
  "timestamp": 1705939231000
}
```

用户取消或权限拒绝：

```json
{
  "type": "scanCodeResult",
  "data": {
    "requestId": "ios-app-cb-1705939230000-1",
    "text": "",
    "format": "",
    "cancelled": true,
    "message": "Camera permission denied."
  },
  "timestamp": 1705939231000
}
```

## 5. 拍照

### 5.1 调用

```js
const requestId = window.ZnhaasAppBridge.takePhoto({
  maxWidth: 1600,
  quality: 80
})
```

参数说明：

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `maxWidth` | `number` | `1600` | 图片最长边压缩到该尺寸以内 |
| `quality` | `number` | `80` | JPEG 压缩质量，范围 `1-100` |

### 5.2 返回事件

事件名：`takePhotoResult`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `requestId` | `string` | 本次拍照请求 ID |
| `cancelled` | `boolean` | 是否取消 |
| `image.base64` | `string` | JPEG base64，不带 data URL 前缀 |
| `image.dataUrl` | `string` | 可直接用于 `<img src>` 的 data URL |
| `image.mimeType` | `string` | 固定为 `image/jpeg` |
| `image.fileName` | `string` | SDK 生成的文件名 |
| `image.width` | `number` | 压缩后图片宽度 |
| `image.height` | `number` | 压缩后图片高度 |
| `image.sizeBytes` | `number` | 压缩后图片字节数 |

异常事件名：`takePhotoError`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `requestId` | `string` | 本次拍照请求 ID |
| `cancelled` | `boolean` | 固定为 `false` |
| `message` | `string` | 错误说明 |

### 5.3 Mock 数据

```json
{
  "type": "takePhotoResult",
  "data": {
    "requestId": "ios-app-cb-1705939230000-2",
    "cancelled": false,
    "image": {
      "base64": "/9j/4AAQSkZJRgABAQAAAQABAAD...",
      "dataUrl": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD...",
      "mimeType": "image/jpeg",
      "fileName": "photo_1705939230000.jpg",
      "width": 1200,
      "height": 1600,
      "sizeBytes": 245678
    }
  },
  "timestamp": 1705939231000
}
```

用户取消：

```json
{
  "type": "takePhotoResult",
  "data": {
    "requestId": "ios-app-cb-1705939230000-2",
    "cancelled": true
  },
  "timestamp": 1705939231000
}
```

拍照失败：

```json
{
  "type": "takePhotoError",
  "data": {
    "requestId": "ios-app-cb-1705939230000-2",
    "cancelled": false,
    "message": "Camera is not available."
  },
  "timestamp": 1705939231000
}
```

## 6. 有网无网判断

### 6.1 调用

```js
const requestId = window.ZnhaasAppBridge.getNetworkState()
```

iOS 侧该方法返回 `requestId`，同时派发 `networkState` 事件。当前使用 iOS 11 可用的 `SystemConfiguration` Reachability 实现。

### 6.2 返回字段

事件名：`networkState`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `requestId` | `string` | 本次网络状态请求 ID |
| `connected` | `boolean` | 是否有可用网络 |
| `type` | `string` | 网络类型，可能为 `wifi`、`cellular`、`none` |
| `validated` | `boolean` | iOS 侧与 `connected` 保持一致 |
| `metered` | `boolean` | 蜂窝网络为 `true`，其他为 `false` |

### 6.3 Mock 数据

```json
{
  "type": "networkState",
  "data": {
    "requestId": "ios-app-cb-1705939230000-3",
    "connected": true,
    "type": "wifi",
    "validated": true,
    "metered": false
  },
  "timestamp": 1705939231000
}
```

无网：

```json
{
  "type": "networkState",
  "data": {
    "requestId": "ios-app-cb-1705939230000-3",
    "connected": false,
    "type": "none",
    "validated": false,
    "metered": false
  },
  "timestamp": 1705939231000
}
```

## 7. 打开新的 WebView

### 7.1 调用

```js
const requestId = window.ZnhaasAppBridge.openWebView({
  url: 'https://www.longfor.com',
  title: '工单详情'
})
```

也可以直接传 URL：

```js
const requestId = window.ZnhaasAppBridge.openWebView('https://www.longfor.com')
```

参数说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `url` | `string` | 要打开的页面地址，当前支持 `http`、`https`、`file`，Demo 还支持 bundle 内 HTML 文件名 |
| `title` | `string` | 新 WebView 顶部标题，可选 |

### 7.2 返回事件

事件名：`openWebViewResult`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `requestId` | `string` | 本次打开请求 ID |
| `success` | `boolean` | 是否成功发起打开 |
| `url` | `string` | 本次请求打开的 URL |
| `message` | `string` | 可选，失败原因 |

### 7.3 Mock 数据

```json
{
  "type": "openWebViewResult",
  "data": {
    "requestId": "ios-app-cb-1705939230000-4",
    "success": true,
    "url": "https://www.longfor.com"
  },
  "timestamp": 1705939231000
}
```

URL 不合法：

```json
{
  "type": "openWebViewResult",
  "data": {
    "requestId": "ios-app-cb-1705939230000-4",
    "success": false,
    "url": "",
    "message": "Invalid or unsupported url."
  },
  "timestamp": 1705939231000
}
```

## 8. Demo 页面

当前 iOS Demo 默认加载：

```text
znhaas_app_tests.html
```

测试页面如下：

| 页面 | 说明 |
| --- | --- |
| `znhaas_app_tests.html` | 所有测试功能入口 |
| `znhaas_scan_code_test.html` | 扫码能力测试 |
| `znhaas_take_photo_test.html` | 拍照能力测试 |
| `znhaas_network_test.html` | 有网无网判断测试 |
| `znhaas_open_webview_test.html` | 打开新 WebView 测试 |
| `znhaas_webview_target.html` | 新 WebView 本地目标测试页 |
| `znhaas_ble_demo.html` | 原 BLE 控制测试 |

## 9. iOS 权限说明

扫码和拍照都需要相机权限，Demo 已在 `Info.plist` 中配置：

```xml
<key>NSCameraUsageDescription</key>
<string>需要使用相机完成工单扫码和拍照上传。</string>
```

如果宿主 App 集成该能力，也需要在宿主 App 的 `Info.plist` 中配置相机权限说明。
