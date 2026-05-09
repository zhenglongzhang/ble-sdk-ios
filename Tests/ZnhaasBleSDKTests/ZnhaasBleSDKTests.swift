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

    func testRecordCommandDoesNotAppendRequestId() {
        let command = ZnhaasBleClient.buildRecordCommand(
            action: .startRecord,
            requestId: "req-123",
            timestamp: 1715155200000
        )
        XCTAssertEqual(command, "V1|RECORD|1|1715155200000")
        XCTAssertFalse(command.contains("req-123"))
    }

    func testRequestIdContainsActionCodePrefix() {
        let requestId = ZnhaasBleClient.buildRequestId(action: .disableVideoKey)
        XCTAssertTrue(requestId.hasPrefix("3-"))
    }
}

