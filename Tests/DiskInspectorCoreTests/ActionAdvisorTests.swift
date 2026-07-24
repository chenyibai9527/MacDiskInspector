import Testing
@testable import DiskInspectorCore

@Suite("Safe action allowlist")
struct ActionAdvisorTests {
    private let advisor = ActionAdvisor()
    private let engine = RuleEngine()

    @Test("npm commands come only from fixed templates")
    func npmCommands() {
        let finding = engine.finding(for: measurement("/Users/test/.npm/_cacache"))
        let commands = advisor.actions(for: finding).compactMap { action -> String? in
            switch action.kind {
            case .copyInspectionCommand, .copyOfficialCleanupCommand:
                action.value
            default:
                nil
            }
        }
        #expect(Set(commands) == Set(["npm cache verify", "npm cache clean --force"]))
        #expect(!commands.contains { $0.contains(finding.path) })
        #expect(!commands.contains { $0.contains("rm ") })
    }

    @Test("High-risk data never receives a shell command")
    func highRiskData() {
        for path in [
            "/Users/test/Library/Application Support/Cursor/state.vscdb",
            "/Users/test/Library/Containers/com.tencent.xinWeChat/Data"
        ] {
            let finding = engine.finding(for: measurement(path))
            let actions = advisor.actions(for: finding)
            #expect(!actions.contains {
                $0.kind == .copyInspectionCommand || $0.kind == .copyOfficialCleanupCommand
            })
        }
    }

    @Test("System-managed data offers only non-destructive actions")
    func systemManagedData() {
        let finding = engine.finding(for: measurement("/private/var/vm"))
        #expect(advisor.actions(for: finding).allSatisfy { !$0.isDestructive })
    }

    private func measurement(_ path: String) -> DirectoryMeasurement {
        DirectoryMeasurement(path: path, allocatedBytes: 100, logicalBytes: 100, fileCount: 1, lastModified: nil)
    }
}
