//
//  SettingsView.swift
//  MicSwitcher
//
//  Settings window for managing microphone preferences
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var telemetry = TelemetryManager.shared
    @State private var selectedDevice: DeviceInfo?
    @State private var showingAdvanced = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Microphone Preferences")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Device list
                VStack(alignment: .leading, spacing: 8) {
                    Text("Device Priority Order")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    Text("Drag devices to reorder. Higher = higher priority.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(state.deviceHistory.enumerated()), id: \.element.id) { index, device in
                                let connected = isDeviceConnected(device)
                                let current = connected && state.availableDevices.first { $0.id == state.currentDefaultID }?.name == device.name
                                
                                DeviceRow(device: device, index: index, isConnected: connected, isCurrent: current)
                                    .onDrag {
                                        state.draggedDevice = device
                                        return NSItemProvider(object: device.name as NSString)
                                    }
                                    .onDrop(of: [UTType.text], delegate: DropViewDelegate(device: device, devices: $state.deviceHistory, draggedDevice: $state.draggedDevice))
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(minWidth: 300)
                
                Divider()
                
                // Info panel
                VStack(alignment: .leading, spacing: 12) {
                    Text("Info")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("• Devices at the top have higher priority")
                        .font(.caption)
                    Text("• When a device connects, it will auto-switch if it has higher priority than the current device")
                        .font(.caption)
                    Text("• Connected devices show in green")
                        .font(.caption)
                    Text("• Disconnected devices show in gray")
                        .font(.caption)
                    
                    Spacer()
                    
                    HStack {
                        Button("Clear History") {
                            state.clearDeviceHistory()
                            // Telemetry is already tracked in clearDeviceHistory()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Advanced Settings...") {
                            openAdvancedSettings()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Done") {
                            if let window = NSApp.keyWindow {
                                window.close()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(minWidth: 300)
                .padding()
            }
        }
        .frame(width: 700, height: 450)
    }
    
    func isDeviceConnected(_ device: DeviceInfo) -> Bool {
        return state.availableDevices.contains { $0.name == device.name }
    }
    
    func openAdvancedSettings() {
        DispatchQueue.main.async {
            let advancedView = AdvancedSettingsView()
            let hostingController = NSHostingController(rootView: advancedView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Advanced Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 500, height: 500))
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.level = .floating
            
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
        }
    }
}

struct DeviceRow: View {
    let device: DeviceInfo
    let index: Int
    let isConnected: Bool
    let isCurrent: Bool
    
    var body: some View {
        HStack {
            Text("\(index + 1).")
                .font(.system(.body, design: .monospaced))
                .frame(width: 30)
                .foregroundColor(.secondary)
            
            Image(systemName: isConnected ? "circle.fill" : "circle")
                .foregroundColor(isConnected ? .green : .gray)
                .font(.caption)
            
            Text(device.name)
                .foregroundColor(isConnected ? .primary : .secondary)
            
            Spacer()
            
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
}

struct DropViewDelegate: DropDelegate {
    let device: DeviceInfo
    @Binding var devices: [DeviceInfo]
    @Binding var draggedDevice: DeviceInfo?
    
    func performDrop(info: DropInfo) -> Bool {
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedDevice = draggedDevice else { return }
        
        if draggedDevice != device {
            let from = devices.firstIndex(of: draggedDevice)!
            let to = devices.firstIndex(of: device)!
            
            withAnimation(.default) {
                devices.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            
            AppState.shared.saveDeviceHistory()
            TelemetryManager.shared.incrementCounter(.priorityChanges)
        }
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject private var telemetry = TelemetryManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Fixed header
            Text("Advanced Settings")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .padding(.top, 30)
                .padding(.bottom, 20)
            
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Telemetry Settings")
                        .font(.headline)
                    
                    Toggle("Enable Anonymous Telemetry", isOn: $telemetry.settings.enabled)
                    
                    if telemetry.settings.enabled {
                        VStack(alignment: .leading, spacing: 12) {
                        Text("OpenTelemetry Collector Endpoint:")
                            .font(.subheadline)
                        
                        HStack {
                            TextField("Endpoint URL", text: Binding(
                                get: { telemetry.settings.endpoint },
                                set: { telemetry.settings.endpoint = $0 }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button("Reset") {
                                telemetry.settings.endpoint = "http://localhost:4318"
                            }
                        }
                        
                        Text("If no path is specified, /v1/metrics will be appended automatically")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Metrics to Track:")
                            .font(.subheadline)
                            .padding(.top, 8)
                        
                        // Multi-column layout for events
                        let columns = [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ]
                        
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(TelemetryMetric.allCases, id: \.rawValue) { metric in
                                Toggle(isOn: Binding(
                                    get: { telemetry.settings.enabledMetrics.contains(metric.rawValue) },
                                    set: { enabled in
                                        if enabled {
                                            telemetry.settings.enabledMetrics.insert(metric.rawValue)
                                        } else {
                                            telemetry.settings.enabledMetrics.remove(metric.rawValue)
                                        }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(metric.displayName)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(metric.isCounter ? "Counter" : "Gauge")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .help(metric.rawValue) // Tooltip showing the raw metric name
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(6)
                        
                        Text("Note: All data is anonymized. No personal information is collected.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                            Text("Telemetry is fire-and-forget. Events are sent immediately without retries. Best used with a local OpenTelemetry collector.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
            }
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 30)
        }
        .frame(width: 500, height: 500)
    }
}