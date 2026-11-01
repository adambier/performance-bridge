// The setup window: the steps of setting up Performance Bridge with TotalMix FX and a Roto-Control,
// each checked live where the app can see it (SetupChecklist in BridgeEngine). It opens by itself
// the first time the app runs, and from the menu (Setup Guide…) after that.

import AppKit
import SwiftUI
#if canImport(BridgeEngine)
import BridgeEngine
#endif

/// The setup window's content. It follows the engine's status, so each step turns done as soon as
/// it works.
struct SetupView: View {
    @ObservedObject var model: BridgeModel

    /// The steps that are notes, not checks: shown apart, without a mark, so they don't read as
    /// to-dos (Adam, 2026-10-31).
    private static let noteIDs: Set<String> = ["hide", "order"]

    /// Screenshots of TotalMix FX for a step, shown under "Show in TotalMix FX" while the step
    /// needs doing. They are from TotalMix FX "2.10 (1)" on a Mac (Adam, 2026-10-31), published
    /// with his permission; TotalMix's windows rarely change.
    private static let screenshots: [String: [String]] = [
        "totalmix": ["totalmix-options-menu", "totalmix-osc-tab", "totalmix-osc-details"],
        "meters": ["totalmix-osc-tab"],
        "hide": ["totalmix-channel-layout"],
    ]

    private var checks: [SetupStep] { steps.filter { !Self.noteIDs.contains($0.id) } }
    private var notes: [SetupStep] { steps.filter { Self.noteIDs.contains($0.id) } }

    private var steps: [SetupStep] {
        SetupChecklist.steps(status: model.status, settings: model.engine.settings,
                             totalMixRunning: model.totalMixRunning, totalMixVersion: model.totalMixVersion)
    }

    /// The height of the steps and notes, measured, so the window fits them until it would be
    /// taller than the screen, and scrolls them after that.
    @State private var contentHeight: CGFloat = 400

    /// The most the scrolling part may take: the screen's height, less room for the title, the
    /// header, the buttons, and the Dock.
    private var maxScrollHeight: CGFloat {
        ((NSScreen.main?.visibleFrame.height ?? 800) - 220).clamped(to: 240...2000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up Performance Bridge")
                    .font(.title3.weight(.semibold))
                Text(SetupChecklist.isComplete(model.status)
                     ? "Everything the hardware controllers need is working."
                     : "Each step updates as soon as it works. Leave this window open while you set up TotalMix FX.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.vertical) {
                stepsAndNotes
                    .padding(.trailing, 12)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: SetupContentHeightKey.self, value: geometry.size.height)
                    })
            }
            .frame(height: min(contentHeight, maxScrollHeight))
            .onPreferenceChange(SetupContentHeightKey.self) { contentHeight = $0 }

            HStack {
                Button("Connections…") { model.showSettings(.connections) }
                Button("Channel Layout…") { model.showSettings(.channelLayout) }
                Spacer()
                Button("Done") { Windows.close("setup") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 532)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The checks, then the notes under "Good to Know".
    private var stepsAndNotes: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(checks) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    icon(step.state)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .fontWeight(.medium)
                        if !step.detail.isEmpty {
                            detailText(step.detail)
                            screenshots(for: step)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Good to Know")
                    .font(.headline)
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .fontWeight(.medium)
                        detailText(note.detail)
                        screenshots(for: note)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A step's detail, broken up for legibility (Adam, 2026-10-31): each line on its own with a
    /// little space between (e.g., numbered steps), and more space between paragraphs, which a
    /// blank line separates.
    private func detailText(_ detail: String) -> some View {
        let paragraphs = detail.components(separatedBy: "\n\n").map { $0.components(separatedBy: "\n") }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(paragraphs.indices, id: \.self) { p in
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(paragraphs[p].indices, id: \.self) { l in
                        Text(paragraphs[p][l])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    /// A step's screenshots, folded away until asked for. Each is shown at its own size (they are
    /// Retina captures, so half their pixels), no wider than 400 points, with an exact height so
    /// no space is left around it.
    @ViewBuilder
    private func screenshots(for step: SetupStep) -> some View {
        let images = (Self.screenshots[step.id] ?? []).compactMap { Brand.resources.image(forResource: $0) }
        if !images.isEmpty {
            DisclosureGroup("Show in TotalMix FX") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(images.indices, id: \.self) { index in
                        let image = images[index]
                        let pixels = pixelSize(image)
                        let width = min(pixels.width / 2, 400)
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: width, height: width * pixels.height / max(pixels.width, 1))
                            .accessibilityLabel("Screenshot of TotalMix FX")
                    }
                }
                .padding(.top, 4)
            }
            .font(.callout)
        }
    }

    /// An image's size in pixels, from its first representation.
    private func pixelSize(_ image: NSImage) -> CGSize {
        guard let rep = image.representations.first, rep.pixelsWide > 0 else { return image.size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    /// The mark for a step's state: a check when done, a clock while waiting, a warning for a
    /// problem, a dash for an optional step, and an "i" for an instruction.
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

/// The measured height of the setup window's scrolling part.
private struct SetupContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension CGFloat {
    /// The value, kept within `range`.
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
