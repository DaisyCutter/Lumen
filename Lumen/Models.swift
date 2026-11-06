import Foundation

// All percentages are fractions in 0...1; all storage and network counters are bytes.
enum Metric: String, CaseIterable, Identifiable {
    case overview, cpu, memory, network, disk, battery, sensors
    var id: String { rawValue }
    var title: String { self == .cpu ? "CPU" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .overview: "waveform.path.ecg"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .sensors: "thermometer.medium"
        }
    }
}
struct CoreLoad: Identifiable {
    let id: Int
    let user: Double
    let system: Double
    var total: Double { user + system }
}
struct MemoryReading {
    var total: Double = 0, app: Double = 0, wired: Double = 0, compressed: Double = 0
    var cached: Double = 0, free: Double = 0, swap: Double = 0
    var pressure = "Unknown"
    var used: Double { app + wired + compressed }
    var fraction: Double { total > 0 ? used / total : 0 }
}
struct InterfaceReading: Identifiable {
    var id: String
    var received: UInt64
    var sent: UInt64
    var download: Double = 0
    var upload: Double = 0
    var active: Bool
}
struct VolumeReading: Identifiable {
    var id: String
    var name: String
    var total: Double
    var free: Double
    var reclaimable: Double?
    var format: String
    var internalDrive: Bool
    var fraction: Double { total > 0 ? max(0, min(1, (total - free) / total)) : 0 }
}
struct BatteryReading {
    var charge: Double
    var status: String
    var time: String
    var health: String
    var condition: String
    var design: Double?
    var nominal: Double?
}
struct ProcessReading: Identifiable {
    var id: Int32
    var name: String
    var cpu: Double
    var memory: Double
}
struct Sample: Identifiable {
    var id = UUID()
    var date = Date()
    var cpu: Double
    var memory: Double
    var download: Double
    var upload: Double
    var battery: Double?
}
struct Snapshot {
    var date = Date()
    var cores: [CoreLoad] = []
    var memory = MemoryReading()
    var interfaces: [InterfaceReading] = []
    var volumes: [VolumeReading] = []
    var battery: BatteryReading?
    var processes: [ProcessReading] = []
    var download: Double = 0, upload: Double = 0
    var received: Double = 0, sent: Double = 0
    var thermal = "Unknown"
    var chipTemperature: Double?
    var errors: [String] = []
    var cpu: Double { cores.isEmpty ? 0 : cores.reduce(0) { $0 + $1.total } / Double(cores.count) }
    var user: Double { cores.isEmpty ? 0 : cores.reduce(0) { $0 + $1.user } / Double(cores.count) }
    var system: Double { cores.isEmpty ? 0 : cores.reduce(0) { $0 + $1.system } / Double(cores.count) }
}
enum Format {
    static func percent(_ value: Double) -> String { "\(Int((max(0, min(1, value)) * 100).rounded()))%" }
    static func bytes(_ value: Double) -> String {
        value < 1 ? "0 B" : ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .binary)
    }
    static func rate(_ value: Double) -> String { bytes(value) + "/s" }
    static func delta(_ new: UInt64, _ old: UInt64, seconds: Double) -> Double {
        guard seconds > 0, seconds < 30, new >= old else { return 0 }
        return Double(new - old) / seconds
    }
}
