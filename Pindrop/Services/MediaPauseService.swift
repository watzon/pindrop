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
   private var didPauseMediaForSession = false
   private var systemAudioState: SystemAudioState?
   private var sessionActive = false

   init() {
      loadMediaRemoteFramework()
   }

   func beginRecordingSession(pauseMedia: Bool, muteSystemAudio: Bool) {
      guard !sessionActive else { return }

      sessionActive = true

      if pauseMedia {
         didPauseMediaForSession = pauseMediaIfNeeded()
      }

      if muteSystemAudio {
         systemAudioState = muteSystemOutputIfNeeded()
      }
   }

   func endRecordingSession() {
      guard sessionActive else { return }

      if didPauseMediaForSession, let sendCommandFunction {
         _ = sendCommandFunction(Self.playCommand, nil)
         Log.app.debug("Resumed media playback after recording")
      }

      didPauseMediaForSession = false
      restoreSystemOutputIfNeeded()
      sessionActive = false
   }

   private func pauseMediaIfNeeded() -> Bool {
      guard let sendCommandFunction else {
         Log.app.debug("Media pause unavailable: MediaRemote command function missing")
         return false
      }

      guard isNowPlayingActive() else {
         Log.app.debug("Media pause skipped: no active Now Playing session")
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

   private func loadMediaRemoteFramework() {
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

   private func isNowPlayingActive() -> Bool {
      guard let getNowPlayingIsPlayingFunction else {
         return false
      }

      let semaphore = DispatchSemaphore(value: 0)
      var isPlaying = false

      getNowPlayingIsPlayingFunction(DispatchQueue.global(qos: .userInitiated)) { playing in
         isPlaying = playing
         semaphore.signal()
      }

      if semaphore.wait(timeout: .now() + 0.5) == .timedOut {
         Log.app.debug("MediaRemote Now Playing query timed out")
         return false
      }

      return isPlaying
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
