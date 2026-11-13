import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var monitor = AutoEnterMonitor.shared
    @State private var showingAccessibilityAlert = false
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main controls in ScrollView
            ScrollView {
                VStack(spacing: 14) {
                    if !monitor.hasAccessibilityPermission {
                        permissionBanner
                    }
                    statusCard
                    cliAutoPilotCard
                    guiAutoEnterCard
                    aiDetectionCard
                    targetAppsCard
                    activityCard
                }
                .padding(14)
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 340, height: 530)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Header
    var headerView: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 1) {
                Text("VibeAutoEnter")
                    .font(.headline)
                Text("Hands-free vibe coding for CLI & IDEs")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Permission Banner
    var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("Accessibility Refresh Needed")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            Text("Because the app was updated, toggle VibeAutoEnter OFF and back ON in Settings (or remove with '-' and re-add).")
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack {
                Button("Open Settings") {
                    monitor.requestAccessibilityPermission()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Restart App") {
                    monitor.restartApp()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Status Card
    var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(monitor.isRunning ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(monitor.isRunning ? Color.green.opacity(0.4) : Color.clear, lineWidth: 4)
                        .scaleEffect(monitor.isRunning ? 1.6 : 1)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: monitor.isRunning)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.isRunning ? "Active" : "Paused")
                    .font(.subheadline.weight(.semibold))
                Text(monitor.statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { monitor.isRunning },
                set: { _ in monitor.toggleRunning() }
            ))
            .labelsHidden()
        }
        .padding(10)
        .background(Color(NSColor.controlColor))
        .cornerRadius(10)
    }

    // MARK: - CLI Auto-Pilot Card
    var cliAutoPilotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("CLI Auto-Pilot", systemImage: "terminal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.cyan)
                Spacer()
                Text("\(monitor.cliEnterPressCount) sent")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(4)
            }

            Text("Monitors CLI windows whenever AI prompts you")
                .font(.caption2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-Accept on [y/N], (y/n), proceed prompts", isOn: $monitor.cliAutoAcceptEnabled)
                    .font(.caption)

                Toggle("Auto-Pick on number prompts [1-3], choice [1]", isOn: $monitor.cliAutoPickNumberEnabled)
                    .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Auto-Swap & Patrol open terminals", isOn: Binding(
                    get: { monitor.autoSwapWindows },
                    set: { newValue in
                        monitor.autoSwapWindows = newValue
                        monitor.updateSwapTimer()
                    }
                ))
                .font(.caption.weight(.medium))

                if monitor.autoSwapWindows {
                    HStack {
                        Text("Swap & check every")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(String(format: "%.1f", monitor.swapInterval))s")
                            .font(.caption2.monospacedDigit())
                    }
                    Slider(value: Binding(
                        get: { monitor.swapInterval },
                        set: {
                            monitor.swapInterval = $0
                            monitor.updateSwapTimer()
                        }
                    ), in: 1.5...10.0, step: 0.5)
                    .controlSize(.small)
                }
            }

            if monitor.cliAutoAcceptEnabled || monitor.cliAutoPickNumberEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CLI Enter delay")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(String(format: "%.1f", monitor.cliEnterDelay))s")
                            .font(.caption2.monospacedDigit())
                    }
                    Slider(value: $monitor.cliEnterDelay, in: 0.2...3.0, step: 0.2)
                        .controlSize(.small)
                }
            }

            Button(action: { monitor.testEnter() }) {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Test Enter in Terminal")
                }
                .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(NSColor.controlColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - GUI Auto-Enter Card
    var guiAutoEnterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("IDE & App Auto-Enter", systemImage: "return.left")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(monitor.enterPressCount) total")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Toggle("Auto-press Enter in Cursor / Claude / Windsurf", isOn: $monitor.autoEnterEnabled)
                .font(.caption)

            if monitor.autoEnterEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Delay before Enter")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(String(format: "%.1f", monitor.enterDelay))s")
                            .font(.caption2.monospacedDigit())
                    }
                    Slider(value: $monitor.enterDelay, in: 0.5...5.0, step: 0.5)
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlColor))
        .cornerRadius(10)
    }

    // MARK: - AI Completion Detection Card
    var aiDetectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AI Completion Alerts", systemImage: "brain.head.profile")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            Toggle("Notify when AI finishes", isOn: $monitor.notifyOnCompletion)
                .font(.caption)

            if monitor.notifyOnCompletion {
                Toggle("Play sound on completion", isOn: $monitor.playSoundOnCompletion)
                    .font(.caption)

                Picker("Notification style", selection: $monitor.notificationStyle) {
                    Text("Banner").tag(NotificationStyle.banner)
                    Text("Alert").tag(NotificationStyle.alert)
                    Text("Sound only").tag(NotificationStyle.soundOnly)
                }
                .font(.caption)
                .pickerStyle(.segmented)
                .controlSize(.small)
            }

            if let lastCompletion = monitor.lastCompletionTime {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text("Last done: \(lastCompletion, formatter: timeFormatter)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlColor))
        .cornerRadius(10)
    }

    // MARK: - Watched Apps Card
    var targetAppsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Watched Applications", systemImage: "app.badge.checkmark")
                .font(.subheadline.weight(.semibold))

            ForEach(monitor.watchedApps, id: \.bundleId) { app in
                HStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .cornerRadius(4)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(app.isCLI ? Color.cyan.opacity(0.3) : Color.purple.opacity(0.3))
                            .frame(width: 18, height: 18)
                            .overlay(Text(app.name.prefix(1)).font(.caption2))
                    }

                    Text(app.name)
                        .font(.caption)

                    if app.isCLI {
                        Text("CLI")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.cyan.opacity(0.12))
                            .cornerRadius(3)
                    }

                    Spacer()

                    Circle()
                        .fill(app.isRunning ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)

                    Toggle("", isOn: Binding(
                        get: { app.isEnabled },
                        set: { monitor.setApp(app, enabled: $0) }
                    ))
                    .labelsHidden()
                    .controlSize(.mini)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlColor))
        .cornerRadius(10)
    }

    // MARK: - Activity Card
    var activityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent Activity", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))

            if monitor.activityLog.isEmpty {
                Text("Waiting for prompts & AI actions…")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(monitor.activityLog.prefix(6)) { entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.icon)
                            .font(.caption2)
                            .foregroundColor(entry.color)
                            .frame(width: 14)
                        Text(entry.message)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.time, formatter: shortTimeFormatter)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlColor))
        .cornerRadius(10)
    }

    // MARK: - Footer
    var footerView: some View {
        HStack {
            Text("VibeAutoEnter v1.2")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            if !monitor.hasAccessibilityPermission {
                Button("Grant Permission") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .font(.caption2)
                .foregroundColor(.orange)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Formatters
private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .medium
    f.dateStyle = .none
    return f
}()

private let shortTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
}()
