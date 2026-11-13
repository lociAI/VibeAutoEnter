import Foundation
import AppKit
import Combine
import UserNotifications
import ApplicationServices
import SwiftUI

// MARK: - Notification Style

enum NotificationStyle: String, CaseIterable {
    case banner, alert, soundOnly
}

// MARK: - Watched App

struct WatchedApp: Identifiable {
    let id = UUID()
    let name: String
    let bundleId: String
    var isEnabled: Bool
    var isCLI: Bool
    var icon: NSImage?

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty == false
    }
}

// MARK: - Activity Entry

struct ActivityEntry: Identifiable {
    let id = UUID()
    let message: String
    let time: Date
    let icon: String
    let color: Color

    init(_ message: String, icon: String = "circle.fill", color: Color = .secondary) {
        self.message = message
        self.time = Date()
        self.icon = icon
        self.color = color
    }
}

// MARK: - CLI Prompt Action

enum CLIPromptAction {
    case confirmYes(matchedText: String, signature: String)
    case confirmChoice(matchedText: String, signature: String)
    case confirmReturn(matchedText: String, signature: String)

    var matchedText: String {
        switch self {
        case .confirmYes(let m, _): return m
        case .confirmChoice(let m, _): return m
        case .confirmReturn(let m, _): return m
        }
    }

    var signature: String {
        switch self {
        case .confirmYes(_, let s): return s
        case .confirmChoice(_, let s): return s
        case .confirmReturn(_, let s): return s
        }
    }

    var description: String {
        switch self {
        case .confirmYes(let m, _): return "Auto-Confirm (Yes): \"\(m)\""
        case .confirmChoice(let m, _): return "Auto-Confirm (Choice 1): \"\(m)\""
        case .confirmReturn(let m, _): return "Auto-Confirm (⏎): \"\(m)\""
        }
    }
}

// MARK: - Terminal Window Record

struct TerminalWindowRecord {
    let id: Int
    let name: String
    let text: String
}

// MARK: - AutoEnterMonitor

@MainActor
class AutoEnterMonitor: ObservableObject {

    static let shared = AutoEnterMonitor()

    // MARK: Published State
    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "Active • Multi-window scanner & swapper"
    @Published var autoEnterEnabled: Bool = true
    @Published var enterDelay: Double = 1.0
    @Published var enterPressCount: Int = 0
    @Published var cliEnterPressCount: Int = 0

    // CLI Auto-Pilot Controls
    @Published var cliAutoAcceptEnabled: Bool = true
    @Published var cliAutoPickNumberEnabled: Bool = true
    @Published var cliEnterDelay: Double = 0.5

    // Multi-Terminal Window Swapping
    @Published var autoSwapWindows: Bool = true
    @Published var swapInterval: Double = 3.0

    // AI Completion Notification
    @Published var notifyOnCompletion: Bool = true
    @Published var playSoundOnCompletion: Bool = true
    @Published var notificationStyle: NotificationStyle = .banner
    @Published var lastCompletionTime: Date? = nil

    // Activity & Permissions
    @Published var activityLog: [ActivityEntry] = []
    @Published var watchedApps: [WatchedApp] = AutoEnterMonitor.defaultWatchedApps()
    @Published var hasAccessibilityPermission: Bool = false

    // MARK: Private
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var swapTimer: Timer?
    private var aiStateTracker = AIStateTracker()
    private var cliTracker = CLITracker()
    private var isScanning = false

    // UI Patterns indicating AI thinking
    private let thinkingPatterns = [
        "Generating", "Thinking", "Working", "Processing",
        "Writing", "Analyzing", "Computing", "Loading…",
        "Thought for", "Running command...",
        "●●●", "...", "⠿", "⠽", "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", "⣷", "⣯", "⣟", "⡿", "⢿"
    ]

    // Patterns indicating GUI AI has finished
    private let donePatterns = [
        "Accept", "Run", "Apply", "Retry",
        "Copy", "Done", "✓", "Complete", "Keep changes"
    ]

    // MARK: - Init
    private init() {
        checkAccessibilityPermission()
        setupAppTracking()
    }

    // MARK: - Default Apps
    static func defaultWatchedApps() -> [WatchedApp] {
        let appDefs: [(String, String, Bool)] = [
            ("Terminal", "com.apple.Terminal", true),
            ("iTerm2", "com.googlecode.iterm2", true),
            ("Warp", "dev.warp.Warp-Stable", true),
            ("Ghostty", "com.mitchellh.ghostty", true),
            ("Alacritty", "org.alacritty", true),
            ("Kitty", "net.kovidgoyal.kitty", true),
            ("WezTerm", "com.github.wez.wezterm", true),
            ("Cursor", "com.todesktop.230313mzl4w4u92", false),
            ("Windsurf", "com.codeium.windsurf", false),
            ("VS Code", "com.microsoft.VSCode", false),
            ("Claude", "com.anthropic.claudefordesktop", false),
            ("ChatGPT", "com.openai.chat", false),
            ("Zed", "dev.zed.Zed", false),
            ("Xcode", "com.apple.dt.Xcode", false),
        ]
        return appDefs.map { (name, bundleId, isCLI) in
            WatchedApp(
                name: name,
                bundleId: bundleId,
                isEnabled: true,
                isCLI: isCLI,
                icon: iconForBundle(bundleId)
            )
        }
    }

    private static func iconForBundle(_ bundleId: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    // MARK: - Accessibility Check
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        hasAccessibilityPermission = trusted

        if !trusted {
            requestAccessibilityPermission()
        }

        start()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                let currentTrusted = AXIsProcessTrusted()
                let wasTrusted = self?.hasAccessibilityPermission ?? false
                self?.hasAccessibilityPermission = currentTrusted
                if currentTrusted && !wasTrusted {
                    self?.addActivity("✅ Accessibility permission active", icon: "checkmark.circle.fill", color: .green)
                    self?.start()
                }
            }
        }
    }

    // MARK: - App Tracking
    private func setupAppTracking() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAppIcons()
            }
            .store(in: &cancellables)
    }

    private func refreshAppIcons() {
        for i in watchedApps.indices {
            watchedApps[i].icon = AutoEnterMonitor.iconForBundle(watchedApps[i].bundleId)
        }
    }

    // MARK: - Toggle Running
    func toggleRunning() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        isRunning = true
        statusMessage = "Active • Auto-patrolling all terminals"
        addActivity("Monitoring is ACTIVE", icon: "play.fill", color: .green)
        startPolling()
        startSwapTimer()
        startGlobalKeyMonitor()
    }

    func stop() {
        isRunning = false
        statusMessage = "Paused"
        addActivity("Monitoring paused", icon: "pause.fill", color: .orange)
        stopPolling()
        stopSwapTimer()
        stopGlobalKeyMonitor()
    }

    func restartApp() {
        let appUrl = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appUrl, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Global Key Monitor
    private func startGlobalKeyMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }
    }

    private func stopGlobalKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              isWatchedAndEnabled(bundleId: app.bundleIdentifier ?? "") else { return }

        if event.keyCode == 36 {
            aiStateTracker.markPromptSent(in: app.bundleIdentifier ?? "")
        }
    }

    // MARK: - Polling Loop
    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollAllApps()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Window Swap Timer (Every Few Seconds)
    func updateSwapTimer() {
        stopSwapTimer()
        if isRunning && autoSwapWindows {
            startSwapTimer()
        }
    }

    private func startSwapTimer() {
        stopSwapTimer()
        guard autoSwapWindows else { return }

        let timer = Timer(timeInterval: max(1.5, swapInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cycleTerminalWindowsIfMultiple()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        swapTimer = timer
    }

    private func stopSwapTimer() {
        swapTimer?.invalidate()
        swapTimer = nil
    }

    // MARK: - Cycle to next terminal window if multiple open
    private func cycleTerminalWindowsIfMultiple() {
        guard isRunning, autoSwapWindows, !isScanning else { return }

        // Swap Terminal windows
        if isWatchedAndEnabled(bundleId: "com.apple.Terminal") {
            let script = """
            tell application "Terminal"
                activate
                set winCount to count of windows
                if winCount > 1 then
                    set idList to id of windows
                    set nextId to item 2 of idList
                    set index of (first window whose id is nextId) to 1
                    return name of first window
                end if
            end tell
            """
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let res = appleScript.executeAndReturnError(&error)
                if let winName = res.stringValue, !winName.isEmpty {
                    addActivity("Patrolling: Swapped to [\(winName)]", icon: "arrow.triangle.2.circlepath", color: .cyan)
                    scanAllTerminalWindows()
                }
            }
        }
    }

    private func pollAllApps() {
        guard isRunning, !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        // 1. Scan EVERY open Apple Terminal window & tab
        if isWatchedAndEnabled(bundleId: "com.apple.Terminal") {
            scanAllTerminalWindows()
        }

        // 2. Scan EVERY open iTerm2 window & session
        if isWatchedAndEnabled(bundleId: "com.googlecode.iterm2") {
            scanAllITerm2Windows()
        }

        // 3. Scan GUI / IDE apps and other terminals
        let otherApps = watchedApps.filter { $0.isEnabled && $0.isRunning && $0.bundleId != "com.apple.Terminal" && $0.bundleId != "com.googlecode.iterm2" }
        for app in otherApps {
            guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId).first else { continue }
            pollGUIApp(runningApp: runningApp, appInfo: app)
        }
    }

    // MARK: - Multi-Window Terminal Scanner
    private func scanAllTerminalWindows() {
        let script = """
        tell application "Terminal"
            set res to ""
            repeat with w in windows
                set res to res & "===WIN_ID:" & (id of w) & "===NAME:" & (name of w) & "===TEXT:\\n" & (contents of selected tab of w) & "\\n===END_WIN===\\n"
            end repeat
            return res
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return }
        let output = appleScript.executeAndReturnError(&error)
        guard let rawOutput = output.stringValue, !rawOutput.isEmpty else { return }

        let windowBlocks = rawOutput.components(separatedBy: "===END_WIN===")
        for block in windowBlocks {
            guard let winId = extractInt(from: block, prefix: "===WIN_ID:"),
                  let winName = extractString(from: block, prefix: "===NAME:"),
                  let text = extractContent(from: block, after: "===TEXT:\n") else { continue }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            processSingleCLIWindow(windowId: winId, windowName: winName, text: trimmed, appBundleId: "com.apple.Terminal", appName: "Terminal")
        }
    }

    // MARK: - Multi-Window iTerm2 Scanner
    private func scanAllITerm2Windows() {
        let script = """
        tell application "iTerm2"
            set res to ""
            repeat with w in windows
                repeat with s in sessions of w
                    set res to res & "===WIN_NAME:" & (name of w) & "===TEXT:\\n" & (text of s) & "\\n===END_WIN===\\n"
                end repeat
            end repeat
            return res
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return }
        let output = appleScript.executeAndReturnError(&error)
        guard let rawOutput = output.stringValue, !rawOutput.isEmpty else { return }

        let windowBlocks = rawOutput.components(separatedBy: "===END_WIN===")
        for (idx, block) in windowBlocks.enumerated() {
            guard let winName = extractString(from: block, prefix: "===WIN_NAME:"),
                  let text = extractContent(from: block, after: "===TEXT:\n") else { continue }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            processSingleCLIWindow(windowId: idx + 1, windowName: winName, text: trimmed, appBundleId: "com.googlecode.iterm2", appName: "iTerm2")
        }
    }

    // MARK: - Process Single CLI Window
    private func processSingleCLIWindow(windowId: Int, windowName: String, text: String, appBundleId: String, appName: String) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }

        let windowKey = "\(appBundleId)_\(windowId)"
        let recentLines = lines.suffix(20).joined(separator: "\n")

        // 1. Completion check
        checkCLICompletion(text: recentLines, appBundleId: appBundleId, appName: appName)

        // 2. Auto-Accept Action Check
        guard autoEnterEnabled, let action = detectCLIPromptAction(lines: lines) else {
            // When no prompt is active, reset signature after idle cooldown so future prompts can trigger
            cliTracker.resetSignatureIfIdle(windowKey: windowKey)
            return
        }

        guard cliTracker.shouldTrigger(windowKey: windowKey, signature: action.signature) else { return }
        cliTracker.markActionScheduled(windowKey: windowKey, signature: action.signature)

        addActivity("\(action.description) in [\(windowName)]", icon: "checkmark.seal.fill", color: .green)

        // Immediately swap to THIS window so the input lands directly
        DispatchQueue.main.asyncAfter(deadline: .now() + cliEnterDelay) { [weak self] in
            guard let self, self.isRunning else {
                self?.cliTracker.markActionCompleted(windowKey: windowKey)
                return
            }
            self.executeCLIAction(windowId: windowId, action: action, appBundleId: appBundleId, windowName: windowName)
        }
    }

    // MARK: - Execute CLI Action to Specific Window
    private func executeCLIAction(windowId: Int, action: CLIPromptAction, appBundleId: String, windowName: String) {
        let windowKey = "\(appBundleId)_\(windowId)"
        defer {
            cliTracker.markActionCompleted(windowKey: windowKey)
        }

        if appBundleId == "com.apple.Terminal" {
            let script = """
            tell application "Terminal"
                activate
                set index of (first window whose id is \(windowId)) to 1
            end tell
            tell application "System Events"
                set frontmost of process "Terminal" to true
                delay 0.1
                tell process "Terminal"
                    key code 36
                end tell
            end tell
            """

            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let err = error {
                    NSLog("VibeAutoEnter Terminal AppleScript Error: %@", err)
                    let msg = err[NSAppleScript.errorMessage] as? String ?? "\(err)"
                    addActivity("⚠️ Script error: \(msg)", icon: "exclamationmark.triangle.fill", color: .red)
                    // Fallback to hardware event ONLY if AppleScript failed
                    postReturnKey()
                }
            }
        } else if appBundleId == "com.googlecode.iterm2" {
            let script = """
            tell application "iTerm2"
                activate
            end tell
            tell application "System Events"
                set frontmost of process "iTerm2" to true
                delay 0.1
                tell process "iTerm2"
                    key code 36
                end tell
            end tell
            """

            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let err = error {
                    NSLog("VibeAutoEnter iTerm2 AppleScript Error: %@", err)
                    postReturnKey()
                }
            }
        }

        cliEnterPressCount += 1
        enterPressCount += 1
        addActivity("⚡ Pressed ⏎ in [\(windowName)]", icon: "return.left", color: .purple)
    }

    // MARK: - Detect Prompt Action Type
    private func detectCLIPromptAction(lines: [String]) -> CLIPromptAction? {
        // Inspect up to the last 20 non-empty lines to capture the full prompt and options block
        let recentLines = Array(lines.suffix(20))
        guard !recentLines.isEmpty else { return nil }

        let lastLine = recentLines.last ?? ""

        // Helper to check if a line looks like it already has an answer entered
        func isAlreadyAnswered(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let patterns = [
                #"(?:\[[yY]/[nN]\]|\([yY]/[nN]\))\s*[yYnN1](?:es|o)?"#,
                #"(?:choice|selection|option)\s*\[\d+\]\s*:\s*\d+"#,
                #"(?:\[\d+-\d+\]|\(\d+-\d+\))\s*:\s*\d+"#,
                #"[?:]\s*[yYnN1]\s*$"#
            ]
            for pat in patterns {
                if trimmed.range(of: pat, options: .regularExpression) != nil {
                    return true
                }
            }
            return false
        }

        if isAlreadyAnswered(lastLine) {
            return nil
        }

        // Helper to build a stable signature from the matched line and surrounding context
        func makeSignature(type: String, pattern: String, index: Int) -> String {
            let start = max(0, index - 2)
            let end = min(recentLines.count - 1, index + 2)
            let context = recentLines[start...end].joined(separator: " ").lowercased()
            return "\(type)::\(pattern)::\(context)"
        }

        // 1. Explicit [y/n] prompts
        let explicitYesPatterns = [
            "[y/n]", "[y/n/?]", "(y/n)", "[yes/no]",
            "(yes/no)", "proceed? [y/n]", "continue? [y/n]",
            "are you sure? [y/n]", "allow this command? [y/n]",
            "run command? [y/n]", "execute command? [y/n]",
            "do you want to proceed? [y/n]", "type 'yes' to proceed",
            "(y/n)?", "[y/n]?"
        ]

        if cliAutoAcceptEnabled {
            for (idx, line) in recentLines.enumerated().reversed() {
                let distFromBottom = recentLines.count - 1 - idx
                if distFromBottom > 15 { break }
                let l = line.lowercased()
                if isAlreadyAnswered(line) { continue }

                for p in explicitYesPatterns {
                    if l.contains(p) {
                        let sig = makeSignature(type: "yes", pattern: p, index: idx)
                        return .confirmYes(matchedText: p, signature: sig)
                    }
                }

                let ynRegex = try? NSRegularExpression(
                    pattern: #"(?:\[[yY]/[nN]\]|\([yY]/[nN]\)|\[[yY]/[nN]/\?\])"#,
                    options: []
                )
                if let match = ynRegex?.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)),
                   let range = Range(match.range, in: line) {
                    let matched = String(line[range])
                    let sig = makeSignature(type: "yes", pattern: matched, index: idx)
                    return .confirmYes(matchedText: matched, signature: sig)
                }
            }
        }

        // 2. Option 1 / Choice prompts
        let optionOnePatterns = [
            "run this command?",
            "execute this command?",
            "requesting permission for:",
            "allow command?",
            "allow this command?",
            "allow tool?",
            "allow this tool?",
            "> 1. yes, run command",
            "1. yes, run command",
            "> 1. yes, accept this change",
            "1. yes, accept this change",
            "> 1. yes",
            "> 1.",
            "1. yes",
            "1. allow",
            "1. run",
            "1. accept",
            "pick a number", "pick an option", "select an option",
            "select option", "enter choice", "enter selection",
            "choose an option", "choice [1]:", "selection [1]:",
            "enter a number", "default 1", "default: 1",
            "select [1-", "pick [1-", "choose [1-", "option [1]:"
        ]

        if cliAutoPickNumberEnabled {
            for (idx, line) in recentLines.enumerated().reversed() {
                let distFromBottom = recentLines.count - 1 - idx
                if distFromBottom > 15 { break }
                let l = line.lowercased()
                if isAlreadyAnswered(line) { continue }

                for p in optionOnePatterns {
                    if l.contains(p) {
                        let sig = makeSignature(type: "choice", pattern: p, index: idx)
                        return .confirmChoice(matchedText: p, signature: sig)
                    }
                }

                let numberRegex = try? NSRegularExpression(
                    pattern: #"(?:(?:pick|select|choose|enter)\s+(?:a\s+)?(?:number|option|choice).{0,30}\[[0-9]+\]?|\[[0-9]+-[0-9]+\]\s*[:\?]?\s*$|\[1\]\s*[:\?]?\s*$)"#,
                    options: [.caseInsensitive]
                )
                if let match = numberRegex?.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)),
                   let range = Range(match.range, in: line) {
                    let matched = String(line[range])
                    let sig = makeSignature(type: "choice", pattern: matched, index: idx)
                    return .confirmChoice(matchedText: matched, signature: sig)
                }
            }
        }

        // 3. Return / Enter to continue prompts
        let returnPatterns = [
            "press enter to continue",
            "press enter to accept",
            "press [enter] to continue",
            "press <enter> to continue",
            "press return to continue",
            "hit enter to continue",
            "(enter to accept)",
            "[enter to accept]",
            "[enter to confirm]",
            "(enter to confirm)",
            "default: yes",
            "default: y",
            "default: enter",
            "accept changes?",
            "accept this change?",
            "apply changes?",
            "apply this change?",
            "accept this file edit?",
            "approve?",
            "authorize?",
            "do you want to proceed",
            "proceed?"
        ]

        if cliAutoAcceptEnabled {
            for (idx, line) in recentLines.enumerated().reversed() {
                let distFromBottom = recentLines.count - 1 - idx
                if distFromBottom > 15 { break }
                let l = line.lowercased()

                for p in returnPatterns {
                    if l.contains(p) {
                        let sig = makeSignature(type: "return", pattern: p, index: idx)
                        return .confirmReturn(matchedText: p, signature: sig)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - CLI Completion Detection
    private func checkCLICompletion(text: String, appBundleId: String, appName: String) {
        let isThinkingNow = thinkingPatterns.contains { text.localizedCaseInsensitiveContains($0) }
        let wasThinking = aiStateTracker.isThinking(bundleId: appBundleId)

        let hasIdlePrompt = text.hasSuffix("> ") || text.hasSuffix("$ ") || text.hasSuffix("➜ ") || text.hasSuffix("❯ ") || text.hasSuffix("? ")

        if wasThinking && !isThinkingNow && (hasIdlePrompt || text.contains("✓") || text.contains("Done") || text.contains("Finished")) {
            aiStateTracker.markComplete(bundleId: appBundleId)
            handleAICompletion(appName: appName)
        } else if isThinkingNow {
            aiStateTracker.markThinking(bundleId: appBundleId)
        }
    }

    // MARK: - GUI App Monitoring (Cursor, VS Code, Claude, Windsurf, etc.)
    private func pollGUIApp(runningApp: NSRunningApplication, appInfo: WatchedApp) {
        let axApp = AXUIElementCreateApplication(runningApp.processIdentifier)
        var windowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)

        guard let window = windowRef else { return }
        let axWindow = window as! AXUIElement

        let texts = collectText(from: axWindow, depth: 0, maxDepth: 6)
        let combined = texts.joined(separator: " ")

        let wasThinking = aiStateTracker.isThinking(bundleId: appInfo.bundleId)
        let nowThinking = thinkingPatterns.contains { combined.localizedCaseInsensitiveContains($0) }
        let nowHasAcceptButton = donePatterns.contains { combined.localizedCaseInsensitiveContains($0) }

        if wasThinking && !nowThinking && nowHasAcceptButton {
            aiStateTracker.markComplete(bundleId: appInfo.bundleId)
            handleAICompletion(appName: appInfo.name)
        } else if nowThinking {
            aiStateTracker.markThinking(bundleId: appInfo.bundleId)
        }

        if autoEnterEnabled {
            checkForAutoEnterOpportunity(axWindow: axWindow, app: appInfo, combined: combined)
        }
    }

    // MARK: - Collect UI Text via Accessibility
    private func collectText(from element: AXUIElement, depth: Int, maxDepth: Int) -> [String] {
        guard depth <= maxDepth else { return [] }

        var results: [String] = []

        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if let val = valueRef as? String, !val.isEmpty {
            results.append(val)
        }

        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        if let desc = descRef as? String, !desc.isEmpty {
            results.append(desc)
        }

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        if let title = titleRef as? String, !title.isEmpty {
            results.append(title)
        }

        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if let children = childrenRef as? [AXUIElement] {
            for child in children.prefix(25) {
                results.append(contentsOf: collectText(from: child, depth: depth + 1, maxDepth: maxDepth))
            }
        }

        return results
    }

    // MARK: - GUI Auto-Enter Logic
    private func checkForAutoEnterOpportunity(axWindow: AXUIElement, app: WatchedApp, combined: String) {
        let promptReadyIndicators = [
            "Press Enter to send", "Hit Enter", "Send message", "⌘↵", "Cmd+Enter"
        ]

        let hasPromptReady = promptReadyIndicators.contains { combined.localizedCaseInsensitiveContains($0) }

        if hasPromptReady && aiStateTracker.shouldAutoEnter(bundleId: app.bundleId) {
            aiStateTracker.scheduleAutoEnter(bundleId: app.bundleId)
            scheduleGUIEnterPress(delay: enterDelay, in: app)
        }
    }

    private func scheduleGUIEnterPress(delay: Double, in app: WatchedApp) {
        addActivity("Auto-Enter scheduled for \(app.name)", icon: "return.left", color: .purple)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRunning, self.autoEnterEnabled else { return }
            self.pressEnterInGUIApp(appInfo: app)
        }
    }

    private func pressEnterInGUIApp(appInfo: WatchedApp) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: appInfo.bundleId).first else { return }

        let source = CGEventSource(stateID: .hidSystemState)

        if runningApp.isActive {
            let globalDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
            let globalUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
            globalDown?.post(tap: .cghidEventTap)
            globalUp?.post(tap: .cghidEventTap)
        } else {
            let pid = runningApp.processIdentifier
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
            keyDown?.postToPid(pid)
            keyUp?.postToPid(pid)
        }

        enterPressCount += 1
        addActivity("⏎ Pressed Enter in \(appInfo.name)", icon: "return.left", color: .purple)
    }

    // MARK: - AI Completion Handler
    private func handleAICompletion(appName: String) {
        lastCompletionTime = Date()
        addActivity("✅ AI finished in \(appName)", icon: "checkmark.circle.fill", color: .green)

        guard notifyOnCompletion else { return }

        switch notificationStyle {
        case .banner, .alert:
            sendNotification(appName: appName)
        case .soundOnly:
            playCompletionSound()
        }

        if playSoundOnCompletion {
            playCompletionSound()
        }
    }

    private func sendNotification(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "✅ AI Finished"
        content.body = "\(appName) has completed its task! Time to review."
        content.sound = notificationStyle == .alert ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func playCompletionSound() {
        NSSound(named: "Glass")?.play()
    }

    // MARK: - Helpers
    func setApp(_ app: WatchedApp, enabled: Bool) {
        if let idx = watchedApps.firstIndex(where: { $0.id == app.id }) {
            watchedApps[idx].isEnabled = enabled
        }
    }

    private func isWatchedAndEnabled(bundleId: String) -> Bool {
        watchedApps.first { $0.bundleId == bundleId && $0.isEnabled } != nil
    }

    func addActivity(_ message: String, icon: String = "circle.fill", color: Color = .secondary) {
        let entry = ActivityEntry(message, icon: icon, color: color)
        activityLog.insert(entry, at: 0)
        if activityLog.count > 50 {
            activityLog = Array(activityLog.prefix(50))
        }
    }

    func testEnter() {
        let script = """
        tell application "Terminal"
            activate
        end tell
        tell application "System Events"
            tell process "Terminal"
                key code 36
            end tell
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
        addActivity("⚡ Sent manual Return to Terminal", icon: "bolt.fill", color: .cyan)
    }
}

// MARK: - Direct Hardware Keystroke Delivery

private func postReturnKey() {
    let src = CGEventSource(stateID: .combinedSessionState)
    if let retDown = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true),
       let retUp = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false) {
        retDown.post(tap: .cghidEventTap)
        usleep(25_000)
        retUp.post(tap: .cghidEventTap)
    }
}

// MARK: - Text Parsing Utilities

private func extractInt(from text: String, prefix: String) -> Int? {
    guard let start = text.range(of: prefix)?.upperBound else { return nil }
    let remainder = text[start...]
    guard let end = remainder.range(of: "===")?.lowerBound else { return nil }
    return Int(remainder[..<end])
}

private func extractString(from text: String, prefix: String) -> String? {
    guard let start = text.range(of: prefix)?.upperBound else { return nil }
    let remainder = text[start...]
    guard let end = remainder.range(of: "===")?.lowerBound else { return nil }
    return String(remainder[..<end])
}

private func extractContent(from text: String, after prefix: String) -> String? {
    guard let start = text.range(of: prefix)?.upperBound else { return nil }
    return String(text[start...])
}

// MARK: - AI State Tracker

class AIStateTracker {
    private struct AppState {
        var isThinking: Bool = false
        var lastPromptSent: Date? = nil
        var lastAutoEnterScheduled: Date? = nil
        var completionCount: Int = 0
    }

    private var states: [String: AppState] = [:]
    private let lock = NSLock()

    func isThinking(bundleId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return states[bundleId]?.isThinking ?? false
    }

    func markThinking(bundleId: String) {
        lock.lock(); defer { lock.unlock() }
        if states[bundleId] == nil { states[bundleId] = AppState() }
        states[bundleId]?.isThinking = true
    }

    func markComplete(bundleId: String) {
        lock.lock(); defer { lock.unlock() }
        states[bundleId]?.isThinking = false
        states[bundleId]?.completionCount += 1
    }

    func markPromptSent(in bundleId: String) {
        lock.lock(); defer { lock.unlock() }
        if states[bundleId] == nil { states[bundleId] = AppState() }
        states[bundleId]?.lastPromptSent = Date()
    }

    func shouldAutoEnter(bundleId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let state = states[bundleId],
              let lastScheduled = state.lastAutoEnterScheduled else { return true }
        return Date().timeIntervalSince(lastScheduled) > 5
    }

    func scheduleAutoEnter(bundleId: String) {
        lock.lock(); defer { lock.unlock() }
        if states[bundleId] == nil { states[bundleId] = AppState() }
        states[bundleId]?.lastAutoEnterScheduled = Date()
    }
}

// MARK: - CLI Prompt Tracker & Deduplicator

class CLITracker {
    private struct WindowState {
        var lastHandledSignature: String = ""
        var lastTriggeredAt: Date = Date.distantPast
        var isActionInFlight: Bool = false
    }

    private var states: [String: WindowState] = [:]
    private let lock = NSLock()

    func shouldTrigger(windowKey: String, signature: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let state = states[windowKey] else { return true }

        // Block if an action is currently pending or executing for this window
        if state.isActionInFlight {
            return false
        }

        // NEVER re-trigger the same prompt signature!
        if state.lastHandledSignature == signature {
            return false
        }

        // Minimum cooldown between any prompt triggers in the same window (1.5s)
        let timeSinceLast = Date().timeIntervalSince(state.lastTriggeredAt)
        if timeSinceLast < 1.5 {
            return false
        }

        return true
    }

    func markActionScheduled(windowKey: String, signature: String) {
        lock.lock()
        defer { lock.unlock() }
        if states[windowKey] == nil {
            states[windowKey] = WindowState()
        }
        states[windowKey]?.isActionInFlight = true
        states[windowKey]?.lastHandledSignature = signature
        states[windowKey]?.lastTriggeredAt = Date()
    }

    func markActionCompleted(windowKey: String) {
        lock.lock()
        defer { lock.unlock() }
        states[windowKey]?.isActionInFlight = false
        states[windowKey]?.lastTriggeredAt = Date()
    }

    func resetSignatureIfIdle(windowKey: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let state = states[windowKey], !state.lastHandledSignature.isEmpty else { return }
        // If no prompt has been active for at least 3 seconds, reset signature so future prompts can trigger
        if !state.isActionInFlight && Date().timeIntervalSince(state.lastTriggeredAt) >= 3.0 {
            states[windowKey]?.lastHandledSignature = ""
        }
    }
}
