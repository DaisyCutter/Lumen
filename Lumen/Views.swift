import SwiftUI
import Charts
import AppKit

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @State var selected: Metric
    var onSettings: () -> Void
    private let accent = Color.teal
    private var s: Snapshot { monitor.snapshot }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lumen").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("YOUR MAC, AT A GLANCE").font(.system(size: 8, weight: .bold)).tracking(1.6).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(.green).frame(width: 5, height: 5)
                Text("LIVE").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(18)
            HStack(spacing: 3) {
                ForEach(Metric.allCases) { metric in
                    Button { selected = metric } label: {
                        Image(systemName: metric.symbol).font(.system(size: 15)).frame(maxWidth: .infinity).frame(height: 32)
                            .foregroundStyle(selected == metric ? accent : .secondary)
                            .background(selected == metric ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).help(metric.title).accessibilityLabel(metric.title)
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if selected == .overview { overview }
                    else {
                        HStack {
                            Label(selected.title, systemImage: selected.symbol).font(.title3.weight(.semibold))
                            Spacer()
                            Text("\(Int(monitor.preferences.interval))s refresh").font(.caption).foregroundStyle(.secondary)
                        }
                        switch selected {
                        case .cpu: cpuPanel
                        case .memory: memoryPanel
                        case .network: networkPanel
                        case .disk: diskPanel
                        case .battery: batteryPanel
                        case .sensors: sensorsPanel
                        case .overview: EmptyView()
                        }
                    }
                    if !s.errors.isEmpty {
                        Text(s.errors.joined(separator: " · ")).font(.caption).foregroundStyle(.orange)
                    }
                }.padding(18)
            }
            Divider()
            HStack {
                Text("Offline · On-device").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onSettings) { Image(systemName: "gearshape") }.help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit Lumen")
            }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 12)
        }.frame(width: 440, height: 660).background(.regularMaterial)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("System overview").font(.title3.weight(.semibold))
                Spacer()
                Text("\(Int(ProcessInfo.processInfo.systemUptime / 3600))h uptime").font(.caption).foregroundStyle(.secondary)
            }
            summary(.cpu, value: s.cores.isEmpty ? "Warming up…" : Format.percent(s.cpu), subtitle: "\(s.cores.count) logical cores", fraction: s.cpu, color: .teal)
            summary(.memory, value: Format.bytes(s.memory.used), subtitle: "\(Format.bytes(s.memory.total)) total · \(s.memory.pressure.lowercased()) pressure", fraction: s.memory.fraction, color: .purple)
            Button { selected = .network } label: {
                Card {
                    HStack {
                        Label("Network", systemImage: "network").fontWeight(.medium)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("↓ \(Format.rate(s.download))").foregroundStyle(.teal)
                            Text("↑ \(Format.rate(s.upload))").foregroundStyle(.blue)
                        }.monospacedDigit().font(.caption)
                    }
                    spark(.network, height: 38)
                }
            }.buttonStyle(.plain)
            summary(.disk, value: s.volumes.first.map { Format.bytes($0.free) + " free" } ?? "Unavailable", subtitle: s.volumes.first?.name ?? "No readable volumes", fraction: s.volumes.first?.fraction ?? 0, color: .blue)
            HStack(spacing: 12) {
                Button { selected = .battery } label: {
                    Card {
                        Label("Battery", systemImage: "battery.75percent").font(.caption).foregroundStyle(.secondary)
                        Text(s.battery.map { Format.percent($0.charge) } ?? "—").font(.title2.weight(.semibold)).monospacedDigit()
                        Text(s.battery?.status ?? "No battery").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button { selected = .sensors } label: {
                    Card {
                        Label("Thermals", systemImage: "thermometer.medium").font(.caption).foregroundStyle(.secondary)
                        Text(s.chipTemperature.map { "\(Int($0.rounded()))°C" } ?? s.thermal).font(.title3.weight(.semibold))
                        Text(s.chipTemperature == nil ? "macOS thermal state" : "Chip sensor peak").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.buttonStyle(.plain)
        }
    }
    private func summary(_ metric: Metric, value: String, subtitle: String, fraction: Double, color: Color) -> some View {
        Button { selected = metric } label: {
            Card {
                HStack {
                    Label(metric.title, systemImage: metric.symbol).fontWeight(.medium)
                    Spacer()
                    Text(value).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                }
                ProgressView(value: max(0, min(1, fraction))).tint(color)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain)
    }
    private var cpuPanel: some View {
        Group {
            Card {
                hero(Format.percent(s.cpu), caption: "Processor utilisation", color: .teal)
                HStack { pill("User", Format.percent(s.user), .teal); pill("System", Format.percent(s.system), .blue); pill("Idle", Format.percent(1-s.cpu), .gray) }
                spark(.cpu)
            }
            Card {
                heading("LOGICAL CORES")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36))], spacing: 10) {
                    ForEach(s.cores) { core in
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                                VStack(spacing: 0) {
                                    Rectangle().fill(.blue).frame(height: 55 * core.system)
                                    Rectangle().fill(loadColor(core.total)).frame(height: 55 * core.user)
                                }.clipShape(RoundedRectangle(cornerRadius: 4))
                            }.frame(width: 25, height: 55)
                            Text("\(core.id + 1)").font(.system(size: 9)).foregroundStyle(.secondary)
                        }.accessibilityLabel("Core \(core.id + 1), \(Format.percent(core.total))")
                    }
                }
                Text("Logical core order from macOS. Performance/efficiency labels are not inferred.").font(.caption2).foregroundStyle(.secondary)
            }
            processCard(memory: false)
        }
    }
    private var memoryPanel: some View {
        Group {
            Card {
                hero(Format.bytes(s.memory.used), caption: "of \(Format.bytes(s.memory.total)) physical memory", color: .purple)
                row("Memory pressure", s.memory.pressure)
                spark(.memory)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle().fill(.purple).frame(width: geometry.size.width * ratio(s.memory.app))
                        Rectangle().fill(.blue).frame(width: geometry.size.width * ratio(s.memory.wired))
                        Rectangle().fill(.orange).frame(width: geometry.size.width * ratio(s.memory.compressed))
                        Rectangle().fill(.secondary.opacity(0.2))
                    }.clipShape(Capsule())
                }.frame(height: 9)
                row("App (estimate)", Format.bytes(s.memory.app))
                row("Wired", Format.bytes(s.memory.wired))
                row("Compressed", Format.bytes(s.memory.compressed))
                row("Cached files + purgeable", Format.bytes(s.memory.cached))
                row("Other / free", Format.bytes(s.memory.free))
                Divider(); row("Swap used", Format.bytes(s.memory.swap))
            }
            Text("Usage and pressure are different. Pressure is the system’s categorical signal; app memory is estimated from VM page counters.").font(.caption).foregroundStyle(.secondary)
            processCard(memory: true)
        }
    }
    private var networkPanel: some View {
        Group {
            Card {
                HStack { pill("Download", Format.rate(s.download), .teal); pill("Upload", Format.rate(s.upload), .blue) }
                spark(.network)
                Divider()
                row("Received this session", Format.bytes(s.received))
                row("Sent this session", Format.bytes(s.sent))
                Text(monitor.preferences.interface == "auto" ? "Physical en* interfaces combined. VPN and bridge traffic is excluded to avoid double counting." : "Selected interface: \(monitor.preferences.interface)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Card {
                heading("INTERFACES")
                ForEach(s.interfaces) { item in
                    VStack(spacing: 4) {
                        HStack { Text(item.id).fontWeight(.medium); Spacer(); Text(item.active ? "Up" : "Down").foregroundStyle(.secondary) }
                        HStack { Text("↓ \(Format.rate(item.download))").foregroundStyle(.teal); Spacer(); Text("↑ \(Format.rate(item.upload))").foregroundStyle(.blue) }
                            .font(.caption).monospacedDigit()
                    }.padding(.vertical, 3)
                }
            }
            Text("Rates measure interface traffic, including local transfers. They are not an internet speed test. Totals reset on app restart or interface change; sleep gaps are excluded.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var diskPanel: some View {
        Group {
            if s.volumes.isEmpty { empty("No readable volumes", "Mounted volume information is unavailable.") }
            ForEach(s.volumes) { v in
                Card {
                    HStack { Label(v.name, systemImage: v.internalDrive ? "internaldrive" : "externaldrive").fontWeight(.semibold); Spacer(); Text(Format.percent(v.fraction)).foregroundStyle(loadColor(v.fraction)) }
                    ProgressView(value: v.fraction).tint(loadColor(v.fraction))
                    row("Used", Format.bytes(v.total-v.free))
                    row("Free now", Format.bytes(v.free))
                    row("Potentially reclaimable", v.reclaimable.map(Format.bytes) ?? "Unavailable")
                    row("Total", Format.bytes(v.total))
                    Divider(); row("Format", v.format)
                    row("Location", v.internalDrive ? "Internal" : "External / network")
                    Text(v.id).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Text("Reclaimable is an estimate from macOS important-usage capacity, included in used space above. APFS volumes may share container capacity; do not add their totals. Encryption and disk I/O rates are not collected.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var batteryPanel: some View {
        Group {
            if let b = s.battery {
                Card {
                    hero(Format.percent(b.charge), caption: b.status, color: b.charge < 0.2 ? .orange : .green)
                    ProgressView(value: max(0, min(1, b.charge))).tint(.green)
                    spark(.battery)
                    row("Time estimate", b.time)
                    row("Health", b.health)
                    row("Condition", b.condition)
                    row("Design capacity", b.design.map { "\(Int($0)) mAh" } ?? "Not exposed")
                    row("Nominal capacity", b.nominal.map { "\(Int($0)) mAh" } ?? "Not exposed")
                    row("Cycle count", "Not exposed")
                    row("Temperature", "Unavailable")
                }
                Text("Values come from the public IOKit power-source API. Health detail and capacity vary by hardware. No undocumented battery registry fields are read.").font(.caption).foregroundStyle(.secondary)
            } else { empty("No internal battery", "This Mac has no internal battery, or macOS is not exposing a power-source reading. External UPS devices are not treated as laptop batteries.") }
        }
    }
    private var sensorsPanel: some View {
        Group {
            Card {
                hero(s.chipTemperature.map { "\(Int($0.rounded()))°C" } ?? "Unavailable", caption: "Highest recognised chip sensor", color: .teal)
                row("macOS thermal condition", s.thermal)
                row("Fan speed", "Unavailable")
                Text("The temperature is the highest plausible reading among recognised chip sensors, not necessarily a CPU core or die temperature. Updated every five seconds.").font(.caption).foregroundStyle(.secondary)
            }
            empty("About temperature readings", "Apple Silicon readings use an undocumented, read-only macOS interface. Sensor names vary between models and may change after system updates. N/A means no recognised valid reading was found. Fan RPM remains unavailable.")
        }
    }
    private func processCard(memory: Bool) -> some View {
        Card {
            heading(memory ? "TOP MEMORY · RESIDENT SIZE" : "TOP CPU · ONE CORE = 100%")
            let processes = Array(s.processes.sorted { memory ? $0.memory > $1.memory : $0.cpu > $1.cpu }.prefix(5))
            if processes.isEmpty { Text("Waiting for accessible process counters…").font(.caption).foregroundStyle(.secondary) }
            ForEach(processes) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).lineLimit(1)
                        Text("PID \(p.id)").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(memory ? Format.bytes(p.memory) : String(format: "%.1f%%", p.cpu)).monospacedDigit().foregroundStyle(.secondary)
                }.font(.caption)
            }
            Text("Updated every 5 seconds. Restricted processes are omitted. Resident sizes can share pages.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func spark(_ metric: Metric, height: CGFloat = 80) -> some View {
        let samples = monitor.history
        let maximum = metric == .network ? max(1024, samples.map { max($0.download, $0.upload) }.max() ?? 1024) : 1
        return Chart {
            ForEach(samples) { sample in
                if metric == .network {
                    LineMark(x: .value("Time", sample.date), y: .value("Bytes/s", sample.download), series: .value("Direction", "Download")).foregroundStyle(.teal)
                    LineMark(x: .value("Time", sample.date), y: .value("Bytes/s", sample.upload), series: .value("Direction", "Upload")).foregroundStyle(.blue)
                } else if let value = chartValue(sample, metric) {
                    AreaMark(x: .value("Time", sample.date), y: .value("Usage", value)).foregroundStyle(LinearGradient(colors: [accent.opacity(0.25), accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", sample.date), y: .value("Usage", value)).foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
        }.chartYScale(domain: 0...maximum)
            .chartXScale(domain: (samples.last?.date ?? Date()).addingTimeInterval(-60)...(samples.last?.date ?? Date()))
            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: height)
            .background(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 1) }
            .accessibilityLabel("Last 60 seconds of \(metric.title.lowercased()) history")
    }
    private func chartValue(_ sample: Sample, _ metric: Metric) -> Double? {
        switch metric { case .cpu: sample.cpu; case .memory: sample.memory; case .battery: sample.battery; default: nil }
    }
    private func hero(_ value: String, caption: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 34, weight: .medium, design: .rounded)).foregroundStyle(color).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }.padding(.bottom, 6)
    }
    private func pill(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(color).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.caption)
    }
    private func heading(_ title: String) -> some View { Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary) }
    private func empty(_ title: String, _ detail: String) -> some View {
        Card { Label(title, systemImage: "info.circle").font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
    private func ratio(_ value: Double) -> Double { s.memory.total > 0 ? max(0, min(1, value/s.memory.total)) : 0 }
    private func loadColor(_ value: Double) -> Color { value >= 0.9 ? .red : value >= 0.7 ? .orange : .teal }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.045)) }
    }
}
struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var monitor: Monitor
    var body: some View {
        Form {
            Section("Menu bar") {
                ForEach(Metric.allCases.filter { $0 != .overview }) { metric in
                    Toggle(metric.title, isOn: Binding(get: { preferences.enabled.contains(metric) }, set: { enabled in
                        if enabled { preferences.enabled.insert(metric) } else { preferences.enabled.remove(metric) }
                    }))
                }
                Toggle("Compact text", isOn: $preferences.compact)
                Text("The Lumen icon always stays visible. Command-drag icons to arrange them; macOS may hide items when the menu bar is full.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Sampling") {
                Picker("Refresh", selection: $preferences.interval) {
                    Text("Every second").tag(1.0); Text("Every 2 seconds").tag(2.0); Text("Every 5 seconds").tag(5.0)
                }
                Picker("Network totals", selection: $preferences.interface) {
                    Text("Physical interfaces (en*)").tag("auto")
                    ForEach(monitor.snapshot.interfaces) { item in Text(item.id).tag(item.id) }
                    if preferences.interface != "auto" && !monitor.snapshot.interfaces.contains(where: { $0.id == preferences.interface }) {
                        Text("\(preferences.interface) (disconnected)").tag(preferences.interface)
                    }
                }
                Text("Changing the interface resets session totals and history. Volume and process details refresh every 5 seconds.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Lumen 1.0 · No accounts, analytics or licence checks. All readings stay in memory on your Mac; settings are saved locally.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 480, height: 570)
    }
}
