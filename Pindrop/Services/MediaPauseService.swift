//
//  MediaPauseService.swift
//  Pindrop
//
//  Created on 2026-02-14.
//

import CoreAudio
import Foundation

@MainActor
final class MediaPauseService {
   private typealias SendCommandFunction = @convention(c) (UInt32, CFDictionary?) -> Bool
   private typealias GetNowPlayingIsPlayingFunction =
      @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

   private struct SystemAudioState {
      let deviceID: AudioDeviceID
      let previousMute: UInt32?
      let previousVolume: Float32?
   }

   private static let mediaRemoteFrameworkPath =
      "/System/Library/PrivateFrameworks/MediaRemote.framework"
   private static let playCommand: UInt32 = 0
   private static let pauseCommand: UInt32 = 1

   private var sendCommandFunction: SendCommandFunction?
   private var getNowPlayingIsPlayingFunction: GetNowPlayingIsPlayingFunction?
   /// Once true, MediaRemote resolution has been attempted and must not repeat,
   /// including when symbols were unavailable.
   private var didResolveMediaRemoteSymbols = false
   private var didPauseMediaForSession = false
   private var systemAudioState: SystemAudioState?
   private var sessionActive = false
   private var pauseTask: Task<Void, Never>?
   private var sessionGeneration: UInt64 = 0

   init() {}

   func beginRecordingSession(pauseMedia: Bool, muteSystemAudio: Bool) {
      guard !sessionActive else { return }

      sessionGeneration &+= 1
      let generation = sessionGeneration
      sessionActive = true

      // Mute is a fast CoreAudio property write; do it synchronously.
      if muteSystemAudio {
         systemAudioState = muteSystemOutputIfNeeded()
      }

      // MediaRemote Now Playing queries are callback-based. Kick them off
      // without parking MainActor on a semaphore so recording start stays responsive.
      // Resolve private-framework symbols only for pause-enabled sessions.
      if pauseMedia {
         ensureMediaRemoteSymbolsLoaded()
         pauseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.pauseMediaForActiveSessionIfNeeded(generation: generation)
            if self.sessionGeneration == generation {
               self.pauseTask = nil
            }
         }
      }
   }

   func endRecordingSession() {
      guard sessionActive else { return }

      sessionGeneration &+= 1
      sessionActive = false
      pauseTask?.cancel()
      pauseTask = nil

      if didPauseMediaForSession, let sendCommandFunction {
         _ = sendCommandFunction(Self.playCommand, nil)
         Log.app.debug("Resumed media playback after recording")
      }

      didPauseMediaForSession = false
      restoreSystemOutputIfNeeded()
   }

   private func pauseMediaForActiveSessionIfNeeded(generation: UInt64) async {
      guard sessionActive, sessionGeneration == generation else { return }

      let didPause = await pauseMediaIfNeeded(generation: generation)

      // The session may have ended or been replaced while the Now Playing query
      // was outstanding. A successful late pause must be undone immediately.
      guard sessionActive, sessionGeneration == generation else {
         if didPause, let sendCommandFunction {
            _ = sendCommandFunction(Self.playCommand, nil)
            Log.app.debug("Resumed media playback after late pause during session teardown")
         }
         return
      }

      didPauseMediaForSession = didPause
   }

   private func pauseMediaIfNeeded(generation: UInt64) async -> Bool {
      guard let sendCommandFunction else {
         Log.app.debug("Media pause unavailable: MediaRemote command function missing")
         return false
      }

      guard await isNowPlayingActive() else {
         Log.app.debug("Media pause skipped: no active Now Playing session")
         return false
      }

      guard sessionActive, sessionGeneration == generation, !Task.isCancelled else {
         return false
      }

      let didPause = sendCommandFunction(Self.pauseCommand, nil)
      if didPause {
         Log.app.info("Paused active media playback")
      } else {
         Log.app.debug("MediaRemote pause command returned false")
      }

      return didPause
   }

   private func muteSystemOutputIfNeeded() -> SystemAudioState? {
      guard let deviceID = defaultOutputDeviceID() else {
         Log.app.debug("System mute skipped: no default output device")
         return nil
      }

      if let previousMute = currentMuteState(deviceID: deviceID) {
         if previousMute == 0 {
            _ = setMuteState(1, deviceID: deviceID)
            Log.app.info("Muted system audio for recording session")
         }
         return SystemAudioState(
            deviceID: deviceID, previousMute: previousMute, previousVolume: nil)
      }

      if let previousVolume = currentOutputVolume(deviceID: deviceID) {
         if previousVolume > 0 {
            _ = setOutputVolume(0, deviceID: deviceID)
            Log.app.info("Set output volume to 0 for recording session")
         }
         return SystemAudioState(
            deviceID: deviceID, previousMute: nil, previousVolume: previousVolume)
      }

      Log.app.debug("System mute skipped: output device does not expose mute or volume controls")
      return nil
   }

   private func restoreSystemOutputIfNeeded() {
      guard let state = systemAudioState else { return }

      if let previousMute = state.previousMute {
         _ = setMuteState(previousMute, deviceID: state.deviceID)
         Log.app.debug("Restored previous mute state after recording")
      } else if let previousVolume = state.previousVolume {
         _ = setOutputVolume(previousVolume, deviceID: state.deviceID)
         Log.app.debug("Restored previous output volume after recording")
      }

      systemAudioState = nil
   }

   /// Lazily resolves MediaRemote function pointers on first pause-enabled use.
   /// Subsequent calls reuse the cached success or failure state.
   private func ensureMediaRemoteSymbolsLoaded() {
      guard !didResolveMediaRemoteSymbols else { return }
      didResolveMediaRemoteSymbols = true

      let bundleURL = URL(fileURLWithPath: Self.mediaRemoteFrameworkPath)

      guard let bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL as CFURL) else {
         Log.app.debug("MediaRemote load failed: bundle creation error")
         return
      }

      guard
         let sendCommandPointer = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteSendCommand" as CFString)
      else {
         Log.app.debug("MediaRemote load failed: MRMediaRemoteSendCommand not found")
         return
      }

      sendCommandFunction = unsafeBitCast(sendCommandPointer, to: SendCommandFunction.self)

      if let nowPlayingPointer = CFBundleGetFunctionPointerForName(
         bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString)
      {
         getNowPlayingIsPlayingFunction = unsafeBitCast(
            nowPlayingPointer, to: GetNowPlayingIsPlayingFunction.self)
      } else {
         Log.app.debug(
            "MediaRemote load warning: MRMediaRemoteGetNowPlayingApplicationIsPlaying not found")
      }
   }

   private func isNowPlayingActive() async -> Bool {
      guard let getNowPlayingIsPlayingFunction else {
         return false
      }

      let bridge = NowPlayingQueryBridge()
      return await withTaskCancellationHandler {
         await withCheckedContinuation { continuation in
            guard bridge.installContinuation(continuation) else {
               continuation.resume(returning: false)
               return
            }

            getNowPlayingIsPlayingFunction(DispatchQueue.global(qos: .userInitiated)) { playing in
               bridge.resume(playing)
            }

            let timeoutTask = Task {
               try? await Task.sleep(for: .milliseconds(500))
               guard !Task.isCancelled else { return }
               if bridge.resume(false) {
                  Log.app.debug("MediaRemote Now Playing query timed out")
               }
            }
            bridge.installTimeoutTask(timeoutTask)
         }
      } onCancel: {
         bridge.resume(false)
      }
   }

   private func defaultOutputDeviceID() -> AudioDeviceID? {
      var address = AudioObjectPropertyAddress(
         mSelector: kAudioHardwarePropertyDefaultOutputDevice,
         mScope: kAudioObjectPropertyScopeGlobal,
         mElement: kAudioObjectPropertyElementMain
      )

      var deviceID = AudioDeviceID(0)
      var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

      let status = AudioObjectGetPropertyData(
         AudioObjectID(kAudioObjectSystemObject),
         &address,
         0,
         nil,
         &dataSize,
         &deviceID
      )

      guard status == noErr else {
         return nil
      }

      return deviceID
   }

   private func currentMuteState(deviceID: AudioDeviceID) -> UInt32? {
      var address = AudioObjectPropertyAddress(
         mSelector: kAudioDevicePropertyMute,
         mScope: kAudioDevicePropertyScopeOutput,
         mElement: kAudioObjectPropertyElementMain
      )

      guard AudioObjectHasProperty(deviceID, &address) else {
         return nil
      }

      var muteState: UInt32 = 0
      var dataSize = UInt32(MemoryLayout<UInt32>.size)

      let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &muteState)
      guard status == noErr else {
         return nil
      }

      return muteState
   }

   @discardableResult
   private func setMuteState(_ value: UInt32, deviceID: AudioDeviceID) -> Bool {
      var mutableValue = value
      var address = AudioObjectPropertyAddress(
         mSelector: kAudioDevicePropertyMute,
         mScope: kAudioDevicePropertyScopeOutput,
         mElement: kAudioObjectPropertyElementMain
      )

      guard AudioObjectHasProperty(deviceID, &address) else {
         return false
      }

      let status = AudioObjectSetPropertyData(
         deviceID,
         &address,
         0,
         nil,
         UInt32(MemoryLayout<UInt32>.size),
         &mutableValue
      )

      return status == noErr
   }

   private func currentOutputVolume(deviceID: AudioDeviceID) -> Float32? {
      var address = AudioObjectPropertyAddress(
         mSelector: kAudioDevicePropertyVolumeScalar,
         mScope: kAudioDevicePropertyScopeOutput,
         mElement: kAudioObjectPropertyElementMain
      )

      guard AudioObjectHasProperty(deviceID, &address) else {
         return nil
      }

      var volume: Float32 = 0
      var dataSize = UInt32(MemoryLayout<Float32>.size)

      let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)
      guard status == noErr else {
         return nil
      }

      return volume
   }

   @discardableResult
   private func setOutputVolume(_ value: Float32, deviceID: AudioDeviceID) -> Bool {
      var mutableValue = value
      var address = AudioObjectPropertyAddress(
         mSelector: kAudioDevicePropertyVolumeScalar,
         mScope: kAudioDevicePropertyScopeOutput,
         mElement: kAudioObjectPropertyElementMain
      )

      guard AudioObjectHasProperty(deviceID, &address) else {
         return false
      }

      let status = AudioObjectSetPropertyData(
         deviceID,
         &address,
         0,
         nil,
         UInt32(MemoryLayout<Float32>.size),
         &mutableValue
      )

      return status == noErr
   }
}

/// Resumes a now-playing query continuation exactly once across the MediaRemote
/// callback and the async timeout path.
private final class NowPlayingQueryBridge: @unchecked Sendable {
   private let lock = NSLock()
   private var continuation: CheckedContinuation<Bool, Never>?
   private var timeoutTask: Task<Void, Never>?
   private var isFinished = false

   func installContinuation(_ continuation: CheckedContinuation<Bool, Never>) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard !isFinished else { return false }
      self.continuation = continuation
      return true
   }

   func installTimeoutTask(_ task: Task<Void, Never>) {
      lock.lock()
      if isFinished {
         lock.unlock()
         task.cancel()
         return
      }
      timeoutTask = task
      lock.unlock()
   }

   /// Returns `true` when this call performed the continuation resume.
   @discardableResult
   func resume(_ value: Bool) -> Bool {
      lock.lock()
      guard !isFinished else {
         lock.unlock()
         return false
      }
      isFinished = true
      let pending = continuation
      continuation = nil
      let timeoutTask = timeoutTask
      self.timeoutTask = nil
      lock.unlock()

      timeoutTask?.cancel()
      pending?.resume(returning: value)
      return pending != nil
   }
}
