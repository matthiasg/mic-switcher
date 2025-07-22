//
//  MicSwitcherApp.swift
//  MicSwitcher
//
//  Created by Matthias Götzke on 16.07.25.
//

import SwiftUI
import CoreAudio
import UserNotifications
import AppKit  // For NSSound and NSHostingController
import os.log

// Device info for UI
struct DeviceInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    var lastSeen: Date
    
    static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
        return lhs.name == rhs.name
    }
}

// Device info for persistence
struct DeviceHistoryItem: Codable {
    let name: String
    var lastSeen: Date
}

// Singleton for app state to avoid StateObject issues
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentDefaultID: AudioObjectID
    @Published var availableDevices: [(id: AudioDeviceID, name: String)] = []
    @Published var menuID = UUID() // Force menu refresh
    @Published var deviceHistory: [DeviceInfo] = [] // All devices ever seen, in priority order
    @Published var draggedDevice: DeviceInfo?
    @Published var autoSwitchEnabled: Bool = UserDefaults.standard.bool(forKey: "AutoSwitchEnabled") {
        didSet {
            UserDefaults.standard.set(autoSwitchEnabled, forKey: "AutoSwitchEnabled")
        }
    }
    var previousDevices: Set<AudioDeviceID>
    private var audioMonitor: AudioMonitor?
    
    private init() {
        currentDefaultID = getDefaultInputDevice()
        let devices = getInputDevices()
        availableDevices = devices
        previousDevices = Set(devices.map { $0.id })
        loadDeviceHistory()
        setupAudioMonitor()
        
        // Defer device history update to avoid initialization issues
        DispatchQueue.main.async { [weak self] in
            self?.updateDeviceHistoryWithCurrentDevices()
            
            // Update telemetry gauges
            TelemetryManager.shared.setGauge(.connectedDevices, value: Double(self?.availableDevices.count ?? 0))
            TelemetryManager.shared.setGauge(.historyDevices, value: Double(self?.deviceHistory.count ?? 0))
            
            // Auto-switch on startup if enabled
            if self?.autoSwitchEnabled == true {
                self?.performAutoSwitch()
            }
        }
    }
    
    private func loadDeviceHistory() {
        guard let data = UserDefaults.standard.data(forKey: "DeviceHistory") else { return }
        
        do {
            let items = try JSONDecoder().decode([DeviceHistoryItem].self, from: data)
            deviceHistory = items.map { DeviceInfo(name: $0.name, lastSeen: $0.lastSeen) }
        } catch {
            print("Failed to decode device history: \(error)")
            // Clear corrupted data
            UserDefaults.standard.removeObject(forKey: "DeviceHistory")
        }
    }
    
    func saveDeviceHistory() {
        let items = deviceHistory.map { DeviceHistoryItem(name: $0.name, lastSeen: $0.lastSeen) }
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: "DeviceHistory")
            // Update telemetry gauge
            TelemetryManager.shared.setGauge(.historyDevices, value: Double(deviceHistory.count))
        } catch {
            print("Failed to encode device history: \(error)")
        }
    }
    
    func clearDeviceHistory() {
        deviceHistory = []
        saveDeviceHistory()
        // Re-add currently connected devices
        updateDeviceHistoryWithCurrentDevices()
        // Track the clear event
        TelemetryManager.shared.incrementCounter(.deviceHistoryClears)
    }
    
    private func updateDeviceHistoryWithCurrentDevices() {
        let currentDeviceNames = Set(availableDevices.map { $0.name })
        
        // Update last seen for existing devices
        for i in 0..<deviceHistory.count {
            if currentDeviceNames.contains(deviceHistory[i].name) {
                deviceHistory[i].lastSeen = Date()
            }
        }
        
        // Add new devices to history
        for device in availableDevices {
            if !deviceHistory.contains(where: { $0.name == device.name }) && 
               !device.name.lowercased().contains("iphone") {
                deviceHistory.append(DeviceInfo(name: device.name, lastSeen: Date()))
            }
        }
        
        saveDeviceHistory()
    }
    
    private func setupAudioMonitor() {
        audioMonitor = AudioMonitor(
            onDefaultChange: { [weak self] in
                guard let self = self else { return }
                self.currentDefaultID = getDefaultInputDevice()
                self.sendNotification(message: "Microphone switched to \(getDeviceName(for: self.currentDefaultID) ?? "Unknown")")
            },
            onDevicesChange: { [weak self] in
                guard let self = self else { return }
                let newDevices = getInputDevices()
                let newIDs = Set(newDevices.map { $0.id })
                let removed = self.previousDevices.subtracting(newIDs)
                let added = newIDs.subtracting(self.previousDevices)
                
                for id in removed {
                    let deviceName = getDeviceName(for: id) ?? "Unknown"
                    self.sendNotification(message: "Microphone no longer available: \(deviceName)")
                    // Update gauge for connected devices
                    TelemetryManager.shared.setGauge(.connectedDevices, value: Double(newDevices.count))
                }
                for id in added {
                    let deviceName = getDeviceName(for: id) ?? "Unknown"
                    self.sendNotification(message: "New microphone detected: \(deviceName)")
                    // Update gauge for connected devices
                    TelemetryManager.shared.setGauge(.connectedDevices, value: Double(newDevices.count))
                    
                    // Auto-switch if this is a preferred device and auto-switch is enabled
                    if self.autoSwitchEnabled && self.shouldAutoSwitch(to: deviceName, currentDevices: newDevices) {
                        setDefaultInputDevice(id)
                        self.currentDefaultID = id
                        self.sendNotification(message: "Auto-switched to preferred microphone: \(deviceName)")
                        TelemetryManager.shared.incrementCounter(.microphoneSwitchesAuto)
                        TelemetryManager.shared.incrementCounter(.microphoneSwitches)
                    }
                }
                
                self.previousDevices = newIDs
                self.updateDevices() // Update the published device list
                
                // Check if default needs update (e.g., if current default was removed)
                let current = getDefaultInputDevice()
                if !newIDs.contains(current) && self.autoSwitchEnabled {
                    // Try to switch to the best available preferred device
                    if let bestDevice = self.findBestDevice(from: newDevices) {
                        setDefaultInputDevice(bestDevice.id)
                        self.currentDefaultID = bestDevice.id
                        self.sendNotification(message: "Switched to fallback microphone: \(bestDevice.name)")
                    }
                }
            }
        )
    }
    
    func updateDevices() {
        availableDevices = getInputDevices()
        updateDeviceHistoryWithCurrentDevices()
        menuID = UUID() // Force menu refresh
    }
    
    func shouldAutoSwitch(to deviceName: String, currentDevices: [(id: AudioDeviceID, name: String)]) -> Bool {
        // Find indices in device history (priority order)
        guard let newDeviceIndex = deviceHistory.firstIndex(where: { $0.name == deviceName }) else { return false }
        
        // Get current device name
        let currentDeviceName = getDeviceName(for: currentDefaultID) ?? ""
        
        // If current device is also in history, only switch if new device has higher priority (lower index)
        if let currentIndex = deviceHistory.firstIndex(where: { $0.name == currentDeviceName }) {
            return newDeviceIndex < currentIndex
        }
        
        // If current device is not in history, always switch to a device in history
        return true
    }
    
    func findBestDevice(from devices: [(id: AudioDeviceID, name: String)]) -> (id: AudioDeviceID, name: String)? {
        // Find the highest priority device that's currently available
        for historyDevice in deviceHistory {
            if let device = devices.first(where: { $0.name == historyDevice.name }) {
                return device
            }
        }
        // If no device from history is available, return first non-iPhone device
        return devices.first { !$0.name.lowercased().contains("iphone") }
    }
    
    func performAutoSwitch() {
        guard autoSwitchEnabled else { return }
        
        if let bestDevice = findBestDevice(from: availableDevices) {
            if bestDevice.id != currentDefaultID {
                setDefaultInputDevice(bestDevice.id)
                TelemetryManager.shared.incrementCounter(.microphoneSwitchesAuto)
                TelemetryManager.shared.incrementCounter(.microphoneSwitches)
            }
        }
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
    @StateObject private var appState = AppState.shared
    private static let logger = Logger(subsystem: "dev.matthiasgoetzke.MicSwitcher", category: "Main")
    
    init() {
        setupNotifications()
        
        // Debug telemetry settings
        MicSwitcherApp.logger.info("App started")
        MicSwitcherApp.logger.info("About to call TelemetryManager.shared.logEvent(.appLaunched)")
        
        TelemetryManager.shared.incrementCounter(.appLaunches)
        
        MicSwitcherApp.logger.info("Called TelemetryManager.shared.logEvent(.appLaunched)")
        
        // Add app termination observer
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            TelemetryManager.shared.incrementCounter(.appTerminations)
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            MicMenuContent()
                .id(appState.menuID) // Force refresh when menuID changes
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
        let availableDeviceNames = Set(state.availableDevices.filter { !$0.name.lowercased().contains("iphone") }.map { $0.name })
        
        // Show all devices from history in order
        ForEach(Array(state.deviceHistory.enumerated()), id: \.element.id) { index, historyDevice in
            let isConnected = availableDeviceNames.contains(historyDevice.name)
            let connectedDevice = state.availableDevices.first { $0.name == historyDevice.name }
            let isCurrent = connectedDevice?.id == state.currentDefaultID
            
            Button(action: {
                if let device = connectedDevice {
                    setDefaultInputDevice(device.id)
                    state.currentDefaultID = device.id
                    state.sendNotification(message: "Manually switched to \(device.name)")
                    TelemetryManager.shared.incrementCounter(.microphoneSwitchesManual)
                    TelemetryManager.shared.incrementCounter(.microphoneSwitches)
                }
            }) {
                HStack {
                    Text("\(index + 1). \(historyDevice.name)")
                        .foregroundColor(isConnected ? .primary : .secondary)
                    if isCurrent {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
            .disabled(!isConnected)
        }
        
        Divider()
        
        Toggle("Auto-Switch To Best Available", isOn: $state.autoSwitchEnabled)
            .toggleStyle(.checkbox)
        
        Button("Settings...") {
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
        
    
        Divider()
        
        Button("About MicSwitcher") {
            openAbout()
        }
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
    
    func openAbout() {
        DispatchQueue.main.async {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "About MicSwitcher"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 550, height: 580))
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.level = .floating
            
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
        }
    }
    
    func openSettings() {
        TelemetryManager.shared.incrementCounter(.settingsOpened)
        DispatchQueue.main.async {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "MicSwitcher Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 700, height: 450))
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.level = .floating
            
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
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
