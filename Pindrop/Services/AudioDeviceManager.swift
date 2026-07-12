//
//  AudioDeviceManager.swift
//  Pindrop
//
//  Created on 2026-02-05.
//

import Foundation
import CoreAudio
import os.log

struct AudioInputDevice: Identifiable, Hashable {
    let deviceID: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool
    
    var id: String { uid }
    
    var displayName: String {
        if isDefault {
            return "\(name) (Default)"
        }
        return name
    }
}

enum AudioDeviceManager {
    static func inputDevices() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()
        let devices = deviceIDs()
            .filter { inputChannelCount($0) > 0 }
            .map { deviceID in
                let uid = deviceUID(deviceID)
                let resolvedUID = uid.isEmpty ? String(deviceID) : uid
                let name = deviceName(deviceID)
                let resolvedName = name.isEmpty ? "Audio Device \(deviceID)" : name
                return AudioInputDevice(
                    deviceID: deviceID,
                    uid: resolvedUID,
                    name: resolvedName,
                    isDefault: deviceID == defaultID
                )
            }
        
        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    static func inputDeviceID(for uid: String?) -> AudioDeviceID? {
        guard let uid = uid, !uid.isEmpty else { return nil }
        for deviceID in deviceIDs() {
            if deviceUID(deviceID) == uid || String(deviceID) == uid {
                return deviceID
            }
        }
        return nil
    }
    
    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        if status != noErr {
            Log.audio.error("Failed to get default input device: \(status)")
            return nil
        }
        
        return deviceID
    }

    static func nominalSampleRate(_ deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyNominalSampleRate),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        var sampleRate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        guard status == noErr, sampleRate > 0 else { return nil }
        return sampleRate
    }
    
    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        if status != noErr {
            Log.audio.error("Failed to get audio device list size: \(status)")
            return []
        }
        
        let deviceCount = Int(size / UInt32(MemoryLayout<AudioDeviceID>.size))
        guard deviceCount > 0 else { return [] }
        
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = deviceIDs.withUnsafeMutableBufferPointer { bufferPointer in
            guard let pointer = bufferPointer.baseAddress else { return -1 }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        
        if status != noErr {
            Log.audio.error("Failed to get audio device list: \(status)")
            return []
        }
        
        return deviceIDs
    }
    
    private static func deviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceNameCFString),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        if status != noErr {
            return ""
        }
        
        return name?.takeUnretainedValue() as String? ?? ""
    }
    
    private static func deviceUID(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceUID),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        if status != noErr {
            return ""
        }
        
        return uid?.takeUnretainedValue() as String? ?? ""
    }
    
    private static func inputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreamConfiguration),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        if status != noErr {
            return 0
        }
        
        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }
        let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList)
        if status != noErr {
            return 0
        }
        
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

// MARK: - Cached input-device snapshot

/// Maintains a cached snapshot of input devices, refreshed only when CoreAudio
/// reports device-list or default-input-device changes. UI hot paths (status menu
/// row render) should read this cache instead of calling `inputDevices()`.
///
/// Reuses `AudioDeviceListMonitor` for device-list observation and adds a single
/// default-input listener. Registration is refcounted via `start()` / `stop()` so
/// teardown is explicit and idempotent.
final class AudioInputDeviceCache {
    static let shared = AudioInputDeviceCache()

    /// Fired on the main queue after the snapshot is refreshed to a new value.
    var onChange: (() -> Void)?

    private let lock = NSLock()
    private var cachedDevices: [AudioInputDevice] = []
    private var startCount = 0
    private let deviceListMonitor = AudioDeviceListMonitor()
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
        mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
        mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )

    /// Latest input-device snapshot. Empty until `start()` has refreshed once.
    var devices: [AudioInputDevice] {
        lock.lock()
        defer { lock.unlock() }
        return cachedDevices
    }

    deinit {
        // Force full teardown regardless of startCount so listeners never leak.
        tearDownListeners()
    }

    /// Begins observing CoreAudio (refcounted). Safe to call multiple times.
    func start() {
        lock.lock()
        startCount += 1
        let shouldInstall = startCount == 1
        lock.unlock()

        guard shouldInstall else { return }
        installListeners()
        refreshSnapshot(notify: false)
    }

    /// Drops one start reference and tears down listeners when the count hits zero.
    /// Idempotent when already stopped.
    func stop() {
        lock.lock()
        guard startCount > 0 else {
            lock.unlock()
            return
        }
        startCount -= 1
        let shouldTearDown = startCount == 0
        lock.unlock()

        guard shouldTearDown else { return }
        tearDownListeners()
    }

    /// Forces a re-enumeration into the cache. Prefer listener-driven refresh.
    func refreshNow() {
        refreshSnapshot(notify: true)
    }

    func device(uid: String) -> AudioInputDevice? {
        devices.first { $0.uid == uid }
    }

    /// MainActor-safe observation token. `tearDown()` is nonisolated and idempotent so
    /// `@MainActor` owners can call it from `deinit`.
    func makeObservation(onChange: @escaping () -> Void) -> Observation {
        Observation(cache: self, onChange: onChange)
    }

    private func installListeners() {
        deviceListMonitor.onChange = { [weak self] in
            self?.refreshSnapshot(notify: true)
        }
        deviceListMonitor.start()

        if defaultInputListener == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                // Default-input flips are single events — refresh on the main queue.
                if Thread.isMainThread {
                    self?.refreshSnapshot(notify: true)
                } else {
                    DispatchQueue.main.async {
                        self?.refreshSnapshot(notify: true)
                    }
                }
            }
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultInputAddress,
                DispatchQueue.main,
                block
            )
            if status == noErr {
                defaultInputListener = block
            } else {
                Log.audio.error("Failed to observe default input device for cache: status=\(status)")
            }
        }
    }

    /// Removes listeners and pending work. Safe to call repeatedly.
    private func tearDownListeners() {
        deviceListMonitor.onChange = nil
        deviceListMonitor.stop()

        if let block = defaultInputListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultInputAddress,
                DispatchQueue.main,
                block
            )
            defaultInputListener = nil
        }

        lock.lock()
        startCount = 0
        lock.unlock()
    }

    private func refreshSnapshot(notify: Bool) {
        let snapshot = AudioDeviceManager.inputDevices()
        lock.lock()
        let previous = cachedDevices
        cachedDevices = snapshot
        lock.unlock()

        guard notify else { return }
        // Drop no-op refreshes so status-row consumers resolve once per real change.
        if previous == snapshot { return }
        if Thread.isMainThread {
            onChange?()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onChange?()
            }
        }
    }

    /// Nonisolated lifecycle handle for one consumer of the shared cache.
    final class Observation: @unchecked Sendable {
        private let cache: AudioInputDeviceCache
        private let lock = NSLock()
        private var isActive = true

        fileprivate init(cache: AudioInputDeviceCache, onChange: @escaping () -> Void) {
            self.cache = cache
            cache.onChange = onChange
            cache.start()
        }

        /// Idempotent: clears the callback and drops one start reference.
        func tearDown() {
            lock.lock()
            let wasActive = isActive
            isActive = false
            lock.unlock()
            guard wasActive else { return }
            cache.onChange = nil
            cache.stop()
        }

        deinit {
            tearDown()
        }
    }
}

/// Watches the system audio device list and fires `onChange` on the main queue when
/// devices are added or removed. Changes are debounced because a single unplug can
/// re-enumerate the device list several times in quick succession.
final class AudioDeviceListMonitor {
    private static let debounceInterval: TimeInterval = 0.5

    var onChange: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var debounceWorkItem: DispatchWorkItem?
    private var address = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
        mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
        mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )

    deinit {
        stop()
    }

    func start() {
        guard listenerBlock == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleChangeNotification()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        guard status == noErr else {
            Log.audio.error("Failed to observe audio device list changes: status=\(status)")
            return
        }
        listenerBlock = block
    }

    func stop() {
        if let block = listenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            listenerBlock = nil
        }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    private func scheduleChangeNotification() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }
}
