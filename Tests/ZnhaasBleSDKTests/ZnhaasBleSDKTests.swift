import XCTest
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
}
