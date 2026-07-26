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

    @Test("System privacy databases are excluded by default")
    func systemPrivacyDatabaseDefaults() throws {
        let suiteName = "MacDiskInspectorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = InspectorViewModel(defaults: defaults)
        let protectedPaths = Set(
            InspectorViewModel.ProtectedDirectory.allCases
                .filter { !model.isProtectedDirectoryEnabled($0) }
                .flatMap(\.relativePaths)
        )

        #expect(protectedPaths.contains("Library/Calendars"))
        #expect(protectedPaths.contains("Library/Application Support/AddressBook"))
        #expect(protectedPaths.contains("Library/Reminders"))
        #expect(protectedPaths.contains("Library/HomeKit"))
        #expect(protectedPaths.contains("Library/Photos"))
        #expect(protectedPaths.contains("Library/MediaAnalysis"))
        #expect(protectedPaths.contains("Library/Caches/com.apple.Photos"))
        #expect(protectedPaths.contains("Library/Application Support/MediaLibrary"))
        #expect(protectedPaths.contains("Library/Caches/com.apple.Music"))
        #expect(protectedPaths.contains("Library/Caches/com.apple.itunescloudd"))
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

        let musicPaths = InspectorViewModel.ProtectedDirectory.music
            .urls(homeDirectory: loginHome)
            .map(\.path)
        #expect(musicPaths.contains(loginHome.appendingPathComponent("Music").path))
        #expect(
            musicPaths.contains(
                loginHome.appendingPathComponent(
                    "Library/Caches/com.apple.Music"
                ).path
            )
        )
    }

    @Test("Full-volume protection includes the login account")
    func localHomesIncludeLoginAccount() {
        let loginHome = InspectorViewModel.loginHomeDirectory().standardizedFileURL.path
        let localHomes = InspectorViewModel.localUserHomeDirectories()
            .map(\.standardizedFileURL.path)

        #expect(localHomes.contains(loginHome))
        #expect(localHomes.allSatisfy { $0.hasPrefix("/Users/") })
    }

    @Test("Protected-directory opt-ins never apply to other accounts")
    func optInsAreScopedToLoginAccount() {
        let loginHome = URL(fileURLWithPath: "/Users/current", isDirectory: true)
        let otherHome = URL(fileURLWithPath: "/Users/other", isDirectory: true)
        let exclusions = InspectorViewModel.protectedDirectoryExclusions(
            homeDirectories: [loginHome, otherHome],
            loginHomeDirectory: loginHome,
            allowedForLoginAccount: [.music]
        )
        let paths = Set(exclusions.map(\.path))

        #expect(!paths.contains("/Users/current/Music"))
        #expect(!paths.contains("/Users/current/Library/Caches/com.apple.Music"))
        #expect(paths.contains("/Users/other/Music"))
        #expect(paths.contains("/Users/other/Library/Caches/com.apple.Music"))
        #expect(paths.contains("/Users/current/Pictures"))
        #expect(paths.contains("/Users/other/Pictures"))
    }

    @Test("Rescan keeps media service paths excluded when no opt-in is stored")
    func rescanConfigurationKeepsMediaServicesPrivate() throws {
        let suiteName = "MacDiskInspectorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = InspectorViewModel(defaults: defaults)
        let loginHome = URL(fileURLWithPath: "/Users/current", isDirectory: true)
        let exclusions = InspectorViewModel.protectedDirectoryExclusions(
            homeDirectories: [loginHome],
            loginHomeDirectory: loginHome,
            allowedForLoginAccount: model.enabledProtectedDirectories
        )
        let paths = Set(exclusions.map(\.path))

        #expect(paths.contains("/Users/current/Music"))
        #expect(paths.contains("/Users/current/Library/Photos"))
        #expect(paths.contains("/Users/current/Library/MediaAnalysis"))
        #expect(paths.contains("/Users/current/Library/Caches/com.apple.Music"))
        #expect(paths.contains("/Users/current/Library/Caches/com.apple.Photos"))
    }
}
