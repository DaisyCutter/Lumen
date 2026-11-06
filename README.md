# Lumen

An independent, native macOS menu-bar system monitor built with Swift, SwiftUI, AppKit and Swift Charts. Requires **macOS 14 or later**. Builds for Apple Silicon and Intel. No package dependencies, account, subscription, licence validation, telemetry, outbound requests or server dependency. All history is in memory; preferences are local UserDefaults.

**[Visit the Lumen product page](https://daisycutter.github.io/Lumen/)** · [Download the latest app](https://github.com/DaisyCutter/Lumen/releases/latest/download/Lumen.zip)

## Get the source

```sh
git clone https://github.com/DaisyCutter/Lumen.git
cd Lumen
```

## Open and run

1. Open `Lumen.xcodeproj` in Xcode 15 or newer (validated with Xcode 26.6).
2. Select the **Lumen** scheme and **My Mac**, then Run (⌘R).
3. Find the waveform icon and metric items on the right side of the menu bar. Click an item for its panel. The app has no Dock icon.
4. Use the gear button to select menu-bar metrics, compact text, 1/2/5-second sampling and the network interface. The waveform icon remains available even when all metrics are hidden. Quit using the power button.

For local builds without a development team:

```sh
./build.sh
open .build/Build/Products/Release/Lumen.app
```

`build.sh` builds a universal Release app and signs it ad hoc for local use. You can copy that app to Applications yourself. In Xcode, if signing asks for a team, set Signing Certificate to **Sign to Run Locally**, or use the script. There are no entitlements or additional permissions to configure. App Sandbox is disabled because system-wide process inspection is part of the functionality; the app does not request administrator access.

For distributing beyond your own Mac, configure your own bundle identifier and Developer ID signing, then archive and notarize using your Apple developer account. The supplied local build is **not notarized**. It does not include an updater. If macOS blocks the downloaded app, see [Apple’s guidance on opening apps safely](https://support.apple.com/en-gb/102445).

To display the same dashboard in a conventional window for inspection:

```sh
open .build/Build/Products/Release/Lumen.app --args --dashboard
```

Launch arguments apply when the app starts; quit an existing instance first. In Xcode you can put `--dashboard` in Scheme → Run → Arguments.

## What is implemented

| Area | Readings and interaction |
| --- | --- |
| Menu bar | Individually enabled metrics; dark rounded widgets with vertically stacked labels, CPU bars (first eight logical cores), memory usage ring, stacked download/upload rates, disk and battery percentages, and a chip-temperature indicator when available; compact network option; click any metric to open its panel |
| Overview | Resource cards and a network sparkline; click a card or the navigation icons for details |
| CPU | All logical cores, user/system/idle breakdown, 60-second history, top accessible CPU processes using interval deltas |
| Memory | Estimated app memory, wired, compressed, cached/purgeable and other/free; categorical system pressure when available; swap; top resident-memory processes |
| Network | Download/upload history, rates per interface, session totals; physical `en*` links by default or one selected interface including VPNs |
| Disk | Visible mounted volumes plus a startup-volume fallback, used/free capacity, macOS reclaimable estimate when available, filesystem format and location |
| Battery | Internal battery charge, charging/power status, system time estimate and public health/condition/capacity fields when exposed; charge history |
| Sensors | Best-effort Apple Silicon chip-sensor peak and macOS thermal condition; fan speed unavailable |

History is a rolling 60 seconds at the chosen sampling interval, not 60 fixed samples. Process and disk details update no more frequently than every five seconds. No historical log is written. Session transfer totals reset when the app restarts or the interface selection changes. Sleep gaps longer than 30 seconds do not count toward rates or totals. CPU usage is a fraction of the whole machine; process CPU uses one logical core = 100% and can exceed 100%.

## Accuracy and limitations

- **Temperature / fans:** On Apple Silicon, Lumen discovers recognised `PMU tdie`, `pACC MTR Temp` and `eACC MTR Temp` sensors using an undocumented, read-only IOKit HID interface. It displays the highest plausible (10–120 °C) reading as a **chip sensor peak**, not a confirmed CPU die or core temperature. It samples every five seconds, needs no administrator privileges on the tested Mac, and shows N/A when the API or recognised readings are unavailable. Sensors, permissions and private interfaces vary by model and macOS version; one successful reading is not proof of calibrated accuracy. Intel falls back to N/A. No fan control or privileged helper is used; fan RPM remains unavailable. macOS thermal condition is a separate categorical signal. Enable Sensors in Settings to show the temperature tile.
- **Battery:** only public IOKit power-source dictionaries are read. Cycle count is not exposed through the selected API and is labelled accordingly. Health, condition and design/nominal capacity may also be absent. No health percentage is invented from charge percentage. Desktops show a no-internal-battery state; external UPS devices are excluded. Time remaining can be unavailable or still calculating.
- **Memory:** app memory is a VM-page estimate, not Activity Monitor's private accounting. Pressure is categorical, not an invented percentage. It may initially remain Unknown if macOS does not expose an initial pressure level and no pressure event has arrived. Process resident sizes include shared pages and must not be summed as exclusive app memory.
- **CPU:** cores are logical CPU indices; P/E labels are not guessed. First sampling interval establishes a baseline. Process start timestamps disambiguate reused PIDs; restricted or vanished processes are omitted. Sampling hundreds of processes has a cost, so it runs every five seconds.
- **Network:** 64-bit routing counters avoid 32-bit wraps. Counter resets and long sleep gaps produce zero rates rather than spikes. Default totals combine `en*` interfaces, excluding loopback, bridges and VPN tunnels to reduce double counting. This can include local traffic and cannot universally identify the internet-facing route. Select an interface for precise scope. Per-interface rows can represent overlapping traffic; do not sum them indiscriminately. No per-process bandwidth attribution, packet capture or speed test is implemented.
- **Disk:** reclaimable space is an estimate derived from important-usage availability and is already included in used space, not an extra partition. APFS volumes can share container capacity and their totals should not be added. Encryption state and disk read/write throughput are not collected. Resource metadata can be unavailable; a public `statfs` capacity fallback is used. Mounted external/network volumes depend on macOS visibility and access.
- Menu-bar space is controlled by macOS, including notch constraints. Disable some metrics or use compact mode if items disappear. Command-drag icons to arrange them.
- The app follows system light/dark appearance. Metrics have text labels and accessibility descriptions. Large text/VoiceOver, multi-display placement, hot plugging, wake transitions and older macOS versions still need hands-on testing.

## Test and validation

```sh
./test.sh
```

This compiles the real collector with a standalone smoke-test executable. It checks rate math, counter resets and sleep gaps; live core/memory/volume/process readings; optional battery readings; process CPU against a controlled busy `/usr/bin/yes` child; and interface-change session resets. It uses about 12 seconds and briefly loads one CPU core. The child is terminated on normal completion. This is an integration check, not a mock data demo.

The Xcode project has no XCTest target; `test.sh` is the test entry point. Release builds have been validated for Apple Silicon and Intel; runtime and sensor tests have been performed on one Apple Silicon Mac. Other hardware and macOS versions need further testing.

## Source map

- `LumenApp.swift`: app lifecycle, independent AppKit status items, popover and settings window.
- `Monitor.swift`: observable state, preferences, serial sampling and bounded history.
- `Collector.swift`: Mach CPU/VM, public BSD process/routing/filesystem calls, IOKit power sources and macOS thermal state.
- `Models.swift`: value snapshots, units, formatting and counter-delta rules.
- `Views.swift`: original SwiftUI cards, charts, navigation and preferences.
- `Resources/AppIcon.svg`: editable original icon artwork; `Lumen.icns` is the app icon.

## Design provenance

The public feature list and illustrated panel examples at [General Software's Beacon page](https://general.software/beacon/) informed the six-panel scope, compact indicators and usage-history pattern. This is a new implementation with original code, name, card styling and icon. No proprietary app binary, source, assets or licence mechanism was accessed, copied or modified. Lumen is not affiliated with General Software and does not claim complete Beacon feature parity. The implementation deliberately limits sensor and health readings to what it can obtain honestly through the APIs described above.

CPU accounting also follows Apple’s public Mach timebase: task counters are converted using `mach_timebase_info`, and verified against a controlled load. Apple’s [XNU accounting overview](https://github.com/apple-oss-distributions/xnu/blob/main/doc/observability/recount.md) provides background on the system interfaces; no kernel source is bundled.

## Licence

Lumen is available under the [MIT License](LICENSE).
