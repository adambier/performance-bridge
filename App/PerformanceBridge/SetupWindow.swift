// The setup window: an assistant with one step of setting up Performance Bridge per page (Adam,
// 2026-11-02, from the UI review of that date), each step checked live where the app can see it
// (SetupChecklist in BridgeEngine). It opens by itself the first time the app runs, and at a
// problem's step when SetupWatch says so; from the menu (Setup Guide…) after that.

import AppKit
import SwiftUI
#if canImport(BridgeEngine)
import BridgeEngine
#endif
#if canImport(LaunchControl)
import LaunchControl
#endif

/// The setup window's content: one step per page, with Back and Continue, and a row of marks
/// across the top for every step, so the whole setup can be seen at a glance and any step reached
/// with a click. It follows the engine's status, so a step's mark and page change as soon as it
/// works.
struct SetupView: View {
    @ObservedObject var model: BridgeModel
    /// The step to open at (e.g., the problem that opened the window), or `nil` for the first step
    /// that isn't done (`SetupChecklist.startIndex`).
    var openFor: String?

    /// The step on show, by its id, so the page stays put when steps come and go (e.g., Mute
    /// Master's).
    @State private var pageID: String?
    /// Where the page on show was, so that if its step goes away (e.g., Mute Master's, once it is
    /// on) the assistant stays at the same place instead of jumping (review of 1.0.2).
    @State private var lastIndex: Int?
    /// Whether a done page shows how its step is set up (Adam, 2026-11-02); hidden again on
    /// another page.
    @State private var showInstructions = false

    /// Screenshots for a step, shown on its page: one for every step (Adam, 2026-11-02), whole
    /// windows so it is clear where a setting is, with the setting outlined in the app's amber
    /// where the window holds more. TotalMix FX's ("totalmix-") are from TotalMix FX "2.10 (1)" on
    /// a Mac (Adam, 2026-10-31 and 2026-11-02), published with his permission; TotalMix FX's
    /// windows rarely change. Performance Bridge's own ("app-") need taking again when its
    /// windows change. The "login" page has none: its own checkbox is on the page.
    private var shots: [String: [String]] {
        let launchControl = model.status.launchControlLayout == .lc3 ? "app-connections-lc3" : "app-connections-xl3"
        return [
            "port": ["totalmix-osc-outgoing"],
            "version": ["totalmix-about"],
            "channels": ["app-menu-refresh"],
            "meters": ["totalmix-osc-level-data"],
            "mutemaster": ["totalmix-control-strip"],
            "roto": ["app-connections-roto"],
            "launchcontrol": [launchControl],
            "e16": ["app-connections-e16"],
            "livemode": ["totalmix-live-mode"],
            "cue": ["totalmix-cue-pfl-to"],
            "hide": ["totalmix-channel-layout"],
            "order": ["app-channel-layout"],
        ]
    }

    /// The width of the window's content, and so the widest a screenshot is shown.
    private static let width: CGFloat = 560

    private var steps: [SetupStep] {
        SetupChecklist.steps(status: model.status, settings: model.engine.settings,
                             totalMixRunning: model.totalMixRunning, totalMixVersion: model.totalMixVersion,
                             openAtLogin: model.loginItem == .unavailable ? nil : model.loginItem == .on)
    }

    private var index: Int {
        let steps = self.steps
        if let pageID, let index = steps.firstIndex(where: { $0.id == pageID }) { return index }
        if let lastIndex { return min(lastIndex, max(steps.count - 1, 0)) }
        return SetupChecklist.startIndex(of: steps, openFor: openFor)
    }

    /// The most the page may take: the screen's height, less room for the title, the marks, the
    /// buttons, and the Dock.
    private var maxPageHeight: CGFloat {
        ((NSScreen.main?.visibleFrame.height ?? 800) - 240).clamped(to: 300...560)
    }

    /// Shows step `i`.
    private func go(to i: Int, in steps: [SetupStep]) {
        guard steps.indices.contains(i) else { return }
        if pageID != steps[i].id { showInstructions = false }
        pageID = steps[i].id
        lastIndex = i
    }

    var body: some View {
        let steps = self.steps
        let index = min(self.index, max(steps.count - 1, 0))
        VStack(alignment: .leading, spacing: 14) {
            header(steps, index: index)
            Divider()
            if steps.indices.contains(index) {
                ScrollView(.vertical) {
                    page(steps[index])
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: maxPageHeight)
            }
            Divider()
            footer(steps, index: index)
        }
        .padding(20)
        .frame(width: Self.width + 40)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { if pageID == nil { go(to: index, in: steps) } }
    }

    // MARK: - Parts

    /// The summary line and a mark for every step: a click on a mark opens its page.
    private func header(_ steps: [SetupStep], index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(SetupChecklist.isComplete(model.status)
                 ? "Everything the hardware controllers need is working."
                 : "Each step updates as soon as it works. Leave this window open while you set up TotalMix FX.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { i in
                    Button { go(to: i, in: steps) } label: {
                        mark(steps[i].state, current: i == index)
                    }
                    .buttonStyle(.plain)
                    .help(steps[i].title)
                    .accessibilityLabel("Step \(i + 1): \(steps[i].title), \(stateText(steps[i].state))")
                    .accessibilityAddTraits(i == index ? .isSelected : [])
                }
                Spacer()
                Text("Step \(index + 1) of \(steps.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// One step: its mark and title, what to do, the TotalMix FX screenshots for it, and a button
    /// to the Settings tab it needs.
    private func page(_ step: SetupStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                icon(step.state)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(stateText(step.state))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if !step.detail.isEmpty { detailText(step.detail) }
            if step.state != .done {
                screenshots(for: step)
            } else if !step.instructions.isEmpty || shots[step.id] != nil {
                // A done step's instructions and screenshots, on request: e.g., to set up another
                // Mac the same way.
                Button(showInstructions ? "Hide Instructions" : "Show Instructions") {
                    showInstructions.toggle()
                }
                if showInstructions {
                    if !step.instructions.isEmpty { detailText(step.instructions) }
                    screenshots(for: step)
                }
            }
            if step.id == "login" {
                OpenAtLoginToggle(model: model)
            }
            if let link = settingsLink(for: step.id) {
                Button(link.title) { model.showSettings(link.tab) }
            }
        }
    }

    /// Back and Continue (Done on the last page), the default button: one page at a time, done or
    /// not (Adam, 2026-11-02; skipping the done ones was tried the same day).
    private func footer(_ steps: [SetupStep], index: Int) -> some View {
        HStack {
            Button("Back") { go(to: index - 1, in: steps) }
                .disabled(index == 0)
            Spacer()
            if index + 1 < steps.count {
                Button("Continue") { go(to: index + 1, in: steps) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Done") { Windows.close("setup") }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The Settings tab a step's page links to, with the button's title.
    private func settingsLink(for id: String) -> (title: String, tab: SettingsTab)? {
        switch id {
        case "port", "totalmix", "roto", "launchcontrol": return ("Open Connections Settings…", .connections)
        case "order": return ("Open Channel Layout Settings…", .channelLayout)
        default: return nil
        }
    }

    /// A step's detail, broken up for legibility (Adam, 2026-10-31): each line on its own with a
    /// little space between (e.g., numbered steps), and more space between paragraphs, which a
    /// blank line separates. In the primary color, since on its page the detail is what the user
    /// acts on (UI review of 2026-11-02). A line `[image: name]` shows that screenshot there, after
    /// the steps it shows (Adam, 2026-11-02).
    private func detailText(_ detail: String) -> some View {
        let paragraphs = detail.components(separatedBy: "\n\n").map { $0.components(separatedBy: "\n") }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(paragraphs.indices, id: \.self) { p in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(paragraphs[p].indices, id: \.self) { l in
                        let line = paragraphs[p][l]
                        if let name = Self.imageName(line) {
                            screenshot(name)
                                .padding(.vertical, 6)
                        } else {
                            Text(line)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    /// A step's screenshots, each shown at its own size (they are Retina captures, so half their
    /// pixels), no wider than the page, with an exact height so no space is left around it.
    @ViewBuilder
    private func screenshots(for step: SetupStep) -> some View {
        // None where the page has nothing to say about them: a step with no text (e.g., TotalMix FX
        // not answering yet, on the channels page), or the version page while TotalMix FX isn't
        // running (review of 2026-11-02).
        let unexplained = step.detail.isEmpty && step.state != .done
        let notRunning = step.id == "version" && step.state == .waiting
        let names = unexplained || notRunning ? []
            : (shots[step.id] ?? []).filter { Brand.resources.image(forResource: $0) != nil }
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                // Named for the app the screenshots show.
                Text(names.allSatisfy { $0.hasPrefix("app-") } ? "Where it is in Performance Bridge" : "Where it is in TotalMix FX")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(names, id: \.self) { name in screenshot(name) }
            }
        }
    }

    /// The screenshot a detail line names (`[image: name]`), or `nil` for a line of text.
    private static func imageName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[image:"), trimmed.hasSuffix("]") else { return nil }
        return trimmed.dropFirst("[image:".count).dropLast().trimmingCharacters(in: .whitespaces)
    }

    /// One screenshot at its own size (a Retina capture, so half its pixels), no wider than the
    /// page, with an exact height so no space is left around it.
    @ViewBuilder
    private func screenshot(_ name: String) -> some View {
        if let image = Brand.resources.image(forResource: name) {
            let pixels = pixelSize(image)
            let width = min(pixels.width / 2, Self.width - 12)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: width * pixels.height / max(pixels.width, 1))
                .accessibilityLabel(name.hasPrefix("app-") ? "Screenshot of Performance Bridge" : "Screenshot of TotalMix FX")
        }
    }

    /// An image's size in pixels, from its first representation.
    private func pixelSize(_ image: NSImage) -> CGSize {
        guard let rep = image.representations.first, rep.pixelsWide > 0 else { return image.size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    /// A step's state in words, under its title.
    private func stateText(_ state: SetupStep.State) -> String {
        switch state {
        case .done: return "Done: nothing to do here"
        case .waiting: return "Not done yet"
        case .problem: return "Needs attention"
        case .optional: return "Optional"
        case .instruction: return "Performance Bridge can’t check this one"
        }
    }

    /// A step's small mark in the row across the top: its state's color, ringed while on show.
    private func mark(_ state: SetupStep.State, current: Bool) -> some View {
        let color: Color = {
            switch state {
            case .done: return .green
            case .problem: return .orange
            case .instruction: return Brand.accent
            case .waiting, .optional: return .secondary
            }
        }()
        let filled = state == .done || state == .problem
        return ZStack {
            Circle()
                .fill(filled ? color : Color.clear)
            Circle()
                .strokeBorder(color, lineWidth: filled ? 0 : 1.5)
        }
        .frame(width: 12, height: 12)
        .padding(3)
        .overlay(Circle().strokeBorder(Color.primary.opacity(current ? 0.8 : 0), lineWidth: 1.5))
        .contentShape(Circle())
    }

    /// The mark for a step's state on its page: a check when done, a clock while waiting, a
    /// warning for a problem, a dash for an optional step, and an "i" for an instruction.
    @ViewBuilder
    private func icon(_ state: SetupStep.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel("Done")
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
                .accessibilityLabel("Waiting")
        case .problem:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .accessibilityLabel("Problem")
        case .optional:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                .accessibilityLabel("Optional")
        case .instruction:
            Image(systemName: "info.circle").foregroundStyle(Brand.accent)
                .accessibilityLabel("Instruction")
        }
    }
}

private extension CGFloat {
    /// The value, kept within `range`.
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
