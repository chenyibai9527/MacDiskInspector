import Foundation
import Testing
@testable import MacDiskInspectorApp

@Suite("Privacy settings", .serialized)
@MainActor
struct PrivacySettingsTests {
    @Test("Other app data is disabled by default and covers both container roots")
    func otherAppDataDefaults() throws {
        let suiteName = "MacDiskInspectorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = InspectorViewModel(defaults: defaults)
        #expect(
            !model.isProtectedDirectoryEnabled(
                InspectorViewModel.ProtectedDirectory.otherAppData
            )
        )

        let paths = InspectorViewModel.ProtectedDirectory.otherAppData.relativePaths
        #expect(paths == ["Library/Containers", "Library/Group Containers"])
    }

    @Test("An existing preference does not opt into newly protected app data")
    func existingPreferencesRemainPrivate() throws {
        let suiteName = "MacDiskInspectorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            [InspectorViewModel.ProtectedDirectory.music.rawValue],
            forKey: "enabledProtectedDirectories"
        )

        let model = InspectorViewModel(defaults: defaults)
        #expect(model.isProtectedDirectoryEnabled(.music))
        #expect(!model.isProtectedDirectoryEnabled(.otherAppData))
    }

    @Test("Protected paths use the login account home directory")
    func protectedPathsUseLoginHome() {
        let loginHome = InspectorViewModel.loginHomeDirectory()
        #expect(loginHome.path.hasPrefix("/"))
        #expect(loginHome.lastPathComponent.isEmpty == false)

        let musicPath = InspectorViewModel.ProtectedDirectory.music
            .urls(homeDirectory: loginHome)
            .first
        #expect(musicPath?.path == loginHome.appendingPathComponent("Music").path)
    }
}
