import Foundation
import Darwin

@main
struct SmokeTests {
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
            print("PASS: \(message)")
        }
        check(Format.delta(200, 100, seconds: 2) == 50, "Counter delta uses elapsed time")
        check(Format.delta(10, 100, seconds: 1) == 0, "Counter resets never create negative rates")
        check(Format.delta(200, 100, seconds: 60) == 0, "Sleep gaps never create misleading rates")
        check(Format.delta(200, 100, seconds: 0) == 0, "First sample has no rate")
        let queue = DispatchQueue(label: "lumen.test")
        let collector = Collector(queue: queue)
        _ = queue.sync { collector.sample(interface: "auto") }
        Thread.sleep(forTimeInterval: 1.2)
        let s = queue.sync { collector.sample(interface: "auto") }
        check(s.cores.count == ProcessInfo.processInfo.processorCount, "Every logical CPU is sampled")
        check(s.cores.allSatisfy { $0.total >= 0 && $0.total <= 1 }, "CPU fractions remain bounded")
        check(s.memory.total == Double(ProcessInfo.processInfo.physicalMemory), "Memory total matches hardware")
        check(s.memory.used > 0 && s.memory.used <= s.memory.total, "Memory usage is plausible")
        check(s.download >= 0 && s.upload >= 0, "Network rates are nonnegative")
        check(!s.volumes.isEmpty && s.volumes.allSatisfy { $0.total > 0 && $0.free >= 0 && $0.fraction <= 1 }, "Mounted volume capacities are valid")
        check(!s.processes.isEmpty, "Accessible process counters are returned")
        check(s.processes.allSatisfy { $0.cpu >= 0 && $0.memory >= 0 }, "Process readings are nonnegative")
        check(["Nominal", "Fair", "Serious", "Critical", "Unknown"].contains(s.thermal), "Thermal state is explicit")
        if let temp = s.chipTemperature { check(temp.isFinite && (10...120).contains(temp), "Chip temperature is within the accepted range"); print("INFO: Chip sensor peak \(temp) °C") }
        else { print("INFO: No recognised chip temperature; unavailable state used") }
        if let b = s.battery { check(b.charge >= 0 && b.charge <= 1, "Battery charge is bounded") }
        else { print("INFO: No internal battery reported; unavailable state used") }
        let load = Process()
        load.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        load.standardOutput = FileHandle.nullDevice
        try load.run()
        defer { if load.isRunning { load.terminate() } }
        Thread.sleep(forTimeInterval: 5.2)
        let busy = queue.sync { collector.sample(interface: "auto") }
        if let child = busy.processes.first(where: { $0.id == load.processIdentifier }) {
            // First observation establishes a baseline; sample a second interval below.
            check(child.memory > 0, "New process resident memory is visible")
        }
        Thread.sleep(forTimeInterval: 5.2)
        let busyAgain = queue.sync { collector.sample(interface: "auto") }
        check(busyAgain.processes.contains { $0.id == load.processIdentifier && $0.cpu > 20 }, "Process CPU detects a controlled busy process")
        let changed = queue.sync { collector.sample(interface: "lumen-nonexistent") }
        check(changed.received == 0 && changed.sent == 0 && changed.download == 0, "Interface change resets totals and excludes unrelated traffic")
        print("LIVE: CPU \(Format.percent(s.cpu)), RAM \(Format.bytes(s.memory.used)), \(s.interfaces.count) interfaces, \(s.volumes.count) volumes, \(s.processes.count) accessible processes, pressure \(s.memory.pressure)")
    }
}
