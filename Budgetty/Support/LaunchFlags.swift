//
//  LaunchFlags.swift
//  Budgetty
//
//  Reads the DEBUG test hooks (SKIP_AUTH, ONBOARDING, QUIZ, USE_STUB_EXTRACTOR, SCAN_PHASE, …) from
//  EITHER source they can arrive through:
//
//   • the process environment — Xcode scheme "Environment Variables", and the screenshot/emulator
//     scripts that set them via `simctl ... --env`;
//   • a launch argument surfaced through UserDefaults — how Maestro delivers `launchApp.arguments`
//     on iOS (as `-KEY value`, which Foundation folds into the UserDefaults argument domain). Maestro
//     can't set iOS environment variables, so without this a cross-platform Maestro flow couldn't
//     reach these hooks.
//
//  Environment wins when both are present. These are test affordances; every caller stays behind
//  `#if DEBUG`, so release builds never consult them.
//

import Foundation

enum LaunchFlags {
    /// The string value of a hook, from the environment first, then a `-KEY value` launch argument.
    static func value(_ key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty { return env }
        return UserDefaults.standard.string(forKey: key)
    }

    /// True when the hook is set to "1" (the on/off flags: SKIP_AUTH, USE_STUB_EXTRACTOR, SHOW_SCAN).
    static func isOn(_ key: String) -> Bool { value(key) == "1" }
}
