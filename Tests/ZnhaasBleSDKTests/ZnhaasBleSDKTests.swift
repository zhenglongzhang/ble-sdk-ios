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
        XCTAssertEqual(command, "V1|RECORD|1|req-123|1715155200000")
        XCTAssertTrue(command.contains("req-123"))
    }

    func testRecordCommandAppendsNonEmptyExtraFields() {
        let command = ZnhaasBleClient.buildRecordCommand(
            action: .startRecord,
            requestId: "req-123",
            timestamp: 1715155200000,
            extraFields: [
                "work_order": "WO-20250122",
                "task_id": "TASK-01",
                "empty_value": "",
                " ": "ignored"
            ]
        )

        XCTAssertTrue(command.contains("|work_order=WO-20250122"))
        XCTAssertTrue(command.contains("|task_id=TASK-01"))
        XCTAssertFalse(command.contains("empty_value="))
        XCTAssertFalse(command.contains("ignored"))
    }

    func testRequestIdUsesReqPrefix() {
        let requestId = ZnhaasBleClient.buildRequestId(action: .disableVideoKey)
        XCTAssertTrue(requestId.hasPrefix("req-"))
    }
}
