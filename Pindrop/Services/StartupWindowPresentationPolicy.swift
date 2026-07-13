//
//  StartupWindowPresentationPolicy.swift
//  Pindrop
//
//  Created on 2026-07-13.
//

import AppKit
import Foundation

/// Immutable launch signals captured synchronously during
/// `applicationDidFinishLaunching`, before any deferred Task runs.
struct StartupLaunchSemantics: Sendable, Equatable {
    /// True when LaunchServices requested a hidden/background launch
    /// (`kLSLaunchAndHide` in open-application `keyAEPropData`).
    var launchServicesRequestedHide: Bool

    static let normal = StartupLaunchSemantics(launchServicesRequestedHide: false)
}

/// Pure decision seam for whether startup should order the main window front
/// (and related non-onboarding startup chrome). Manual menu-bar / menu actions
/// still open the window later.
enum StartupWindowPresentationPolicy: Sendable, Equatable {
    /// `open -j` / LaunchServices "hide on launch" flag. Raw value so tests can
    /// inject the bit without linking LaunchServices constants.
    static let launchAndHideFlag: UInt32 = 0x0010_0000

    /// Inputs that drive the initial main-window presentation decision.
    struct Context: Sendable, Equatable {
        /// User preference: keep the main window closed on startup.
        var launchWithoutShowingWindow: Bool
        /// LaunchServices hide request detected at process start.
        var launchServicesRequestedHide: Bool
        /// Onboarding must always show UI; first-run never suppresses the window.
        var hasCompletedOnboarding: Bool

        init(
            launchWithoutShowingWindow: Bool,
            launchServicesRequestedHide: Bool = false,
            hasCompletedOnboarding: Bool = true
        ) {
            self.launchWithoutShowingWindow = launchWithoutShowingWindow
            self.launchServicesRequestedHide = launchServicesRequestedHide
            self.hasCompletedOnboarding = hasCompletedOnboarding
        }

        init(
            launchWithoutShowingWindow: Bool,
            launchSemantics: StartupLaunchSemantics,
            hasCompletedOnboarding: Bool
        ) {
            self.init(
                launchWithoutShowingWindow: launchWithoutShowingWindow,
                launchServicesRequestedHide: launchSemantics.launchServicesRequestedHide,
                hasCompletedOnboarding: hasCompletedOnboarding
            )
        }
    }

    /// Whether startup should order the main window front / show splash /
    /// auto-present What's New. Incomplete onboarding always presents UI.
    static func shouldOrderMainWindowFront(for context: Context) -> Bool {
        guard context.hasCompletedOnboarding else {
            return true
        }

        if context.launchWithoutShowingWindow {
            return false
        }

        if context.launchServicesRequestedHide {
            return false
        }

        return true
    }

    /// Decode LaunchServices launch flags from open-application property data.
    /// Accepts truncated and unaligned payloads safely.
    static func launchFlags(fromPropertyData data: Data) -> UInt32? {
        guard data.count >= MemoryLayout<UInt32>.size else {
            return nil
        }

        return data.withUnsafeBytes { buffer -> UInt32? in
            guard let base = buffer.baseAddress else { return nil }
            // Byte-wise big-endian decode avoids alignment assumptions on
            // `load(as:)` for arbitrarily offset AppleEvent payloads.
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let value =
                (UInt32(bytes[0]) << 24)
                | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8)
                | UInt32(bytes[3])
            return value
        }
    }

    static func launchServicesRequestedHide(inPropertyData data: Data?) -> Bool {
        guard let data, let flags = launchFlags(fromPropertyData: data) else {
            return false
        }
        return (flags & launchAndHideFlag) != 0
    }

    /// Capture launch-hide semantics from the current open-application
    /// AppleEvent. Must be called synchronously while the event is still
    /// available (typically at the start of `applicationDidFinishLaunching`).
    static func captureLaunchSemantics(
        from appleEvent: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent
    ) -> StartupLaunchSemantics {
        guard let appleEvent else {
            return .normal
        }

        let propData = appleEvent.paramDescriptor(forKeyword: keyAEPropData)?.data
        return StartupLaunchSemantics(
            launchServicesRequestedHide: launchServicesRequestedHide(inPropertyData: propData)
        )
    }
}
