//
//  FloatingIndicatorTypeTests.swift
//  PindropTests
//
//  Created on 2026-07-13.
//

import Foundation
import Testing

@testable import Pindrop

@Suite
struct FloatingIndicatorTypeTests {
    @Test func allCasesIncludeTransientAndAlwaysOnStyles() {
        #expect(FloatingIndicatorType.allCases == [.notch, .pill, .bubble, .orb])
    }

    @Test func alwaysOnFlagsMatchStyleContract() {
        #expect(FloatingIndicatorType.orb.isAlwaysOn)
        #expect(FloatingIndicatorType.pill.isAlwaysOn)
        #expect(!FloatingIndicatorType.notch.isAlwaysOn)
        #expect(!FloatingIndicatorType.bubble.isAlwaysOn)
    }

    @Test func toastAnchoringMatchesStyleContract() {
        #expect(FloatingIndicatorType.notch.anchorsToastsToIndicator)
        #expect(FloatingIndicatorType.pill.anchorsToastsToIndicator)
        #expect(!FloatingIndicatorType.bubble.anchorsToastsToIndicator)
        #expect(FloatingIndicatorType.orb.anchorsToastsToIndicator)
    }

    @Test func rawValuesRoundTrip() {
        for type in FloatingIndicatorType.allCases {
            #expect(FloatingIndicatorType(rawValue: type.rawValue) == type)
        }
    }

    @Test func displayNamesResolveEnglishKeys() {
        let locale = Locale(identifier: "en")
        #expect(FloatingIndicatorType.notch.displayName(locale: locale) == "Notch")
        #expect(FloatingIndicatorType.pill.displayName(locale: locale) == "Pill")
        #expect(FloatingIndicatorType.bubble.displayName(locale: locale) == "Bubble")
        #expect(FloatingIndicatorType.orb.displayName(locale: locale) == "Orb")
    }

    @Test func descriptionsResolveEnglishKeys() {
        let locale = Locale(identifier: "en")
        #expect(
            FloatingIndicatorType.notch.description(locale: locale)
                == "Shows in the menu bar/notch area"
        )
        #expect(
            FloatingIndicatorType.bubble.description(locale: locale)
                == "Shows beside the focused text field/caret"
        )
        #expect(
            FloatingIndicatorType.pill.description(locale: locale)
                == "Shows as a pill at the bottom of the screen"
        )
        #expect(
            FloatingIndicatorType.orb.description(locale: locale)
                == "Shows as a liquid glass orb in the corner of the screen"
        )
    }
}

@Suite
struct FloatingIndicatorPresentationLifecycleTests {
    @Test func hideCompletionAppliesOnlyForMatchingGeneration() {
        #expect(
            FloatingIndicatorPresentationLifecycle.shouldApplyHideCompletion(
                hideGeneration: 3,
                currentGeneration: 3
            )
        )
    }

    @Test func hideCompletionIsIgnoredAfterShowBumpsGeneration() {
        // hide captured gen 4; show/startRecording then bumped to 5
        #expect(
            !FloatingIndicatorPresentationLifecycle.shouldApplyHideCompletion(
                hideGeneration: 4,
                currentGeneration: 5
            )
        )
    }

    @Test func hideCompletionIsIgnoredAfterSupersedingHide() {
        // first hide gen 7; second hide bumped to 8 before first completion
        #expect(
            !FloatingIndicatorPresentationLifecycle.shouldApplyHideCompletion(
                hideGeneration: 7,
                currentGeneration: 8
            )
        )
    }

    @Test func generationTransitionModelMatchesControllerContract() {
        var generation: UInt = 0

        // hide starts
        generation &+= 1
        let hideGeneration = generation
        #expect(hideGeneration == 1)

        // new recording show invalidates hide
        generation &+= 1
        #expect(
            !FloatingIndicatorPresentationLifecycle.shouldApplyHideCompletion(
                hideGeneration: hideGeneration,
                currentGeneration: generation
            )
        )

        // later hide for the active presentation may complete
        generation &+= 1
        let finalHide = generation
        #expect(
            FloatingIndicatorPresentationLifecycle.shouldApplyHideCompletion(
                hideGeneration: finalHide,
                currentGeneration: generation
            )
        )
    }

    @Test func showDuringHideRequiresGenerationBumpViaShowPath() {
        // Models showForCurrentState() always calling show(): even when a panel
        // still exists mid-hide, generation must advance so hide completion is dropped.
        var generation: UInt = 0

        generation &+= 1
        let hideGeneration = generation

        // show()/showForCurrentState() while panel != nil
        generation &+= 1

        #expect(
            !FloatingIndicatorPresentationLifecycle.shouldApplyHideCompletion(
                hideGeneration: hideGeneration,
                currentGeneration: generation
            )
        )
        #expect(generation == hideGeneration &+ 1)
    }
}
