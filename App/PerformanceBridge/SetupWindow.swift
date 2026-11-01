// The setup window: the steps of setting up Performance Bridge with TotalMix FX and a Roto-Control,
// each checked live where the app can see it (SetupChecklist in BridgeEngine). It opens by itself
// the first time the app runs, and from the menu (Setup Guide…) after that.

import SwiftUI
#if canImport(BridgeEngine)
import BridgeEngine
#endif

/// The setup window's content. It follows the engine's status, so each step turns done as soon as
/// it works.
struct SetupView: View {
    @ObservedObject var model: BridgeModel

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
                     ? "Everything the surfaces need is working."
                     : "Each step updates as soon as it works. Leave this window open while you set up TotalMix FX.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(steps) { step in
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
                        }
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
