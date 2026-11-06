import SwiftUI
import Combine

final class Preferences: ObservableObject {
    @Published var enabled: Set<Metric> { didSet { save() } }
    @Published var interval: Double { didSet { UserDefaults.standard.set(interval, forKey: "interval") } }
    @Published var interface: String { didSet { UserDefaults.standard.set(interface, forKey: "interface") } }
    @Published var compact: Bool { didSet { UserDefaults.standard.set(compact, forKey: "compact") } }
    init() {
        let stored = UserDefaults.standard.stringArray(forKey: "metrics")
        enabled = stored.map { Set($0.compactMap(Metric.init(rawValue:))) } ?? [.cpu, .memory, .network, .battery]
        let interval = UserDefaults.standard.double(forKey: "interval")
        self.interval = [1.0, 2.0, 5.0].contains(interval) ? interval : 1
        interface = UserDefaults.standard.string(forKey: "interface") ?? "auto"
        compact = UserDefaults.standard.bool(forKey: "compact")
    }
    private func save() { UserDefaults.standard.set(enabled.map(\.rawValue), forKey: "metrics") }
}
final class Monitor: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var history: [Sample] = []
    let preferences = Preferences()
    private let queue = DispatchQueue(label: "local.lumen.sampler", qos: .utility)
    private var collector: Collector!
    private var timer: DispatchSourceTimer?
    private var subscriptions: Set<AnyCancellable> = []
    init() {
        collector = Collector(queue: queue)
        preferences.$interval.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.restart() }.store(in: &subscriptions)
        preferences.$interface.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.history.removeAll() }.store(in: &subscriptions)
        restart()
    }
    private func restart() {
        timer?.cancel()
        let interval = preferences.interval
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in self?.sample() }
        source.resume(); timer = source
    }
    private var sampling = false
    private func sample() {
        guard !sampling else { return }
        sampling = true
        let interface = preferences.interface
        queue.async { [weak self] in
            guard let self else { return }
            let s = self.collector.sample(interface: interface)
            DispatchQueue.main.async {
                self.snapshot = s
                self.history.append(Sample(cpu: s.cpu, memory: s.memory.fraction, download: s.download, upload: s.upload, battery: s.battery?.charge))
                self.history.removeAll { $0.date < Date().addingTimeInterval(-60) }
                self.sampling = false
            }
        }
    }
}
