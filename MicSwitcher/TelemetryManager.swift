//
//  TelemetryManager.swift
//  MicSwitcher
//
//  Handles privacy-focused telemetry with OpenTelemetry support
//

import Foundation
import CryptoKit
import IOKit
import os.log

// Telemetry metric types
enum TelemetryMetric: String, CaseIterable {
    // Counter metrics (always increasing)
    case appLaunches = "app_launches_total"
    case appTerminations = "app_terminations_total"
    case microphoneSwitches = "microphone_switches_total"
    case microphoneSwitchesAuto = "microphone_switches_auto_total"
    case microphoneSwitchesManual = "microphone_switches_manual_total"
    case settingsOpened = "settings_opened_total"
    case priorityChanges = "priority_changes_total"
    case deviceHistoryClears = "device_history_clears_total"
    
    // Gauge metrics (can go up and down)
    case connectedDevices = "connected_devices"
    case historyDevices = "history_devices"
    
    var displayName: String {
        switch self {
        case .appLaunches: return "App Launches"
        case .appTerminations: return "App Terminations"
        case .microphoneSwitches: return "Total Microphone Switches"
        case .microphoneSwitchesAuto: return "Auto Switches"
        case .microphoneSwitchesManual: return "Manual Switches"
        case .settingsOpened: return "Settings Opened"
        case .priorityChanges: return "Priority Order Changes"
        case .deviceHistoryClears: return "Device History Clears"
        case .connectedDevices: return "Connected Devices"
        case .historyDevices: return "Devices in History"
        }
    }
    
    var isCounter: Bool {
        switch self {
        case .connectedDevices, .historyDevices:
            return false
        default:
            return true
        }
    }
}

// Telemetry settings
struct TelemetrySettings: Codable {
    var enabled: Bool = false
    var endpoint: String = "http://localhost:4318"
    var enabledMetrics: Set<String> = Set(TelemetryMetric.allCases.map { $0.rawValue })
    
    static func load() -> TelemetrySettings {
        if let data = UserDefaults.standard.data(forKey: "TelemetrySettings"),
           var settings = try? JSONDecoder().decode(TelemetrySettings.self, from: data) {
            // Migrate from events to metrics if needed
            if settings.enabledMetrics.isEmpty && !settings.enabledEvents.isEmpty {
                settings.enabledMetrics = Set(TelemetryMetric.allCases.map { $0.rawValue })
            }
            return settings
        }
        return TelemetrySettings()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "TelemetrySettings")
        }
    }
    
    // For migration compatibility
    private var enabledEvents: Set<String> = []
}

class TelemetryManager: ObservableObject {
    static let shared = TelemetryManager()
    private static let logger = Logger(subsystem: "dev.matthiasgoetzke.MicSwitcher", category: "Telemetry")
    
    @Published var settings = TelemetrySettings.load() {
        didSet {
            settings.save()
        }
    }
    
    private let deviceHash: String
    private let sessionId = UUID().uuidString
    
    // Metric counters - persisted across app launches
    private var counters: [String: Int64] = [:]
    private let countersKey = "TelemetryCounters"
    
    // Current gauge values
    private var gauges: [String: Double] = [:]
    
    private init() {
        // Create a stable, anonymous device hash
        if let hardwareUUID = TelemetryManager.getHardwareUUID() {
            let hash = SHA256.hash(data: hardwareUUID.data(using: .utf8)!)
            self.deviceHash = String(hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16))
        } else {
            self.deviceHash = "unknown"
        }
        
        // Load persisted counters
        if let data = UserDefaults.standard.data(forKey: countersKey),
           let loaded = try? JSONDecoder().decode([String: Int64].self, from: data) {
            counters = loaded
        }
    }
    
    private func saveCounters() {
        if let data = try? JSONEncoder().encode(counters) {
            UserDefaults.standard.set(data, forKey: countersKey)
        }
    }
    
    private static func getHardwareUUID() -> String? {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        defer { IOObjectRelease(service) }
        
        if let cfString = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return cfString
        }
        return nil
    }
    
    func incrementCounter(_ metric: TelemetryMetric, by value: Int64 = 1) {
        guard metric.isCounter else { 
            TelemetryManager.logger.error("Attempted to increment non-counter metric: \(metric.rawValue)")
            return 
        }
        
        TelemetryManager.logger.info("Incrementing counter '\(metric.rawValue)' by \(value)")
        
        counters[metric.rawValue, default: 0] += value
        saveCounters()
        
        if settings.enabled && settings.enabledMetrics.contains(metric.rawValue) {
            sendMetrics()
        }
    }
    
    func setGauge(_ metric: TelemetryMetric, value: Double) {
        guard !metric.isCounter else { 
            TelemetryManager.logger.error("Attempted to set gauge on counter metric: \(metric.rawValue)")
            return 
        }
        
        TelemetryManager.logger.info("Setting gauge '\(metric.rawValue)' to \(value)")
        
        gauges[metric.rawValue] = value
        
        if settings.enabled && settings.enabledMetrics.contains(metric.rawValue) {
            sendMetrics()
        }
    }
    
    private func sendMetrics() {
        let timestamp = Date()
        let timestampNanos = String(Int64(timestamp.timeIntervalSince1970 * 1_000_000_000))
        
        var dataPoints: [[String: Any]] = []
        
        // Add counter metrics
        for (name, value) in counters {
            guard settings.enabledMetrics.contains(name) else { continue }
            dataPoints.append([
                "name": name,
                "sum": [
                    "dataPoints": [[
                        "asInt": String(value),
                        "timeUnixNano": timestampNanos,
                        "attributes": []
                    ]],
                    "aggregationTemporality": 2, // CUMULATIVE
                    "isMonotonic": true
                ]
            ])
        }
        
        // Add gauge metrics
        for (name, value) in gauges {
            guard settings.enabledMetrics.contains(name) else { continue }
            dataPoints.append([
                "name": name,
                "gauge": [
                    "dataPoints": [[
                        "asDouble": value,
                        "timeUnixNano": timestampNanos,
                        "attributes": []
                    ]]
                ]
            ])
        }
        
        guard !dataPoints.isEmpty else { return }
        
        // Create OTLP metrics payload
        let payload: [String: Any] = [
            "resourceMetrics": [[
                "resource": [
                    "attributes": [
                        ["key": "service.name", "value": ["stringValue": "MicSwitcher"]],
                        ["key": "service.version", "value": ["stringValue": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"]],
                        ["key": "device.id", "value": ["stringValue": deviceHash]]
                    ]
                ],
                "scopeMetrics": [[
                    "scope": ["name": "micswitcher.metrics"],
                    "metrics": dataPoints
                ]]
            ]]
        ]
        
        // Check if endpoint has a path or just host:port
        let urlString: String
        if let url = URL(string: settings.endpoint), url.path.isEmpty || url.path == "/" {
            // No path specified, append /v1/metrics
            urlString = settings.endpoint.trimmingCharacters(in: .init(charactersIn: "/")) + "/v1/metrics"
            TelemetryManager.logger.debug("Endpoint has no path, using: \(urlString)")
        } else {
            // Use as-is, user specified a full path
            urlString = settings.endpoint
        }
        
        guard let url = URL(string: urlString) else { 
            TelemetryManager.logger.error("Invalid URL: \(urlString)")
            return 
        }
        
        TelemetryManager.logger.debug("Sending to URL: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            request.httpBody = jsonData
            
            // Debug: log the JSON payload
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                TelemetryManager.logger.debug("Payload preview (first 500 chars): \(String(jsonString.prefix(500)))")
            }
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    TelemetryManager.logger.error("Send error: \(error)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    TelemetryManager.logger.info("Response status: \(httpResponse.statusCode)")
                    if httpResponse.statusCode != 200 {
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            TelemetryManager.logger.error("Response body: \(responseString)")
                        }
                    } else {
                        TelemetryManager.logger.info("Successfully sent metrics")
                    }
                }
            }.resume()
        } catch {
            TelemetryManager.logger.error("Serialization error: \(error)")
        }
    }
}

