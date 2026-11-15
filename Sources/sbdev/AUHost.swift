// sbdev auhost: what an instrument's Audio Unit tells a host about its parameters.
//
// A probe for docs/PLUGIN-MODE-PLAN.md, section 10: it loads an Audio Unit with no audio running,
// prints its parameters as a host sees them, and, with --window, shows the plugin's own window
// and prints each parameter whose name or value changes, so that a preset change shows whether
// the names follow the preset.
//
// Never compiled on macOS when written (2026-11-14, on Linux, where it compiles out).

import Foundation

let auHostUsage = """
    Usage: sbdev auhost [NAME] [options]

      With no NAME, lists the instrument Audio Units installed. With a NAME (part of a name is
      enough, e.g. Pigments), loads that one and prints the first parameters a host is given.

      --all            every parameter, not the first 40
      --window         shows the plugin's window; then prints each parameter whose name or value
                       text changes, and the preset's name, until Control-C
      --count N        how many parameters to print and watch (default 40)
    """

#if canImport(AVFoundation) && canImport(AppKit) && canImport(CoreAudioKit)
import AppKit
import AVFoundation
import CoreAudioKit

private struct AUHostParameter: Equatable {
    var name: String
    var text: String
}

private func auHostRead(_ unit: AUAudioUnit, count: Int?) -> [(address: AUParameterAddress, identifier: String, parameter: AUHostParameter)] {
    let all = unit.parameterTree?.allParameters ?? []
    let shown = count.map { Array(all.prefix($0)) } ?? all
    return shown.map { parameter in
        (parameter.address, parameter.identifier,
         AUHostParameter(name: parameter.displayName, text: parameter.string(fromValue: nil)))
    }
}

func auHost(_ arguments: ArraySlice<String>) -> Never {
    var rest = arguments
    var words: [String] = []
    var count: Int? = 40
    var window = false
    while let argument = rest.popFirst() {
        switch argument {
        case "--all": count = nil
        case "--window": window = true
        case "--count":
            guard let text = rest.popFirst(), let number = Int(text), number > 0 else { fail("--count needs a number.\n\n\(auHostUsage)") }
            count = number
        case "-h", "--help": print(auHostUsage); exit(0)
        default: words.append(argument)
        }
    }
    let anyInstrument = AudioComponentDescription(
        componentType: kAudioUnitType_MusicDevice, componentSubType: 0, componentManufacturer: 0,
        componentFlags: 0, componentFlagsMask: 0)
    let components = AVAudioUnitComponentManager.shared().components(matching: anyInstrument)
    guard let wanted = words.first else {
        for component in components.sorted(by: { ($0.manufacturerName, $0.name) < ($1.manufacturerName, $1.name) }) {
            print("\(component.manufacturerName): \(component.name)  (version \(component.versionString))")
        }
        print("\(components.count) instrument Audio Units.")
        exit(0)
    }
    let name = words.joined(separator: " ")
    let matches = components.filter { $0.name.localizedCaseInsensitiveContains(name) }
    guard let component = matches.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) ?? (matches.count == 1 ? matches.first : nil) else {
        if matches.isEmpty { fail("No instrument Audio Unit's name contains \"\(wanted)\". `sbdev auhost` lists them.") }
        fail("More than one matches: " + matches.map(\.name).joined(separator: ", "))
    }
    print("Loading \(component.manufacturerName) \(component.name), version \(component.versionString) …")

    let application = NSApplication.shared
    application.setActivationPolicy(window ? .regular : .accessory)
    var loaded: AVAudioUnit?
    var shownWindow: NSWindow?
    var last: [AUParameterAddress: AUHostParameter] = [:]
    var lastPreset: String?
    let started = Date()

    func report(_ unit: AUAudioUnit, first: Bool) {
        let preset = unit.currentPreset?.name ?? "(none)"
        if preset != lastPreset {
            print(String(format: "%9.3f  preset, as the host is told: %@", Date().timeIntervalSince(started), preset))
            lastPreset = preset
        }
        for (address, identifier, parameter) in auHostRead(unit, count: count) {
            if first {
                print("  \(address)  \(parameter.name)  = \(parameter.text)   [\(identifier)]")
            } else if let before = last[address], before != parameter {
                let what = before.name != parameter.name ? "name \"\(before.name)\" -> \"\(parameter.name)\"" : "\"\(parameter.name)\""
                print(String(format: "%9.3f  %@  = %@", Date().timeIntervalSince(started), what, parameter.text))
            }
            last[address] = parameter
        }
    }

    AVAudioUnit.instantiate(with: component.audioComponentDescription, options: []) { unit, error in
        DispatchQueue.main.async {
            guard let unit = unit else {
                fail("Could not load it: \(error?.localizedDescription ?? "no error given").")
            }
            loaded = unit
            let audioUnit = unit.auAudioUnit
            let total = audioUnit.parameterTree?.allParameters.count ?? 0
            print("\(total) parameters; factory presets the host is told of: \(audioUnit.factoryPresets?.count ?? 0).")
            report(audioUnit, first: true)
            guard window else { exit(0) }
            audioUnit.requestViewController { controller in
                DispatchQueue.main.async {
                    guard let controller = controller else { fail("The Audio Unit gave no window.") }
                    let made = NSWindow(contentViewController: controller)
                    made.title = component.name
                    made.makeKeyAndOrderFront(nil)
                    application.activate(ignoringOtherApps: true)
                    shownWindow = made
                    print("Watching. Change presets and controls in the window; Control-C to stop.")
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in report(audioUnit, first: false) }
                }
            }
        }
    }
    application.run()
    _ = (loaded, shownWindow)
    exit(0)
}
#else
func auHost(_ arguments: ArraySlice<String>) -> Never {
    if arguments.contains("-h") || arguments.contains("--help") { print(auHostUsage); exit(0) }
    fail("sbdev auhost needs macOS.")
}
#endif
