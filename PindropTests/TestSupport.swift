//
//  TestSupport.swift
//  PindropTests
//
//  Created on 2026-03-21.
//

import Foundation
@testable import Pindrop

final class ManualTaskScheduler: TaskScheduling {
    private struct PendingTask {
        let sequence: Int
        let fireAt: Date
        let operation: @MainActor () -> Void
        let token: Token
    }

    final class Token: ScheduledTask {
        fileprivate var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var now: Date
    private var pendingTasks: [PendingTask] = []
    private var nextSequence = 0

    init(now: Date = Date(timeIntervalSince1970: 0)) {
        self.now = now
    }

    func schedule(after delay: TimeInterval, operation: @escaping @MainActor () -> Void) -> ScheduledTask {
        let token = Token()
        let task = PendingTask(
            sequence: nextSequence,
            fireAt: now.addingTimeInterval(delay),
            operation: operation,
            token: token
        )
        nextSequence += 1
        pendingTasks.append(task)
        return token
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
        runDueTasks()
    }

    private func runDueTasks() {
        while let nextIndex = nextDueTaskIndex() {
            let task = pendingTasks.remove(at: nextIndex)
            guard !task.token.isCancelled else { continue }
            MainActor.assumeIsolated {
                task.operation()
            }
        }
    }

    private func nextDueTaskIndex() -> Int? {
        pendingTasks
            .enumerated()
            .filter { $0.element.fireAt <= now }
            .min {
                if $0.element.fireAt == $1.element.fireAt {
                    return $0.element.sequence < $1.element.sequence
                }
                return $0.element.fireAt < $1.element.fireAt
            }?
            .offset
    }
}
