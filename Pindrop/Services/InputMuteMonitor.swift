//
//  InputMuteMonitor.swift
//  Pindrop
//
//  Created on 2026-07-09.
//
//  Observes the selected input device mute/volume via CoreAudio property listeners and
//  publishes `isMuted` for the floating indicator (orb/pill Muted state).
//

import AudioToolbox
import CoreAudio
import Foundation

// MARK: - Protocol seam

@MainActor
protocol InputMuteObserving: AnyObject {
    var isMuted: Bool { get }
    /// Called whenever mute state may have changed.
    var onMuteStateChange: ((Bool) -> Void)? { get set }

    func start()
    func stop()
    /// Switch observation to a different preferred device UID (empty = system default).
    func setPreferredDeviceUID(_ uid: String?)
}

// MARK: - CoreAudio property reading (testable via protocol)

@MainActor
protocol InputDeviceMuteReading: AnyObject {
    func resolveDeviceID(preferredUID: String?) -> AudioDeviceID?
    /// Returns mute state for the device. `nil` when the property is unsupported.
    func readIsMuted(deviceID: AudioDeviceID) -> Bool?
    func addMuteListener(
        deviceID: AudioDeviceID,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus
    func removeMuteListener(
        deviceID: AudioDeviceID,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    )
    func addDefaultInputListener(
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus
    func removeDefaultInputListener(
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    )
}

@MainActor
final class CoreAudioInputDeviceMuteReader: InputDeviceMuteReading {
    func resolveDeviceID(preferredUID: String?) -> AudioDeviceID? {
        if let preferredUID, !preferredUID.isEmpty,
           let id = AudioDeviceManager.inputDeviceID(for: preferredUID) {
            return id
        }
        return AudioDeviceManager.defaultInputDeviceID()
    }

    func readIsMuted(deviceID: AudioDeviceID) -> Bool? {
        // Prefer hardware mute when present.
        if let muted = readMuteFlag(deviceID: deviceID) {
            return muted
        }
        // Fall back to volume scalar: treat near-zero volume as muted.
        if let volume = readVolumeScalar(deviceID: deviceID) {
            return volume <= 0.0001
        }
        return nil
    }

    func addMuteListener(
        deviceID: AudioDeviceID,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        var addresses = Self.watchedAddresses
        var lastStatus: OSStatus = noErr
        var anySucceeded = false
        for index in addresses.indices {
            let status = AudioObjectAddPropertyListenerBlock(
                deviceID,
                &addresses[index],
                queue,
                block
            )
            if status == noErr {
                anySucceeded = true
            } else {
                lastStatus = status
            }
        }
        return anySucceeded ? noErr : lastStatus
    }

    func removeMuteListener(
        deviceID: AudioDeviceID,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var addresses = Self.watchedAddresses
        for index in addresses.indices {
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &addresses[index],
                queue,
                block
            )
        }
    }

    func addDefaultInputListener(
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        var address = Self.defaultInputAddress
        return AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
    }

    func removeDefaultInputListener(
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = Self.defaultInputAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
    }

    // MARK: - Private CoreAudio helpers

    private static let watchedAddresses: [AudioObjectPropertyAddress] = [
        AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyMute),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        ),
        AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        ),
        AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
    ]

    private static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
        mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
        mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )

    private func readMuteFlag(deviceID: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyMute),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else { return nil }
        return muted != 0
    }

    private func readVolumeScalar(deviceID: AudioDeviceID) -> Float32? {
        // Virtual master volume first, then channel-0 scalar.
        let selectors: [AudioObjectPropertySelector] = [
            AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume),
            AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar)
        ]
        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
            if status == noErr {
                return volume
            }
        }
        return nil
    }
}

// MARK: - Listener registration (nonisolated for deinit)

/// Holds registered CoreAudio listener blocks so teardown can run from `deinit`
/// without hopping to the MainActor (which is not allowed in a synchronous deinit).
private final class InputMuteListenerRegistration: @unchecked Sendable {
    private let lock = NSLock()
    private var deviceID: AudioDeviceID?
    private var muteBlock: AudioObjectPropertyListenerBlock?
    private var defaultBlock: AudioObjectPropertyListenerBlock?
    /// Optional test seam; production path removes listeners via CoreAudio directly.
    private let reader: (any InputDeviceMuteReading)?

    init(reader: (any InputDeviceMuteReading)? = nil) {
        self.reader = reader
    }

    func setDeviceListener(deviceID: AudioDeviceID, block: @escaping AudioObjectPropertyListenerBlock) {
        lock.lock()
        defer { lock.unlock() }
        self.deviceID = deviceID
        self.muteBlock = block
    }

    func setDefaultListener(block: @escaping AudioObjectPropertyListenerBlock) {
        lock.lock()
        defer { lock.unlock() }
        self.defaultBlock = block
    }

    func clearDeviceListener() {
        lock.lock()
        defer { lock.unlock() }
        deviceID = nil
        muteBlock = nil
    }

    func clearDefaultListener() {
        lock.lock()
        defer { lock.unlock() }
        defaultBlock = nil
    }

    /// Idempotent: removes any registered listeners and clears stored refs.
    func tearDown() {
        lock.lock()
        let deviceID = self.deviceID
        let muteBlock = self.muteBlock
        let defaultBlock = self.defaultBlock
        self.deviceID = nil
        self.muteBlock = nil
        self.defaultBlock = nil
        let reader = self.reader
        lock.unlock()

        if let deviceID, let muteBlock {
            if let reader {
                // Test path: notify mock reader so tests can assert remove counts.
                Self.notifyReaderRemoveMute(reader, deviceID: deviceID, block: muteBlock)
            }
            // Always remove via CoreAudio so production listeners never leak, even if
            // the Task above is still pending when the process is tearing down.
            Self.removeMuteListenersDirectly(deviceID: deviceID, block: muteBlock)
        }
        if let defaultBlock {
            if let reader {
                Self.notifyReaderRemoveDefault(reader, block: defaultBlock)
            }
            Self.removeDefaultListenerDirectly(block: defaultBlock)
        }
    }

    private static func notifyReaderRemoveMute(
        _ reader: any InputDeviceMuteReading,
        deviceID: AudioDeviceID,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        Task { @MainActor in
            reader.removeMuteListener(deviceID: deviceID, queue: .main, block: block)
        }
    }

    private static func notifyReaderRemoveDefault(
        _ reader: any InputDeviceMuteReading,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        Task { @MainActor in
            reader.removeDefaultInputListener(queue: .main, block: block)
        }
    }

    private static func removeMuteListenersDirectly(
        deviceID: AudioDeviceID,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var addresses = [
            AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyMute),
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            ),
            AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume),
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            ),
            AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar),
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeInput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
        ]
        for index in addresses.indices {
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &addresses[index],
                DispatchQueue.main,
                block
            )
        }
    }

    private static func removeDefaultListenerDirectly(block: @escaping AudioObjectPropertyListenerBlock) {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }
}

// MARK: - Monitor

@MainActor
@Observable
final class InputMuteMonitor: InputMuteObserving {
    private(set) var isMuted: Bool = false
    var onMuteStateChange: ((Bool) -> Void)?

    private let reader: any InputDeviceMuteReading
    private var preferredDeviceUID: String?
    private var observedDeviceID: AudioDeviceID?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?
    private var didLogUnsupportedMute = false
    private var isRunning = false
    /// Nonisolated registration bookkeeping so `deinit` can tear down listeners.
    private let listenerRegistration: InputMuteListenerRegistration

    init(
        preferredDeviceUID: String? = nil,
        reader: (any InputDeviceMuteReading)? = nil
    ) {
        self.preferredDeviceUID = preferredDeviceUID
        let resolvedReader = reader ?? CoreAudioInputDeviceMuteReader()
        self.reader = resolvedReader
        // Pass the reader only when it's a test double (non-CoreAudio) so mock remove
        // counts still work. Production always uses direct CoreAudio removal in tearDown.
        self.listenerRegistration = InputMuteListenerRegistration(
            reader: reader
        )
    }

    deinit {
        // Always tear down CoreAudio listeners if the monitor is deallocated without stop().
        // Idempotent: tearDown no-ops when no listeners are registered.
        listenerRegistration.tearDown()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        installDefaultInputListener()
        rebindToPreferredDevice()
    }

    func stop() {
        isRunning = false
        tearDownListeners()
        isMuted = false
    }

    /// Shared cleanup for `stop()`. Safe to call multiple times.
    private func tearDownListeners() {
        removeDeviceListeners()
        removeDefaultInputListener()
        observedDeviceID = nil
        // Registration tearDown is also invoked by deinit; calling both is safe.
        listenerRegistration.tearDown()
    }

    func setPreferredDeviceUID(_ uid: String?) {
        let normalized = (uid?.isEmpty == true) ? nil : uid
        preferredDeviceUID = normalized
        guard isRunning else { return }
        rebindToPreferredDevice()
    }

    // MARK: - Binding

    private func rebindToPreferredDevice() {
        removeDeviceListeners()
        observedDeviceID = nil
        didLogUnsupportedMute = false

        guard let deviceID = reader.resolveDeviceID(preferredUID: preferredDeviceUID) else {
            publishMuted(false)
            return
        }

        observedDeviceID = deviceID
        installDeviceListeners(deviceID: deviceID)
        refreshMuteState()
    }

    private func refreshMuteState() {
        guard let deviceID = observedDeviceID else {
            publishMuted(false)
            return
        }

        if let muted = reader.readIsMuted(deviceID: deviceID) {
            publishMuted(muted)
        } else {
            if !didLogUnsupportedMute {
                didLogUnsupportedMute = true
                Log.audio.info(
                    "Input device does not support mute/volume observation (deviceID=\(deviceID)); treating as unmuted"
                )
            }
            publishMuted(false)
        }
    }

    private func publishMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        onMuteStateChange?(muted)
    }

    // MARK: - Listeners

    private func installDeviceListeners(deviceID: AudioDeviceID) {
        // Listener is registered on the main queue; hop to MainActor for @Observable updates.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshMuteState()
            }
        }
        let status = reader.addMuteListener(
            deviceID: deviceID,
            queue: .main,
            block: block
        )
        if status == noErr {
            muteListenerBlock = block
            listenerRegistration.setDeviceListener(deviceID: deviceID, block: block)
        } else {
            Log.audio.debug(
                "Could not attach mute/volume listeners for deviceID=\(deviceID) status=\(status)"
            )
            // Still try a one-shot read; unsupported property is handled there.
            refreshMuteState()
        }
    }

    private func removeDeviceListeners() {
        guard let deviceID = observedDeviceID, let block = muteListenerBlock else {
            muteListenerBlock = nil
            listenerRegistration.clearDeviceListener()
            return
        }
        reader.removeMuteListener(deviceID: deviceID, queue: .main, block: block)
        muteListenerBlock = nil
        listenerRegistration.clearDeviceListener()
    }

    private func installDefaultInputListener() {
        guard defaultInputListenerBlock == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                // Default input or preferred device may have changed — re-resolve.
                self?.rebindToPreferredDevice()
            }
        }
        let status = reader.addDefaultInputListener(queue: .main, block: block)
        if status == noErr {
            defaultInputListenerBlock = block
            listenerRegistration.setDefaultListener(block: block)
        } else {
            Log.audio.debug("Could not observe default input device changes: status=\(status)")
        }
    }

    private func removeDefaultInputListener() {
        guard let block = defaultInputListenerBlock else { return }
        reader.removeDefaultInputListener(queue: .main, block: block)
        defaultInputListenerBlock = nil
        listenerRegistration.clearDefaultListener()
    }
}
