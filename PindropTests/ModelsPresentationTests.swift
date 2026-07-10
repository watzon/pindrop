//
//  ModelsPresentationTests.swift
//  PindropTests
//
//  Created on 2026-07-10.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct ModelsPresentationTests {

    // MARK: - Disk total aggregation

    @Test func totalMegabytesSumsInstalledOnly() {
        let speech: [(isInstalled: Bool, sizeInMB: Int)] = [
            (true, 500),
            (false, 3000),
            (true, 145),
        ]
        let features: [(isInstalled: Bool, sizeInMB: Int)] = [
            (true, 100),
            (false, 650),
        ]
        #expect(
            ModelsDiskTotal.totalMegabytes(speechModels: speech, featureModels: features)
                == 500 + 145 + 100
        )
    }

    @Test func totalMegabytesEmptyIsZero() {
        #expect(
            ModelsDiskTotal.totalMegabytes(speechModels: [], featureModels: []) == 0
        )
    }

    // MARK: - Formatting

    @Test func formattedMegabytesBelowGB() {
        #expect(ModelsDiskTotal.formatted(megabytes: 0) == "0 MB")
        #expect(ModelsDiskTotal.formatted(megabytes: 75) == "75 MB")
        #expect(ModelsDiskTotal.formatted(megabytes: 999) == "999 MB")
    }

    @Test func formattedMegabytesAsGB() {
        #expect(ModelsDiskTotal.formatted(megabytes: 1000) == "1 GB")
        #expect(ModelsDiskTotal.formatted(megabytes: 3200) == "3.2 GB")
        #expect(ModelsDiskTotal.formatted(megabytes: 1500) == "1.5 GB")
    }

    @Test func formattedTotalConvenience() {
        let text = ModelsDiskTotal.formattedTotal(
            speechModels: [(true, 2200), (false, 500)],
            featureModels: [(true, 100)]
        )
        #expect(text == "2.3 GB")
    }
}
