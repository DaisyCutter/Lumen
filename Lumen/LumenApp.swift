import SwiftUI
import AppKit
import Combine

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = Monitor()
    private var items: [Metric: NSStatusItem] = [:]
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popover.behavior = .transient
        monitor.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        monitor.preferences.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        refresh()
        if CommandLine.arguments.contains("--dashboard") { showDashboardWindow() }
    }
    func refresh() {
        let desired = monitor.preferences.enabled.union([.overview])
        for metric in Array(items.keys) where !desired.contains(metric) {
            if let item = items.removeValue(forKey: metric) { NSStatusBar.system.removeStatusItem(item) }
        }
        for metric in Metric.allCases where desired.contains(metric) {
            let item: NSStatusItem
            if let existing = items[metric] { item = existing }
            else {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                items[metric] = item
                item.button?.target = self; item.button?.action = #selector(clicked(_:))
                item.button?.identifier = NSUserInterfaceItemIdentifier(metric.rawValue)
            }
            guard let button = item.button else { continue }
            button.font = .monospacedDigitSystemFont(ofSize: monitor.preferences.compact ? 10 : 11, weight: .medium)
            button.image = widget(metric)
            button.imagePosition = .imageOnly
            button.title = ""
            if metric == .overview {
                button.title = ""
                button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Lumen system monitor")
            }
            button.toolTip = "Lumen · \(metric.title) — click for details"
            button.setAccessibilityLabel("Lumen \(metric.title) \(title(metric))")
        }
    }
    private func widget(_ metric: Metric) -> NSImage? {
        guard metric != .overview else { return nil }
        let s = monitor.snapshot
        let width: CGFloat
        switch metric {
        case .cpu: width = 61
        case .memory: width = 40
        case .network: width = monitor.preferences.compact ? 68 : 76
        case .disk: width = 43
        case .battery: width = 54
        case .sensors: width = 64
        case .overview: return nil
        }
        let image = NSImage(size: NSSize(width: width, height: 30), flipped: false) { _ in
            let tile = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: width-1, height: 29), xRadius: 4, yRadius: 4)
            NSColor(calibratedWhite: 0.08, alpha: 0.96).setFill(); tile.fill()
            NSColor(calibratedWhite: 0.35, alpha: 1).setStroke(); tile.lineWidth = 0.7; tile.stroke()
            let inset = NSAffineTransform(); inset.translateX(by: 0, yBy: 3); inset.concat()
            func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor = .white, weight: NSFont.Weight = .bold) {
                (value as NSString).draw(at: NSPoint(x: x + 3, y: y), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight), .foregroundColor: color])
            }
            func label(_ letters: String) {
                for (i, letter) in letters.enumerated() { text(String(letter), 4, 16.4-CGFloat(i)*6.6, 6.3, NSColor(white: 0.67, alpha: 1)) }
            }
            func shortRate(_ n: Double) -> String {
                if n >= 1_000_000_000 { return String(format: "%.1f G", n / 1_000_000_000) }
                if n >= 1_000_000 { return String(format: "%.1f M", n / 1_000_000) }
                if n >= 1000 { return String(format: "%.0f K", n / 1000) }
                return String(format: "%.0f B", n)
            }
            func right(_ value: String, y: CGFloat, size: CGFloat) {
                let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
                let w = (value as NSString).size(withAttributes: [.font: font]).width
                text(value, width-11-w, y, size)
            }
            switch metric {
            case .cpu:
                label("CPU")
                let cores = Array(s.cores.prefix(8))
                let available: CGFloat = width - 23
                let gap: CGFloat = 1
                let bar = (available - CGFloat(max(0, cores.count - 1))*gap) / CGFloat(max(1, cores.count))
                for (i, core) in cores.enumerated() {
                    let value = max(0, min(1, core.total))
                    (value >= 0.7 ? NSColor.systemRed : NSColor.systemBlue).setFill()
                    NSBezierPath(rect: NSRect(x: 17 + CGFloat(i)*(bar+gap), y: 4, width: bar, height: max(1, CGFloat(value)*15))).fill()
                }
            case .memory:
                label("MEM")
                let centre = NSPoint(x: 26, y: 12), radius: CGFloat = 8
                NSColor(white: 0.25, alpha: 1).setStroke()
                let track = NSBezierPath(ovalIn: NSRect(x: 18, y: 4, width: 16, height: 16)); track.lineWidth = 2.8; track.stroke()
                NSColor.systemOrange.setStroke()
                let arc = NSBezierPath(); arc.appendArc(withCenter: centre, radius: radius, startAngle: 90, endAngle: 90-CGFloat(max(0,min(1,s.memory.fraction)))*360, clockwise: true); arc.lineWidth = 2.8; arc.lineCapStyle = .round; arc.stroke()
                let percent = s.memory.total > 0 ? String(Int((s.memory.fraction*100).rounded())) : "–"
                let font = NSFont.monospacedDigitSystemFont(ofSize: 6, weight: .bold)
                let tw = (percent as NSString).size(withAttributes: [.font: font]).width
                text(percent, 23-tw/2, 8, 6, NSColor(white: 0.8, alpha: 1))
            case .network:
                label("NET")
                text("↓", 15, 12, 10, .systemTeal); text("↑", 15, 2, 10, .systemRed)
                right(shortRate(s.download), y: 12, size: 8.5); right(shortRate(s.upload), y: 2, size: 8.5)
            case .disk:
                label("DSK")
                if let volume = s.volumes.first { right(Format.percent(volume.fraction), y: 7, size: 9) } else { right("—", y: 7, size: 9) }
            case .battery:
                label("BAT")
                right(s.battery.map { Format.percent($0.charge) } ?? "—", y: 7, size: 9)
            case .sensors:
                label("TMP")
                NSColor.systemTeal.setStroke()
                let stem = NSBezierPath(roundedRect: NSRect(x: 20, y: 8, width: 3.5, height: 11), xRadius: 1.75, yRadius: 1.75)
                stem.lineWidth = 1; stem.stroke()
                let bulb = NSBezierPath(ovalIn: NSRect(x: 19, y: 5, width: 5.5, height: 5.5))
                bulb.lineWidth = 1; bulb.stroke()
                NSColor.systemTeal.setFill()
                NSBezierPath(roundedRect: NSRect(x: 21.1, y: 7, width: 1.3, height: 8), xRadius: 0.6, yRadius: 0.6).fill()
                right(s.chipTemperature.map { "\(Int($0.rounded()))°" } ?? "N/A", y: 7, size: 8)
            case .overview: break
            }
            return true
        }
        image.isTemplate = false
        return image
    }
    private func title(_ metric: Metric) -> String {
        let s = monitor.snapshot
        switch metric {
        case .overview: return "Lumen"
        case .cpu: return "CPU \(s.cores.isEmpty ? "—" : Format.percent(s.cpu))"
        case .memory: return "MEM \(Format.percent(s.memory.fraction))"
        case .network: return monitor.preferences.compact ? "↓\(Format.rate(s.download))" : "↓\(Format.rate(s.download)) ↑\(Format.rate(s.upload))"
        case .disk: return "DSK \(s.volumes.first.map { Format.percent($0.fraction) } ?? "—")"
        case .battery: return "BAT \(s.battery.map { Format.percent($0.charge) } ?? "—")"
        case .sensors: return s.chipTemperature.map { "Chip sensor peak \(Int($0.rounded())) degrees Celsius" } ?? "Temperature unavailable; thermal state \(s.thermal)"
        }
    }
    @objc private func clicked(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil); return }
        let metric = Metric(rawValue: sender.identifier?.rawValue ?? "") ?? .overview
        popover.contentViewController = NSHostingController(rootView: Dashboard(monitor: monitor, selected: metric, onSettings: { [weak self] in self?.showSettings() }))
        popover.contentSize = NSSize(width: 440, height: 660)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 570), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Lumen Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView(preferences: monitor.preferences, monitor: monitor))
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private var dashboardWindow: NSWindow?
    private func showDashboardWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Lumen"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Dashboard(monitor: monitor, selected: .overview, onSettings: { [weak self] in self?.showSettings() }))
        window.center(); window.makeKeyAndOrderFront(nil); dashboardWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
