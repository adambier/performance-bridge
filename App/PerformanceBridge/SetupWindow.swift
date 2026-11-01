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

            ForEach(checks) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    icon(step.state)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .fontWeight(.medium)
                        if !step.detail.isEmpty {
                            Text(step.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
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
                        Text(note.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        screenshots(for: note)
                    }
                }
            }

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
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A step's screenshots, folded away until asked for, each at most its own size (they are
    /// Retina captures, so half their pixels) and no wider than the window allows.
    @ViewBuilder
    private func screenshots(for step: SetupStep) -> some View {
        let images = (Self.screenshots[step.id] ?? []).compactMap { Brand.resources.image(forResource: $0) }
        if !images.isEmpty {
            DisclosureGroup("Show in TotalMix FX") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(images.indices, id: \.self) { index in
                        let image = images[index]
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: min(screenshotPoints(image), 440), alignment: .leading)
                            .accessibilityLabel("Screenshot of TotalMix FX")
                    }
                }
                .padding(.top, 4)
            }
            .font(.callout)
        }
    }

    /// A screenshot's width in points: half its pixels, since they were taken on a Retina display.
    private func screenshotPoints(_ image: NSImage) -> CGFloat {
        let pixels = image.representations.first.map { CGFloat($0.pixelsWide) } ?? image.size.width
        return pixels / 2
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
            Image(systemName: "info.circle").foregroundStyle(Brand.amber)
                .accessibilityLabel("Instruction")
        }
    }
}
