import XCTest
import CoreBluetooth
import Foundation
@testable import ZnhaasBleSDK

final class ZnhaasBleSDKTests: XCTestCase {
    func testTargetNameMatching() {
        XCTAssertTrue(ZnhaasBleClient.isTargetDeviceName("znhaas_23070401"))
        XCTAssertTrue(ZnhaasBleClient.isTargetDeviceName("ZNHAAS-23070401"))
        XCTAssertFalse(ZnhaasBleClient.isTargetDeviceName("other_23070401"))
        XCTAssertFalse(ZnhaasBleClient.isTargetDeviceName(nil))
    }

    func testDisplayNameExtraction() {
        XCTAssertEqual(ZnhaasBleClient.extractDisplayName("znhaas_23070401"), "23070401")
        XCTAssertEqual(ZnhaasBleClient.extractDisplayName("znhaas-23070401"), "23070401")
        XCTAssertEqual(ZnhaasBleClient.extractDisplayName("znhaas"), "znhaas")
        XCTAssertEqual(ZnhaasBleClient.extractDisplayName(nil), "Unknown device")
    }

    func testRecordCommandAppendsRequestId() {
        let command = ZnhaasBleClient.buildRecordCommand(
            action: .startRecord,
            requestId: "req-123",
            timestamp: 1715155200000
        )
        XCTAssertEqual(command, "2|C|0|1|req-123|1715155200000||||||||\n")
        XCTAssertTrue(command.contains("req-123"))
    }

    func testRecordCommandUsesFixedV2Fields() {
        let command = ZnhaasBleClient.buildRecordCommand(
            action: .disableVideoKey,
            requestId: "req-123",
            timestamp: 1715155200000,
            extraFields: [
                "work_order": "WO-20250122",
                "task_id": "TASK-01",
                "device_id": "31011500991325140052",
                "empty_value": "",
                " ": "ignored"
            ]
        )

        XCTAssertEqual(command, "2|C|0|1|req-123|1715155200000|WO-20250122|TASK-01|31011500991325140052|||||\n")
        XCTAssertFalse(command.contains("empty_value="))
        XCTAssertFalse(command.contains("ignored"))
    }

    func testQueryStatusDoesNotSendBusinessFields() {
        let command = ZnhaasBleClient.buildRecordCommand(
            action: .queryStatus,
            requestId: "req-123",
            timestamp: 1715155200000,
            extraFields: [
                "work_order": "WO-20250122",
                "task_id": "TASK-01"
            ]
        )

        XCTAssertEqual(command, "2|C|1|3|req-123|1715155200000||||||||\n")
    }

    func testRequestIdUsesReqPrefix() {
        let requestId = ZnhaasBleClient.buildRequestId(action: .disableVideoKey)
        XCTAssertTrue(requestId.hasPrefix("req-"))
    }

    func testPermissionStateUsesPoweredOnAsAuthorized() {
        let permission = ZnhaasBleClient.resolvePermissionState(
            systemAuthorization: "notDetermined",
            centralState: .poweredOn
        )

        XCTAssertTrue(permission.granted)
        XCTAssertEqual(permission.authorization, "allowedAlways")
        XCTAssertEqual(permission.text, "已授权")
    }

    func testPermissionStateUsesPoweredOffAsAuthorized() {
        let permission = ZnhaasBleClient.resolvePermissionState(
            systemAuthorization: "notDetermined",
            centralState: .poweredOff
        )

        XCTAssertTrue(permission.granted)
        XCTAssertEqual(permission.authorization, "allowedAlways")
        XCTAssertEqual(permission.text, "已授权")
    }

    func testPermissionStateKeepsUnauthorizedAsDenied() {
        let permission = ZnhaasBleClient.resolvePermissionState(
            systemAuthorization: "allowedAlways",
            centralState: .unauthorized
        )

        XCTAssertFalse(permission.granted)
        XCTAssertEqual(permission.authorization, "denied")
        XCTAssertEqual(permission.text, "已拒绝")
    }

    func testDemoBridgeExposesAndroidJsonCompatibilityMethods() throws {
        let source = try demoMainViewControllerSource()
        [
            "startRecordJson",
            "stopRecordJson",
            "queryRecordStatusJson",
            "disableVideoKeyJson",
            "enableVideoKeyJson"
        ].forEach { method in
            XCTAssertGreaterThanOrEqual(source.occurrenceCount(of: "\(method): function"), 1, "Expected iOS BLE H5 bridge to expose \(method)")
        }

        [
            "scanCodeJson",
            "takePhotoJson",
            "openWebViewJson"
        ].forEach { method in
            XCTAssertGreaterThanOrEqual(source.occurrenceCount(of: "\(method): function"), 2, "Expected both iOS AppBridge scripts to expose \(method)")
        }
    }

    func testDemoAppUsesSimplifiedChineseAsDevelopmentLanguage() throws {
        let source = try demoProjectSource()
        XCTAssertTrue(source.contains("developmentRegion = \"zh-Hans\";"))
        XCTAssertTrue(source.contains("\"zh-Hans\","))
    }

    private func demoMainViewControllerSource() throws -> String {
        let packageRoot = packageRootURL()
        let sourceURL = packageRoot
            .appendingPathComponent("DemoApp")
            .appendingPathComponent("ZnhaasBleDemo")
            .appendingPathComponent("MainViewController.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func demoProjectSource() throws -> String {
        let packageRoot = packageRootURL()
        let sourceURL = packageRoot
            .appendingPathComponent("DemoApp")
            .appendingPathComponent("ZnhaasBleDemo.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func packageRootURL() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
