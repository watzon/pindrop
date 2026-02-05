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
