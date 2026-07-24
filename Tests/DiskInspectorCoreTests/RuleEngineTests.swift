import Testing
@testable import DiskInspectorCore

@Suite("Finding rule classification")
struct RuleEngineTests {
    private let engine = RuleEngine()

    @Test("npm cache is regenerable and low risk")
    func npmCache() {
        let finding = engine.finding(for: measurement("/Users/test/.npm/_cacache"))
        #expect(finding.ruleIdentifier == "npm.cache")
        #expect(finding.category == .regenerableCache)
        #expect(finding.risk == .low)
        #expect(finding.potentialReclaimableBytes == 1_000_000)
    }

    @Test("Antigravity recordings are anomalous")
    func antigravityRecordings() {
        let finding = engine.finding(for: measurement("/Users/test/.gemini/antigravity/browser_recordings"))
        #expect(finding.ruleIdentifier == "gemini.antigravity.browser-recordings")
        #expect(finding.category == .anomalous)
    }

    @Test("Cursor state database is never a plain cache")
    func cursorStateDatabase() {
        let finding = engine.finding(for: measurement("/Users/test/Library/Application Support/Cursor/User/globalStorage/state.vscdb"))
        #expect(finding.ruleIdentifier == "cursor.state-database")
        #expect(finding.risk == .high)
        #expect(finding.potentialReclaimableBytes == nil)
    }

    @Test("WeChat container is user data")
    func weChatContainer() {
        let finding = engine.finding(for: measurement("/Users/test/Library/Containers/com.tencent.xinWeChat/Data"))
        #expect(finding.category == .userData)
        #expect(finding.risk == .high)
    }

    @Test("System paths prohibit manual cleanup", arguments: ["/private/var/vm", "/System/Library"])
    func systemPaths(path: String) {
        let finding = engine.finding(for: measurement(path))
        #expect(finding.category == .systemManaged)
        #expect(finding.risk == .prohibited)
        #expect(finding.potentialReclaimableBytes == nil)
    }

    @Test("Chrome local model is app managed")
    func chromeModel() {
        let finding = engine.finding(for: measurement("/Users/test/Library/Application Support/Google/Chrome/OnDeviceModel"))
        #expect(finding.ruleIdentifier == "chrome.on-device-model")
        #expect(finding.category == .appManaged)
    }

    @Test("Lookalike paths are not treated as protected application data")
    func lookalikePaths() {
        let paths = [
            "/tmp/private/var/vm/swapfile0",
            "/tmp/containers/com.tencent.xinwechat/data",
            "/tmp/cursor/state.vscdb",
            "/tmp/micromessenger",
            "/tmp/google/chrome/ondevicemodel",
            "/Users/test/project/library/caches/deep/nested"
        ]
        for path in paths {
            #expect(engine.finding(for: measurement(path)).ruleIdentifier == "unknown")
        }
    }

    private func measurement(_ path: String) -> DirectoryMeasurement {
        DirectoryMeasurement(
            path: path,
            allocatedBytes: 1_000_000,
            logicalBytes: 900_000,
            fileCount: 12,
            lastModified: nil
        )
    }
}
