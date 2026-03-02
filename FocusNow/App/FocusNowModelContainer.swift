import Foundation
import SwiftData

enum FocusNowModelContainer {
    private static let storeDirectoryName = "FocusNow"
    private static let storeFileName = "FocusNow.store"

    static func make() -> ModelContainer {
        let schema = Schema([
            Profile.self,
            TimerConfig.self,
            WebsiteRule.self,
            BlockedAppRule.self,
            ScheduleRule.self,
            SessionRecord.self,
            AppSettings.self
        ])

        let storeURL = primaryStoreURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            archiveIncompatibleStoreArtifacts(at: storeURL)

            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Failed to initialize model container: \(error)")
            }
        }
    }

    private static func primaryStoreURL() -> URL {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        let directoryURL = applicationSupportURL.appendingPathComponent(storeDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let storeURL = directoryURL.appendingPathComponent(storeFileName, isDirectory: false)
        migrateLegacyDefaultStoreIfNeeded(to: storeURL)
        return storeURL
    }

    private static func migrateLegacyDefaultStoreIfNeeded(to destinationStoreURL: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationStoreURL.path) else { return }

        let legacyStoreURL = legacyDefaultStoreURL()
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else { return }

        let artifacts = storeArtifactURLs(for: legacyStoreURL)
        for artifactURL in artifacts where fileManager.fileExists(atPath: artifactURL.path) {
            let destinationArtifactURL: URL
            if artifactURL == legacyStoreURL {
                destinationArtifactURL = destinationStoreURL
            } else {
                destinationArtifactURL = destinationStoreURL.appendingPathExtension(artifactURL.pathExtension)
            }

            do {
                try fileManager.moveItem(at: artifactURL, to: destinationArtifactURL)
            } catch {
                // If moving the old store fails, leave it in place and let container creation recover below.
                return
            }
        }
    }

    private static func archiveIncompatibleStoreArtifacts(at storeURL: URL) {
        let fileManager = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")

        for artifactURL in storeArtifactURLs(for: storeURL) where fileManager.fileExists(atPath: artifactURL.path) {
            let archivedURL = artifactURL.deletingLastPathComponent()
                .appendingPathComponent("\(artifactURL.lastPathComponent).incompatible-\(timestamp)")

            do {
                try fileManager.moveItem(at: artifactURL, to: archivedURL)
            } catch {
                try? fileManager.removeItem(at: artifactURL)
            }
        }
    }

    private static func legacyDefaultStoreURL() -> URL {
        let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupportURL.appendingPathComponent("default.store", isDirectory: false)
    }

    private static func storeArtifactURLs(for storeURL: URL) -> [URL] {
        let shmURL = storeURL.appendingPathExtension("shm")
        let walURL = storeURL.appendingPathExtension("wal")
        return [storeURL, shmURL, walURL]
    }
}
