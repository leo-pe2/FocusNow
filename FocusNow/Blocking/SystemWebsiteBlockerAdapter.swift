import AppKit
import Foundation

@MainActor
final class SystemWebsiteBlockerAdapter: WebsiteBlocker {
    private enum BrowserResolution {
        case unresolved
        case unsupported(String)
        case supported(BrowserTarget)
    }

    private enum BrowserKind {
        case safari
        case chromium
    }

    private struct BrowserTarget {
        let bundleIdentifier: String
        let displayName: String
        let kind: BrowserKind
    }

    private enum EnforcementResult {
        case success
        case permissionDenied
        case browserNotFound
        case unsupportedBrowserModel
        case failed(code: Int?, message: String?)
    }

    private var currentStatus: BlockerStatus = .inactive
    private var blockedHosts: [String] = []
    private var enforcementTask: Task<Void, Never>?
    private var targetBrowser: BrowserTarget?
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

        let browserResolution = resolveDefaultBrowserTarget()
        switch browserResolution {
        case .unresolved:
            stopEnforcement()
            currentStatus = .degraded("Could not resolve default browser")
            return
        case .unsupported(let reason):
            stopEnforcement()
            currentStatus = .degraded(reason)
            return
        case .supported:
            break
        }
        guard case .supported(let browser) = browserResolution else { return }

        blockedHosts = normalized
        targetBrowser = browser
        automationPermissionDenied = false
        currentStatus = .active

        startEnforcementLoop()
    }

    func disable() {
        stopEnforcement()
        blockedHosts = []
        targetBrowser = nil
        automationPermissionDenied = false
        currentStatus = .inactive
    }

    func status() -> BlockerStatus {
        currentStatus
    }

    private func startEnforcementLoop() {
        stopEnforcement()

        guard let targetBrowser else { return }
        let hosts = blockedHosts

        enforcementTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let result = self.enforceInDefaultBrowser(blockedHosts: hosts, target: targetBrowser)

                switch result {
                case .success:
                    if !self.automationPermissionDenied, case .degraded = self.currentStatus {
                        self.currentStatus = .active
                    }

                case .permissionDenied:
                    self.automationPermissionDenied = true
                    self.currentStatus = .degraded(
                        "Allow FocusNow to control \(targetBrowser.displayName). If no toggle exists yet, start a session once to trigger the macOS prompt, then check Privacy & Security > Automation."
                    )
                    self.stopEnforcement()
                    return

                case .browserNotFound:
                    self.currentStatus = .degraded(
                        "Could not find \(targetBrowser.displayName). Re-select your default browser in System Settings > Desktop & Dock."
                    )
                    self.stopEnforcement()
                    return

                case .unsupportedBrowserModel:
                    self.currentStatus = .degraded(
                        "\(targetBrowser.displayName) does not expose tab automation; use Safari or a Chromium browser as default"
                    )
                    self.stopEnforcement()
                    return

                case .failed(let code, let message):
                    self.currentStatus = .degraded(
                        "Could not enforce website blocking in \(targetBrowser.displayName)\(self.failureDetails(code: code, message: message))"
                    )
                }

                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func stopEnforcement() {
        enforcementTask?.cancel()
        enforcementTask = nil
    }

    private func resolveDefaultBrowserTarget() -> BrowserResolution {
        guard let appURL = defaultBrowserApplicationURL(),
              let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier
        else {
            return .unresolved
        }

        let displayName = defaultBrowserDisplayName(applicationURL: appURL, fallbackBundleIdentifier: bundleIdentifier)
        guard let kind = detectBrowserKind(applicationURL: appURL, bundleIdentifier: bundleIdentifier) else {
            return .unsupported("\(displayName) does not expose tab automation; use Safari or a Chromium browser as default")
        }

        return .supported(BrowserTarget(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            kind: kind
        ))
    }

    private func defaultBrowserApplicationURL() -> URL? {
        guard let url = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        else {
            return nil
        }

        return appURL
    }

    private func defaultBrowserDisplayName(applicationURL: URL, fallbackBundleIdentifier: String) -> String {
        guard let bundle = Bundle(url: applicationURL) else {
            return fallbackBundleIdentifier
        }

        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
    }

    private func detectBrowserKind(applicationURL: URL, bundleIdentifier: String) -> BrowserKind? {
        let loweredBundleIdentifier = bundleIdentifier.lowercased()
        if loweredBundleIdentifier == "com.apple.safari" {
            return .safari
        }

        let resourcesURL = applicationURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let chromiumSdefPath = resourcesURL.appendingPathComponent("scripting.sdef").path
        if FileManager.default.fileExists(atPath: chromiumSdefPath) || isLikelyChromiumBundleIdentifier(loweredBundleIdentifier) {
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

    private func enforceInDefaultBrowser(blockedHosts: [String], target: BrowserTarget) -> EnforcementResult {
        if NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty {
            return .success
        }

        let appleScriptSource = buildAppleScript(blockedHosts: blockedHosts, target: target)
        guard let script = NSAppleScript(source: appleScriptSource) else {
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
