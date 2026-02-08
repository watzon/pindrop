//
//  MockPermissionProvider.swift
//  PindropTests
//
//  Created on 2026-02-08.
//

import Foundation
@testable import Pindrop

final class MockPermissionProvider: PermissionProviding {
    var grantPermission: Bool = true
    var requestPermissionCallCount: Int = 0

    func requestPermission() async -> Bool {
        requestPermissionCallCount += 1
        return grantPermission
    }
}
