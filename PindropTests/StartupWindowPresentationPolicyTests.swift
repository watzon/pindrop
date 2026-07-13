//
//  StartupWindowPresentationPolicyTests.swift
//  PindropTests
//
//  Created on 2026-07-13.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct StartupWindowPresentationPolicyTests {

    @Test func defaultLaunchOrdersMainWindowFront() {
        let context = StartupWindowPresentationPolicy.Context(
            launchWithoutShowingWindow: false,
            launchServicesRequestedHide: false,
            hasCompletedOnboarding: true
        )

        #expect(StartupWindowPresentationPolicy.shouldOrderMainWindowFront(for: context))
    }

    @Test func optInSilentLaunchSuppressesMainWindow() {
        let context = StartupWindowPresentationPolicy.Context(
            launchWithoutShowingWindow: true,
            hasCompletedOnboarding: true
        )

        #expect(!StartupWindowPresentationPolicy.shouldOrderMainWindowFront(for: context))
    }

    @Test func launchServicesHideRequestSuppressesMainWindowWithoutPreference() {
        let context = StartupWindowPresentationPolicy.Context(
            launchWithoutShowingWindow: false,
            launchServicesRequestedHide: true,
            hasCompletedOnboarding: true
        )

        #expect(!StartupWindowPresentationPolicy.shouldOrderMainWindowFront(for: context))
    }

    @Test func incompleteOnboardingAlwaysOrdersMainWindowFront() {
        let silent = StartupWindowPresentationPolicy.Context(
            launchWithoutShowingWindow: true,
            launchServicesRequestedHide: true,
            hasCompletedOnboarding: false
        )

        #expect(StartupWindowPresentationPolicy.shouldOrderMainWindowFront(for: silent))
    }

    @Test func launchAndHideFlagMatchesLaunchServicesConstant() {
        #expect(StartupWindowPresentationPolicy.launchAndHideFlag == 0x0010_0000)
    }

    @Test func launchFlagsDecodeBigEndianHideBit() {
        // 0x00100000 big-endian bytes
        let data = Data([0x00, 0x10, 0x00, 0x00])
        let flags = StartupWindowPresentationPolicy.launchFlags(fromPropertyData: data)
        #expect(flags == StartupWindowPresentationPolicy.launchAndHideFlag)
        #expect(StartupWindowPresentationPolicy.launchServicesRequestedHide(inPropertyData: data))
    }

    @Test func launchFlagsIgnoreTruncatedPropertyData() {
        let truncated = Data([0x00, 0x10, 0x00])
        #expect(StartupWindowPresentationPolicy.launchFlags(fromPropertyData: truncated) == nil)
        #expect(!StartupWindowPresentationPolicy.launchServicesRequestedHide(inPropertyData: truncated))
        #expect(!StartupWindowPresentationPolicy.launchServicesRequestedHide(inPropertyData: nil))
        #expect(!StartupWindowPresentationPolicy.launchServicesRequestedHide(inPropertyData: Data()))
    }

    @Test func launchFlagsDecodeFromUnalignedPrefixOffset() {
        // Leading pad would misalign a typed load; decoder reads first four
        // bytes of the provided slice via byte-wise big-endian assembly.
        let padded = Data([0xFF, 0x00, 0x10, 0x00, 0x00])
        let slice = Data(padded.dropFirst())
        let flags = StartupWindowPresentationPolicy.launchFlags(fromPropertyData: slice)
        #expect(flags == StartupWindowPresentationPolicy.launchAndHideFlag)
        #expect(StartupWindowPresentationPolicy.launchServicesRequestedHide(inPropertyData: slice))
    }

    @Test func launchFlagsWithoutHideBitDoNotRequestHide() {
        let data = Data([0x00, 0x00, 0x00, 0x01])
        let flags = StartupWindowPresentationPolicy.launchFlags(fromPropertyData: data)
        #expect(flags == 1)
        #expect(!StartupWindowPresentationPolicy.launchServicesRequestedHide(inPropertyData: data))
    }

    @Test func contextAcceptsCapturedLaunchSemantics() {
        let semantics = StartupLaunchSemantics(launchServicesRequestedHide: true)
        let context = StartupWindowPresentationPolicy.Context(
            launchWithoutShowingWindow: false,
            launchSemantics: semantics,
            hasCompletedOnboarding: true
        )
        #expect(!StartupWindowPresentationPolicy.shouldOrderMainWindowFront(for: context))
    }
}
