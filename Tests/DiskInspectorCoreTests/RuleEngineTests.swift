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

    @Test("Explains common macOS and application support structure")
    func commonMacOSStructure() {
        let cases: [(path: String, rule: String, category: FindingCategory)] = [
            ("/Users/test/Library", "user.library-root", .appManaged),
            ("/Users/test/Library/Application Support", "user.application-support", .appManaged),
            ("/Users/test/Library/Application Support/Google", "google.application-data", .appManaged),
            ("/Users/test/Library/Containers", "user.containers-root", .appManaged),
            ("/Users/test/Library/Containers/com.example.editor", "user.container-data", .userData),
            ("/Users/test/Library/Containers/com.example.editor/Data", "user.container-data", .userData),
            ("/Users/test/Library/Containers/com.example.editor/Data/Documents", "user.container-data", .userData),
            ("/private/var/folders", "system.var-folders", .systemManaged),
            ("/Applications", "system.applications", .appManaged)
        ]

        for item in cases {
            let finding = engine.finding(for: measurement(item.path))
            #expect(finding.ruleIdentifier == item.rule)
            #expect(finding.category == item.category)
            #expect(finding.potentialReclaimableBytes == nil)
        }
    }

    @Test("Explains major developer tool storage")
    func developerStorage() {
        let cases: [(path: String, rule: String)] = [
            ("/Users/test/.npm", "npm.data"),
            ("/Users/test/.npm/_cacache/content-v2", "npm.cache"),
            ("/Users/test/.cache", "developer.generic-cache"),
            ("/Users/test/.nvm", "node.version-manager"),
            ("/Users/test/Library/Developer/Xcode/DerivedData", "xcode.derived-data"),
            ("/Users/test/Library/Developer/Xcode/Archives", "xcode.archives"),
            ("/Users/test/Library/Developer/CoreSimulator", "xcode.simulators"),
            ("/Users/test/Library/Containers/com.docker.docker", "docker.desktop-data"),
            ("/opt/homebrew", "homebrew.data"),
            ("/Users/test/.codex", "ai-tool.workspace-data")
        ]

        for item in cases {
            #expect(engine.finding(for: measurement(item.path)).ruleIdentifier == item.rule)
        }

        #expect(
            engine.finding(
                for: measurement("/Users/test/Library/Developer/Xcode/DerivedData")
            ).potentialReclaimableBytes == 1_000_000
        )
        #expect(
            engine.finding(
                for: measurement("/Users/test/Library/Developer/Xcode/Archives")
            ).potentialReclaimableBytes == nil
        )
    }

    @Test("Explains browser design media and cloud data")
    func creativeAndUserData() {
        let cases: [(path: String, rule: String)] = [
            ("/Users/test/Library/Application Support/Google/Chrome", "chrome.profile-data"),
            ("/Users/test/Library/Application Support/Microsoft Edge", "edge.profile-data"),
            ("/Users/test/Library/Application Support/Firefox/Profiles", "firefox.profile-data"),
            ("/Users/test/Library/Safari", "safari.user-data"),
            ("/Users/test/Library/Application Support/Adobe", "adobe.application-data"),
            ("/Users/test/Library/Caches/Adobe", "adobe.cache"),
            ("/Users/test/Library/Application Support/Figma", "figma.application-data"),
            ("/Users/test/Pictures/Photos Library.photoslibrary", "media.library-bundle"),
            ("/Users/test/Movies/Client Film.fcpbundle", "media.library-bundle"),
            ("/Users/test/Library/CloudStorage", "cloud-storage"),
            ("/Users/test/Library/Application Support/Steam", "steam.library")
        ]

        for item in cases {
            #expect(engine.finding(for: measurement(item.path)).ruleIdentifier == item.rule)
        }

        let photoLibrary = engine.finding(
            for: measurement("/Users/test/Pictures/Photos Library.photoslibrary")
        )
        #expect(photoLibrary.category == .userData)
        #expect(photoLibrary.risk == .high)
        #expect(photoLibrary.potentialReclaimableBytes == nil)
    }

    @Test("Lookalike paths are not treated as protected application data")
    func lookalikePaths() {
        let paths = [
            "/tmp/private/var/vm/swapfile0",
            "/tmp/containers/com.tencent.xinwechat/data",
            "/tmp/cursor/state.vscdb",
            "/tmp/micromessenger",
            "/tmp/google/chrome/ondevicemodel",
            "/Users/test/project/library/caches/deep/nested",
            "/tmp/users/test/library/application support",
            "/Users/test/project/.cache/deep/nested",
            "/Users/test/project/Library/Containers/com.example/Data/Documents"
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
