//
//  TaskScheduler.swift
//  Pindrop
//
//  Created on 2026-03-21.
//

import Foundation

protocol ScheduledTask: AnyObject {
    func cancel()
}

protocol TaskScheduling {
    var now: Date { get }
    func schedule(after delay: TimeInterval, operation: @escaping @MainActor () -> Void) -> ScheduledTask
}

final class DefaultTaskScheduler: TaskScheduling {
    var now: Date {
        Date()
    }

    func schedule(after delay: TimeInterval, operation: @escaping @MainActor () -> Void) -> ScheduledTask {
        let task = Task { @MainActor in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }
            operation()
        }

        return ScheduledTaskHandle(cancelHandler: {
            task.cancel()
        })
    }
}

private final class ScheduledTaskHandle: ScheduledTask {
    private let cancelHandler: () -> Void

    init(cancelHandler: @escaping () -> Void) {
        self.cancelHandler = cancelHandler
    }

    func cancel() {
        cancelHandler()
    }
}
