//
//  MicSwitcherApp.swift
//  MicSwitcher
//
//  Created by Matthias Goetzke on 16.07.25.
//

import SwiftUI
import CoreAudio
import UserNotifications
import AppKit  // For NSSound

// Singleton for app state to avoid StateObject issues
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentDefaultID: AudioObjectID
    var previousDevices: Set<AudioDeviceID>
    
    private init() {
        currentDefaultID = getDefaultInputDevice()
        previousDevices = Set(getInputDevices().map { $0.id })
    }
    
    func sendNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "MicSwitcher"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Notification error: \(error)") }
        }
        NSSound.beep()  // System sound
    }
}

class AudioMonitor {
    let onDefaultChange: () -> Void
    let onDevicesChange: () -> Void
    private var defaultAddress: AudioObjectPropertyAddress
    private var devicesAddress: AudioObjectPropertyAddress
    
    init(onDefaultChange: @escaping () -> Void, onDevicesChange: @escaping () -> Void) {
        self.onDefaultChange = onDefaultChange
        self.onDevicesChange = onDevicesChange
        
        defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        devicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListener(system, &defaultAddress, audioListenerCallback, Unmanaged.passUnretained(self).toOpaque())
        AudioObjectAddPropertyListener(system, &devicesAddress, audioListenerCallback, Unmanaged.passUnretained(self).toOpaque())
    }
    
    deinit {
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListener(system, &defaultAddress, audioListenerCallback, Unmanaged.passUnretained(self).toOpaque())
        AudioObjectRemovePropertyListener(system, &devicesAddress, audioListenerCallback, Unmanaged.passUnretained(self).toOpaque())
    }
}

private let audioListenerCallback: AudioObjectPropertyListenerProc = { _, inNumberAddresses, inAddresses, clientData in
    guard let clientData = clientData else { return noErr }
    let monitor = Unmanaged<AudioMonitor>.fromOpaque(clientData).takeUnretainedValue()
    
    for i in 0..<Int(inNumberAddresses) {
        let addr = inAddresses.advanced(by: i).pointee
        DispatchQueue.main.async {
            if addr.mSelector == kAudioHardwarePropertyDefaultInputDevice {
                monitor.onDefaultChange()
            } else if addr.mSelector == kAudioHardwarePropertyDevices {
                monitor.onDevicesChange()
            }
        }
    }
    return noErr
}

@main
struct MicSwitcherApp: App {
    
    init() {
        setupNotifications()
        _ = AudioMonitor(
            onDefaultChange: {
                AppState.shared.currentDefaultID = getDefaultInputDevice()
                AppState.shared.sendNotification(message: "Microphone switched to \(getDeviceName(for: AppState.shared.currentDefaultID) ?? "Unknown")")
            },
            onDevicesChange: {
                let newDevices = getInputDevices()
                let newIDs = Set(newDevices.map { $0.id })
                let removed = AppState.shared.previousDevices.subtracting(newIDs)
                let added = newIDs.subtracting(AppState.shared.previousDevices)
                
                for id in removed {
                    AppState.shared.sendNotification(message: "Microphone no longer available: \(getDeviceName(for: id) ?? "Unknown")")
                }
                for id in added {
                    AppState.shared.sendNotification(message: "New microphone detected: \(getDeviceName(for: id) ?? "Unknown")")
                }
                
                AppState.shared.previousDevices = newIDs
                
                // Check if default needs update (e.g., if current default was removed)
                let current = getDefaultInputDevice()
                if !newIDs.contains(current) {
                    if let fallback = newDevices.first?.id {
                        setDefaultInputDevice(fallback)
                        AppState.shared.currentDefaultID = fallback
                        AppState.shared.sendNotification(message: "Switched to fallback microphone: \(getDeviceName(for: fallback) ?? "Unknown")")
                    }
                }
            }
        )
    }
    
    var body: some Scene {
        MenuBarExtra {
            MicMenuContent()
        } label: {
            Image(systemName: "mic")  // Menu bar icon
        }
    }
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error { print("Notification permission error: \(error)") }
        }
    }
}

// Reactive menu content
struct MicMenuContent: View {
    @ObservedObject private var state = AppState.shared
    
    var body: some View {
        let devices = getInputDevices().filter { !$0.name.lowercased().contains("iphone") }
        
        ForEach(devices, id: \.id) { device in
            Button(action: {
                setDefaultInputDevice(device.id)
                state.currentDefaultID = device.id
                state.sendNotification(message: "Manually switched to \(device.name)")  // Notify on manual switch
            }) {
                HStack {
                    Text(device.name)
                    if device.id == state.currentDefaultID {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

// Helpers remain the same
func getInputDevices() -> [(id: AudioDeviceID, name: String)] {
    var devices: [(AudioDeviceID, String)] = []
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
    let numDevices = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
    var deviceIDs = Array(repeating: AudioDeviceID(0), count: numDevices)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
    
    for id in deviceIDs {
        var channelsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: 0
        )
        var bufListSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &channelsAddress, 0, nil, &bufListSize)
        let bufList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(bufListSize))
        AudioObjectGetPropertyData(id, &channelsAddress, 0, nil, &bufListSize, bufList)
        let numBuffers = Int(bufList.pointee.mNumberBuffers)
        bufList.deallocate()
        if numBuffers > 0 {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
            var name: CFString? = nil
            withUnsafeMutablePointer(to: &name) {
                _ = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, $0)
            }
            if let deviceName = name as String? {
                devices.append((id, deviceName))
            } else {
                devices.append((id, "Unknown Device"))
            }
        }
    }
    return devices
}

func getDefaultInputDevice() -> AudioObjectID {
    var defaultID: AudioDeviceID = 0
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &defaultID)
    return defaultID
}

func setDefaultInputDevice(_ id: AudioDeviceID) {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var mutableID = id
    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID)
}

func getDeviceName(for id: AudioObjectID) -> String? {
    let devices = getInputDevices()
    return devices.first { $0.id == id }?.name
}
