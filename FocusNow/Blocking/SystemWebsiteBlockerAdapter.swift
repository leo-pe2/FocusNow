import AppKit
import Foundation

@MainActor
final class SystemWebsiteBlockerAdapter: WebsiteBlocker {
    private enum BrowserKind: Sendable, Hashable {
        case safari
        case chromium
    }

    private struct BrowserTarget: Sendable, Hashable {
        let bundleIdentifier: String
        let displayName: String
        let kind: BrowserKind
    }

    private enum EnforcementResult: Sendable {
        case success
        case permissionDenied
        case browserNotFound
        case unsupportedBrowserModel
        case failed(code: Int?, message: String?)
    }

    private static let supportedBrowserCandidates: [BrowserTarget] = [
        BrowserTarget(bundleIdentifier: "com.apple.Safari", displayName: "Safari", kind: .safari),
        BrowserTarget(
            bundleIdentifier: "com.apple.SafariTechnologyPreview",
            displayName: "Safari Technology Preview",
            kind: .safari
        ),
        BrowserTarget(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome", kind: .chromium),
        BrowserTarget(
            bundleIdentifier: "com.google.Chrome.canary",
            displayName: "Google Chrome Canary",
            kind: .chromium
        ),
        BrowserTarget(bundleIdentifier: "org.chromium.Chromium", displayName: "Chromium", kind: .chromium),
        BrowserTarget(bundleIdentifier: "com.brave.Browser", displayName: "Brave", kind: .chromium),
        BrowserTarget(bundleIdentifier: "com.microsoft.edgemac", displayName: "Microsoft Edge", kind: .chromium),
        BrowserTarget(
            bundleIdentifier: "com.microsoft.edgemac.Beta",
            displayName: "Microsoft Edge Beta",
            kind: .chromium
        ),
        BrowserTarget(
            bundleIdentifier: "com.microsoft.edgemac.Dev",
            displayName: "Microsoft Edge Dev",
            kind: .chromium
        ),
        BrowserTarget(bundleIdentifier: "com.operasoftware.Opera", displayName: "Opera", kind: .chromium),
        BrowserTarget(bundleIdentifier: "com.operasoftware.OperaGX", displayName: "Opera GX", kind: .chromium),
        BrowserTarget(bundleIdentifier: "com.vivaldi.Vivaldi", displayName: "Vivaldi", kind: .chromium),
        BrowserTarget(bundleIdentifier: "company.thebrowser.Browser", displayName: "Arc", kind: .chromium)
    ]

    private var currentStatus: BlockerStatus = .inactive
    private var blockedHosts: [String] = []
    private var enforcementTask: Task<Void, Never>?
    private var targetBrowsers: [BrowserTarget] = []
    private var automationPermissionDenied = false

    func enable(profile: WebsiteBlockingProfile) {
        guard profile.mode == .blocklist else {
            stopEnforcement()
            currentStatus = .degraded("Allowlist mode requires extension backend")
            return
        }

        let normalized = normalizedDomains(from: profile.patterns)
        guard !normalized.isEmpty else {
            stopEnforcement()
            currentStatus = .inactive
            return
        }

        let supportedBrowsers = resolveSupportedBrowserTargets()
        guard !supportedBrowsers.isEmpty else {
            stopEnforcement()
            currentStatus = .degraded(
                "No supported browser found. Website blocking works in Safari and supported Chromium browsers."
            )
            return
        }

        blockedHosts = normalized
        targetBrowsers = supportedBrowsers
        automationPermissionDenied = false
        currentStatus = .active

        startEnforcementLoop()
    }

    func disable() {
        stopEnforcement()
        blockedHosts = []
        targetBrowsers = []
        automationPermissionDenied = false
        currentStatus = .inactive
    }

    func status() -> BlockerStatus {
        currentStatus
    }

    private func startEnforcementLoop() {
        stopEnforcement()

        let hosts = blockedHosts
        let browsers = targetBrowsers
        guard !hosts.isEmpty, !browsers.isEmpty else { return }

        let appleScriptSources = Dictionary(uniqueKeysWithValues: browsers.map {
            ($0.bundleIdentifier, buildAppleScript(blockedHosts: hosts, target: $0))
        })

        enforcementTask = Task.detached(priority: .utility) { [weak self] in
            var compiledScripts: [String: NSAppleScript] = [:]

            while !Task.isCancelled {
                var encounteredRecoverableFailure = false

                for target in browsers {
                    guard let appleScriptSource = appleScriptSources[target.bundleIdentifier] else { continue }
                    var compiledScript = compiledScripts[target.bundleIdentifier]
                    let result = Self.enforceInBrowser(
                        compiledScript: &compiledScript,
                        appleScriptSource: appleScriptSource,
                        target: target
                    )

                    if let compiledScript {
                        compiledScripts[target.bundleIdentifier] = compiledScript
                    } else {
                        compiledScripts.removeValue(forKey: target.bundleIdentifier)
                    }

                    if case .failed = result {
                        encounteredRecoverableFailure = true
                    }

                    let shouldStop = await MainActor.run { [weak self] in
                        guard let self else { return true }
                        return self.handleEnforcementResult(result, target: target)
                    }

                    if shouldStop {
                        return
                    }
                }

                if !encounteredRecoverableFailure {
                    await MainActor.run { [weak self] in
                        self?.clearRecoverableFailureStatusIfNeeded()
                    }
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopEnforcement() {
        enforcementTask?.cancel()
        enforcementTask = nil
    }

    private func resolveSupportedBrowserTargets() -> [BrowserTarget] {
        var resolved: [BrowserTarget] = []
        var seenBundleIdentifiers = Set<String>()

        if let defaultBrowser = resolveDefaultBrowserTarget() {
            let key = defaultBrowser.bundleIdentifier.lowercased()
            if seenBundleIdentifiers.insert(key).inserted {
                resolved.append(defaultBrowser)
            }
        }

        for candidate in Self.supportedBrowserCandidates {
            guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleIdentifier)
            else {
                continue
            }

            let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier ?? candidate.bundleIdentifier
            let key = bundleIdentifier.lowercased()
            guard seenBundleIdentifiers.insert(key).inserted else { continue }

            let displayName = browserDisplayName(
                applicationURL: applicationURL,
                fallbackBundleIdentifier: candidate.displayName
            )
            let kind = detectBrowserKind(applicationURL: applicationURL, bundleIdentifier: bundleIdentifier) ?? candidate.kind
            resolved.append(BrowserTarget(bundleIdentifier: bundleIdentifier, displayName: displayName, kind: kind))
        }

        return resolved
    }

    private func resolveDefaultBrowserTarget() -> BrowserTarget? {
        guard let appURL = defaultBrowserApplicationURL(),
              let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier,
              let kind = detectBrowserKind(applicationURL: appURL, bundleIdentifier: bundleIdentifier)
        else {
            return nil
        }

        return BrowserTarget(
            bundleIdentifier: bundleIdentifier,
            displayName: browserDisplayName(applicationURL: appURL, fallbackBundleIdentifier: bundleIdentifier),
            kind: kind
        )
    }

    private func defaultBrowserApplicationURL() -> URL? {
        guard let url = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        else {
            return nil
        }

        return appURL
    }

    private func browserDisplayName(applicationURL: URL, fallbackBundleIdentifier: String) -> String {
        guard let bundle = Bundle(url: applicationURL) else {
            return fallbackBundleIdentifier
        }

        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
    }

    private func detectBrowserKind(applicationURL: URL, bundleIdentifier: String) -> BrowserKind? {
        let loweredBundleIdentifier = bundleIdentifier.lowercased()
        if loweredBundleIdentifier == "com.apple.safari"
            || loweredBundleIdentifier == "com.apple.safaritechnologypreview" {
            return .safari
        }

        let resourcesURL = applicationURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let chromiumSdefPath = resourcesURL.appendingPathComponent("scripting.sdef").path
        if FileManager.default.fileExists(atPath: chromiumSdefPath)
            || isLikelyChromiumBundleIdentifier(loweredBundleIdentifier) {
            return .chromium
        }

        return nil
    }

    private func isLikelyChromiumBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let chromiumHints = [
            "chrome",
            "chromium",
            "brave",
            "edge",
            "opera",
            "vivaldi",
            "arc"
        ]

        return chromiumHints.contains { bundleIdentifier.contains($0) }
    }

    private func normalizedDomains(from patterns: [String]) -> [String] {
        var domains = Set<String>()

        for rawPattern in patterns {
            guard let domain = normalizeDomainPattern(rawPattern) else { continue }
            domains.insert(domain)
            if !domain.hasPrefix("www.") {
                domains.insert("www.\(domain)")
            }
        }

        return domains.sorted()
    }

    private func normalizeDomainPattern(_ rawPattern: String) -> String? {
        let trimmed = rawPattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !trimmed.isEmpty else { return nil }

        let withoutWildcard = trimmed
            .replacingOccurrences(of: "*.", with: "")
            .replacingOccurrences(of: ".*", with: "")

        if let url = URL(string: withoutWildcard), let host = url.host {
            return sanitizeHost(host)
        }

        if let url = URL(string: "https://\(withoutWildcard)"), let host = url.host {
            return sanitizeHost(host)
        }

        return sanitizeHost(withoutWildcard)
    }

    private func sanitizeHost(_ input: String) -> String? {
        var host = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        host = host.replacingOccurrences(of: "https://", with: "")
        host = host.replacingOccurrences(of: "http://", with: "")
        host = host.components(separatedBy: "/").first ?? host
        host = host.components(separatedBy: ":").first ?? host
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard host.contains("."), !host.contains(" ") else {
            return nil
        }

        return host
    }

    private func handleEnforcementResult(_ result: EnforcementResult, target: BrowserTarget) -> Bool {
        switch result {
        case .success:
            return false

        case .permissionDenied:
            automationPermissionDenied = true
            currentStatus = .degraded(
                "Allow FocusNow to control \(target.displayName). If no toggle exists yet, start a session once to trigger the macOS prompt, then check Privacy & Security > Automation."
            )
            stopEnforcement()
            return true

        case .browserNotFound:
            currentStatus = .degraded("Could not find \(target.displayName).")
            stopEnforcement()
            return true

        case .unsupportedBrowserModel:
            currentStatus = .degraded(
                "\(target.displayName) does not expose the browser automation FocusNow needs."
            )
            stopEnforcement()
            return true

        case .failed(let code, let message):
            currentStatus = .degraded(
                "Could not enforce website blocking in \(target.displayName)\(failureDetails(code: code, message: message))"
            )
            return false
        }
    }

    private func clearRecoverableFailureStatusIfNeeded() {
        guard !automationPermissionDenied else { return }
        guard case .degraded(let reason) = currentStatus else { return }
        guard reason.hasPrefix("Could not enforce website blocking in ") else { return }
        currentStatus = .active
    }

    nonisolated private static func enforceInBrowser(
        compiledScript: inout NSAppleScript?,
        appleScriptSource: String,
        target: BrowserTarget
    ) -> EnforcementResult {
        if NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty {
            return .success
        }

        if compiledScript == nil {
            compiledScript = NSAppleScript(source: appleScriptSource)
        }

        guard let script = compiledScript else {
            return .failed(code: nil, message: "AppleScript compilation failed")
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)

        guard let errorInfo else {
            return .success
        }

        let number = errorInfo[NSAppleScript.errorNumber] as? Int
        if number == -1743 {
            return .permissionDenied
        }

        if number == -43 {
            return .browserNotFound
        }

        if number == -1708 || number == -1728 || number == -10000 {
            return .unsupportedBrowserModel
        }

        let message = (errorInfo[NSAppleScript.errorMessage] as? String)
            ?? (errorInfo[NSAppleScript.errorBriefMessage] as? String)
        return .failed(code: number, message: message)
    }

    private func buildAppleScript(blockedHosts: [String], target: BrowserTarget) -> String {
        let blockedList = blockedHosts
            .map { "\"\(escapeForAppleScript($0))\"" }
            .joined(separator: ", ")

        let escapedBlockPage = escapeForAppleScript(Self.blockedPageDataURL)
        let escapedBlockJS = escapeForAppleScript(Self.blockedPageJavaScript)
        let escapedBundleIdentifier = escapeForAppleScript(target.bundleIdentifier)

        let applyBlockCommand: String
        switch target.kind {
        case .safari:
            applyBlockCommand = """
                                set URL of t to blockPage
                                delay 0.03
                                do JavaScript blockJS in t
            """
        case .chromium:
            applyBlockCommand = """
                                set URL of t to blockPage
                                delay 0.03
                                execute javascript blockJS in t
            """
        }

        return """
set blockedHosts to {\(blockedList)}
set blockPage to "\(escapedBlockPage)"
set blockJS to "\(escapedBlockJS)"

on shouldBlock(urlText, blockedHosts)
    repeat with blockedHost in blockedHosts
        if urlText contains (blockedHost as text) then
            return true
        end if
    end repeat
    return false
end shouldBlock

try
    tell application id "\(escapedBundleIdentifier)"
        if it is running then
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set urlText to URL of t
                        if urlText is not missing value and urlText does not start with "data:text/html" and urlText does not start with "about:blank" then
                            if my shouldBlock(urlText as text, blockedHosts) then
\(applyBlockCommand)
                            end if
                        end if
                    end try
                end repeat
            end repeat
        end if
    end tell
on error errMsg number errNum
    error errMsg number errNum
end try
"""
    }

    private func failureDetails(code: Int?, message: String?) -> String {
        var parts: [String] = []
        if let code {
            parts.append("error \(code)")
        }

        if let message {
            let cleanedMessage = message
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleanedMessage.isEmpty {
                parts.append(cleanedMessage)
            }
        }

        guard !parts.isEmpty else { return "" }
        return " (\(parts.joined(separator: ": ")))"
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static let blockedPageDataURL: String = {
        let html = """
<!doctype html>
<html>
<head>
<meta charset=\"utf-8\" />
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
<title>Blocked</title>
<style>
html, body {
    margin: 0;
    padding: 0;
    width: 100%;
    height: 100%;
    background: #ffffff;
    color: #111111;
    font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif;
}
body {
    display: flex;
    align-items: center;
    justify-content: center;
}
.message {
    font-size: 42px;
    font-weight: 700;
    line-height: 1.15;
    text-align: center;
    max-width: 720px;
    padding: 24px;
}
</style>
</head>
<body>
<div class=\"message\">Keep focusing on your task.</div>
</body>
</html>
"""

        let base64 = Data(html.utf8).base64EncodedString()
        return "data:text/html;charset=utf-8;base64,\(base64)"
    }()

    private static let blockedPageJavaScript: String = """
document.documentElement.innerHTML = `<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Blocked</title><style>html,body{margin:0;padding:0;width:100%;height:100%;background:#fff;color:#111;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}body{display:flex;align-items:center;justify-content:center}.message{font-size:42px;font-weight:700;line-height:1.15;text-align:center;max-width:720px;padding:24px}</style></head><body><div class="message">Keep focusing on your task.</div></body>`;
"""
}
