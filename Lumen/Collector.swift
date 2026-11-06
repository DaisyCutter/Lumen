import Foundation
import Darwin
import IOKit.ps

// Owned exclusively by Monitor's serial sampling queue.
final class Collector {
    private var previousCPU: [[UInt32]] = []
    private var previousInterfaces: [String: InterfaceReading] = [:]
    private var previousTime: TimeInterval?
    private var previousProcesses: [Int32: (UInt64, UInt64)] = [:]
    private var processTime: TimeInterval?
    private var processes: [ProcessReading] = []
    private var volumes: [VolumeReading] = []
    private var slowTime: TimeInterval = 0
    private var chipTemperature: Double?
    private var received = 0.0, sent = 0.0
    private var networkSelection = "auto"
    private var pressure = "Unknown"
    private var pressureSource: DispatchSourceMemoryPressure?

    init(queue: DispatchQueue) {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let flags = source?.data else { return }
            self?.pressure = flags.contains(.critical) ? "Critical" : flags.contains(.warning) ? "Warning" : "Normal"
        }
        source.resume()
        pressureSource = source
    }
    deinit { pressureSource?.cancel() }

    func sample(interface: String) -> Snapshot {
        var s = Snapshot()
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { now - $0 } ?? 0
        s.cores = cpu()
        if s.cores.isEmpty { s.errors.append("CPU counters unavailable") }
        s.memory = memory()
        if s.memory.total == 0 { s.errors.append("Memory counters unavailable") }
        var interfaces = network()
        let changed = interface != networkSelection
        if changed { received = 0; sent = 0; networkSelection = interface }
        for i in interfaces.indices {
            if let old = previousInterfaces[interfaces[i].id] {
                interfaces[i].download = Format.delta(interfaces[i].received, old.received, seconds: elapsed)
                interfaces[i].upload = Format.delta(interfaces[i].sent, old.sent, seconds: elapsed)
            }
        }
        // Default counts physical en* links only: no VPN/bridge/loopback double counting.
        let chosen = interfaces.filter { interface == "auto" ? $0.id.hasPrefix("en") : $0.id == interface }
        s.download = chosen.reduce(0) { $0 + $1.download }
        s.upload = chosen.reduce(0) { $0 + $1.upload }
        if !changed && elapsed > 0 && elapsed < 30 {
            received += s.download * elapsed; sent += s.upload * elapsed
        }
        s.received = received; s.sent = sent
        s.interfaces = interfaces
        previousInterfaces = Dictionary(uniqueKeysWithValues: interfaces.map { ($0.id, $0) })
        previousTime = now
        if now - slowTime >= 5 {
            volumes = disks(); processes = readProcesses(now: now); chipTemperature = ChipTemperature.read(); slowTime = now
        }
        s.volumes = volumes; s.processes = processes; s.battery = battery(); s.chipTemperature = chipTemperature
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: s.thermal = "Nominal"
        case .fair: s.thermal = "Fair"
        case .serious: s.thermal = "Serious"
        case .critical: s.thermal = "Critical"
        @unknown default: s.thermal = "Unknown"
        }
        return s
    }
    private func cpu() -> [CoreLoad] {
        var count: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        var cores: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count) == KERN_SUCCESS,
              let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var result: [CoreLoad] = [], current: [[UInt32]] = []
        for core in 0..<Int(cores) {
            let ticks = (0..<Int(CPU_STATE_MAX)).map { UInt32(bitPattern: info[core * Int(CPU_STATE_MAX) + $0]) }
            current.append(ticks)
            guard core < previousCPU.count else { continue }
            let d = zip(ticks, previousCPU[core]).map { Double($0 &- $1) }
            let total = d.reduce(0, +)
            result.append(CoreLoad(id: core, user: total > 0 ? (d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_NICE)]) / total : 0,
                                   system: total > 0 ? d[Int(CPU_STATE_SYSTEM)] / total : 0))
        }
        previousCPU = current
        return result
    }
    private func memory() -> MemoryReading {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemoryReading() }
        let page = Double(vm_kernel_page_size)
        var m = MemoryReading()
        m.total = Double(ProcessInfo.processInfo.physicalMemory)
        m.wired = Double(vm.wire_count) * page
        m.compressed = Double(vm.compressor_page_count) * page
        m.app = max(0, Double(vm.active_count + vm.inactive_count) * page - Double(vm.purgeable_count + vm.external_page_count) * page)
        m.cached = Double(vm.external_page_count + vm.purgeable_count) * page
        m.free = max(0, m.total - m.used - m.cached)
        // Initial system pressure level; event source tracks subsequent transitions.
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            m.pressure = level == 4 ? "Critical" : level == 2 ? "Warning" : level == 1 ? "Normal" : pressure
        } else { m.pressure = pressure }
        var swap = xsw_usage(); size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { m.swap = Double(swap.xsu_used) }
        return m
    }
    private func network() -> [InterfaceReading] {
        // NET_RT_IFLIST2 provides 64-bit interface byte counters (if_data is only 32-bit).
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        let ok = buffer.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) }
        guard ok == 0 else { return [] }
        return buffer.withUnsafeBytes { bytes in
            var offset = 0
            var readings: [InterfaceReading] = []
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let length = Int(header.ifm_msglen)
                guard length > 0, offset + length <= size else { break }
                if header.ifm_type == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size {
                    let item = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(item.ifm_index), &name) != nil {
                        let id = String(cString: name)
                        if !id.hasPrefix("lo") {
                            readings.append(InterfaceReading(id: id, received: item.ifm_data.ifi_ibytes,
                                sent: item.ifm_data.ifi_obytes, active: item.ifm_flags & IFF_UP != 0))
                        }
                    }
                }
                offset += length
            }
            return readings.sorted { $0.id < $1.id }
        }
    }
    private func disks() -> [VolumeReading] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeLocalizedFormatDescriptionKey]
        var urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        if !urls.contains(where: { $0.path == "/" }) { urls.insert(URL(fileURLWithPath: "/"), at: 0) }
        return urls.compactMap { url in
            // Foundation metadata can be absent in restricted sessions. statfs is a public fallback.
            let v = try? url.resourceValues(forKeys: keys)
            var fs = statfs()
            guard statfs(url.path, &fs) == 0 else { return nil }
            let total = Double(fs.f_blocks) * Double(fs.f_bsize)
            let free = min(total, Double(fs.f_bavail) * Double(fs.f_bsize))
            guard total > 0 else { return nil }
            let reclaim = v?.volumeAvailableCapacityForImportantUsage.map { min(total - free, max(0, Double($0) - free)) }
            let format = withUnsafePointer(to: &fs.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
            }
            return VolumeReading(id: url.path, name: v?.volumeName ?? (url.path == "/" ? "Startup volume" : url.lastPathComponent), total: total, free: free,
                reclaimable: reclaim, format: v?.volumeLocalizedFormatDescription ?? format,
                internalDrive: v?.volumeIsInternal ?? (url.path == "/"))
        }.sorted { $0.id < $1.id }
    }
    private func nonempty(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Unavailable" }
        return value
    }
    private func battery() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Double,
                  let max = d[kIOPSMaxCapacityKey] as? Double, max > 0 else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let ac = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = d[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int ?? -1
            return BatteryReading(charge: current / max, status: charging ? "Charging" : ac ? "Connected to power" : "On battery",
                time: minutes > 0 ? "\(minutes / 60)h \(minutes % 60)m \(charging ? "until full" : "remaining")" : "Calculating / unavailable",
                health: nonempty(d[kIOPSBatteryHealthKey] as? String),
                condition: nonempty(d[kIOPSBatteryHealthConditionKey] as? String),
                design: d[kIOPSDesignCapacityKey] as? Double, nominal: d[kIOPSNominalCapacityKey] as? Double)
        }
        return nil
    }
    private func readProcesses(now: TimeInterval) -> [ProcessReading] {
        let capacity = max(4096, Int(proc_listallpids(nil, 0)) + 256)
        var pids = [pid_t](repeating: 0, count: capacity)
        let n = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard n > 0 else { return [] }
        let dt = processTime.map { now - $0 } ?? 0
        var current: [Int32: (UInt64, UInt64)] = [:]
        var readings: [ProcessReading] = []
        for pid in pids.prefix(min(Int(n), capacity)) where pid > 0 {
            var task = proc_taskinfo()
            let bytes = withUnsafeMutablePointer(to: &task) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(MemoryLayout<proc_taskinfo>.size))
            }
            guard bytes == MemoryLayout<proc_taskinfo>.size else { continue }
            let ticks = task.pti_total_user + task.pti_total_system
            // Process start time disambiguates reused PIDs.
            var bsd = proc_bsdinfo()
            let bsdBytes = withUnsafeMutablePointer(to: &bsd) {
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
            }
            guard bsdBytes == MemoryLayout<proc_bsdinfo>.size else { continue }
            let start = bsd.pbi_start_tvsec &* 1_000_000 &+ bsd.pbi_start_tvusec
            current[pid] = (ticks, start)
            let old = previousProcesses[pid]
            // PROC_PIDTASKINFO times are Mach absolute ticks, not nanoseconds on Apple Silicon.
            var timebase = mach_timebase_info_data_t()
            mach_timebase_info(&timebase)
            let nanosPerTick = Double(timebase.numer) / Double(timebase.denom)
            let cpu = old?.1 == start ? Format.delta(ticks, old!.0, seconds: dt) * nanosPerTick / 1_000_000_000 * 100 : 0
            var name = [CChar](repeating: 0, count: 1024)
            let length = proc_name(pid, &name, UInt32(name.count))
            readings.append(ProcessReading(id: pid, name: length > 0 ? String(cString: name) : "PID \(pid)", cpu: cpu, memory: Double(task.pti_resident_size)))
        }
        previousProcesses = current; processTime = now
        return readings
    }
}

// Optional, read-only Apple Silicon sensor discovery. These symbols are private and
// may disappear; absent symbols, services or invalid values all yield nil.
private enum ChipTemperature {
    typealias Create = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    typealias Match = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Void
    typealias Services = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    typealias Property = @convention(c) (UnsafeMutableRawPointer, CFString) -> Unmanaged<CFTypeRef>?
    typealias Event = @convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    typealias Value = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double
    static let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL)
    static func symbol<T>(_ name: String, _: T.Type) -> T? {
        guard let library, let p = dlsym(library, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
    static func read() -> Double? {
        #if arch(arm64)
        guard let create = symbol("IOHIDEventSystemClientCreate", Create.self),
              let match = symbol("IOHIDEventSystemClientSetMatching", Match.self),
              let services = symbol("IOHIDEventSystemClientCopyServices", Services.self),
              let property = symbol("IOHIDServiceClientCopyProperty", Property.self),
              let event = symbol("IOHIDServiceClientCopyEvent", Event.self),
              let value = symbol("IOHIDEventGetFloatValue", Value.self),
              let client = create(kCFAllocatorDefault) else { return nil }
        defer { Unmanaged<CFTypeRef>.fromOpaque(client).release() }
        let filter = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        match(client, filter)
        guard let list = services(client)?.takeRetainedValue() else { return nil }
        var candidates: [Double] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let service = UnsafeMutableRawPointer(mutating: raw)
            guard let name = property(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  name.hasPrefix("PMU tdie") || name.hasPrefix("pACC MTR Temp") || name.hasPrefix("eACC MTR Temp"),
                  let reading = event(service, 15, 0, 0) else { continue }
            let celsius = value(reading, 15 << 16)
            Unmanaged<CFTypeRef>.fromOpaque(reading).release()
            if celsius.isFinite && (10...120).contains(celsius) { candidates.append(celsius) }
        }
        return candidates.max()
        #else
        return nil
        #endif
    }
}
