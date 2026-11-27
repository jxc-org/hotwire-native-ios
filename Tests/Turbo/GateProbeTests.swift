import XCTest

/// TEMPORARY: proves fork CI goes red on a failing test. Reverted in the next commit.
final class GateProbeTests: XCTestCase {
    func test_deliberateFailure_provesTheGateCanFail() {
        XCTFail("Deliberate failure: CI must report this run as failed.")
    }
}
