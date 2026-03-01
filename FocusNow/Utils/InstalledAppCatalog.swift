import Foundation

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let url: URL
}

enum InstalledAppCatalog {
    static func discover() -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Setapp", isDirectory: true)
        ]

        var seenBundleIdentifiers = Set<String>()
        var seenPaths = Set<String>()
        var results: [InstalledApp] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let appURL as URL in enumerator {
                guard appURL.pathExtension.lowercased() == "app" else { continue }

                if shouldSkip(url: appURL, root: root) {
                    continue
                }

                guard let bundle = Bundle(url: appURL) else { continue }
                let bundleIdentifier = bundle.bundleIdentifier ?? ""

                guard !bundleIdentifier.isEmpty else { continue }
                guard !seenBundleIdentifiers.contains(bundleIdentifier) else { continue }
                guard !seenPaths.contains(appURL.path) else { continue }

                let appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent

                seenBundleIdentifiers.insert(bundleIdentifier)
                seenPaths.insert(appURL.path)

                results.append(
                    InstalledApp(
                        id: bundleIdentifier,
                        displayName: appName,
                        bundleIdentifier: bundleIdentifier,
                        url: appURL
                    )
                )
            }
        }

        return results.sorted {
            if $0.displayName.caseInsensitiveCompare($1.displayName) == .orderedSame {
                return $0.bundleIdentifier < $1.bundleIdentifier
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private static func shouldSkip(url: URL, root: URL) -> Bool {
        let rootDepth = root.pathComponents.count
        let appDepth = url.pathComponents.count
        return (appDepth - rootDepth) > 4
    }
}
