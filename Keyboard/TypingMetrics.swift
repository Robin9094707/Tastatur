import UIKit
import SwiftUI

/// Tipp-Messung direkt auf dem iPhone: Wie schnell kommt jeder Finger an, wo hängt die Tastatur?
/// Immer aktiv ist nur die billige Messung pro Tipp (eine Subtraktion). Die Ruckler-Erkennung
/// (Bildwechsel-Zähler) läuft nur nach „Messen“ für 60 Sekunden.
final class TypingMetrics: ObservableObject {
    static let shared = TypingMetrics()

    // Reaktionszeit: vom echten Berühren (UITouch.timestamp) bis die Tastatur den Tipp verarbeitet
    private(set) var taps = 0
    private var latencySum: Double = 0
    private(set) var latencyMax: Double = 0
    private(set) var slowTaps = 0          // > 34 ms (mehr als 2 Bilder bei 60 Hz)

    // Laufzeit einzelner Arbeitsschritte auf dem Haupt-Thread
    private(set) var slowest: [String: Double] = [:]

    // Ruckler (nur während der Messung)
    @Published private(set) var measuring = false
    @Published private(set) var report = ""
    private(set) var stalls = 0
    private(set) var worstStall: Double = 0
    private(set) var worstStallLabel = ""
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var endTime: CFTimeInterval = 0
    /// Was zuletzt auf dem Haupt-Thread lief (für die Zuordnung eines Rucklers).
    var lastWork = "–"

    /// Pro Tipp aus `touchesBegan` – kostet praktisch nichts.
    private var lastTap: CFTimeInterval = 0

    func touchArrived(_ t: UITouch) {
        lastTap = CACurrentMediaTime()
        let ms = (CACurrentMediaTime() - t.timestamp) * 1000
        guard ms >= 0, ms < 5000 else { return }
        taps += 1
        latencySum += ms
        if ms > latencyMax { latencyMax = ms }
        if ms > 34 { slowTaps += 1 }
        DebugLog.shared.tap(ms)
    }

    /// Misst einen Arbeitsschritt (nur wenn er spürbar lang war, wird er gemerkt).
    @inline(__always)
    func measure<T>(_ label: String, _ work: () -> T) -> T {
        let start = CACurrentMediaTime()
        let r = work()
        let ms = (CACurrentMediaTime() - start) * 1000
        lastWork = label
        if ms > 4, ms > (slowest[label] ?? 0) { slowest[label] = ms }
        if ms > 8 { DebugLog.shared.add(.slow, String(format: "%@ dauerte %.1f ms", label, ms)) }
        return r
    }

    func start() {
        reset()
        measuring = true
        report = "Messung läuft … tippe jetzt 60 Sekunden lang ganz normal (auch schnell mit mehreren Fingern)."
        lastFrame = CACurrentMediaTime()
        endTime = lastFrame + 60
        let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        guard measuring else { return }
        measuring = false
        report = summary
    }

    func reset() {
        taps = 0; latencySum = 0; latencyMax = 0; slowTaps = 0
        slowest = [:]; stalls = 0; worstStall = 0; worstStallLabel = ""
        report = ""
    }

    @objc private func frame(_ l: CADisplayLink) {
        let now = l.timestamp
        let gap = (now - lastFrame) * 1000
        lastFrame = now
        // Ein Bild dauert 8–16 ms. Über 50 ms sieht man ein Ruckeln.
        // Nur Ruckler beim Tippen zählen (kurz nach einem Tipp), nicht beim Öffnen von Menüs
        if gap > 50, gap < 1000, now - lastTap < 1.2, lastWork != "Panel wechseln" {
            stalls += 1
            if gap > worstStall { worstStall = gap; worstStallLabel = lastWork }
        }
        if now >= endTime { stop() }
    }

    var summary: String {
        guard taps > 0 else { return "Noch keine Tipps gemessen." }
        let avg = latencySum / Double(taps)
        var lines = [
            String(format: "Reaktion: Ø %.0f ms · max %.0f ms · %d von %d Tipps verzögert", avg, latencyMax, slowTaps, taps),
            "Ruckler: \(stalls)" + (stalls > 0 ? String(format: " (schlimmster %.0f ms nach „%@“)", worstStall, worstStallLabel) : ""),
        ]
        let top = slowest.sorted { $0.value > $1.value }.prefix(4)
        if !top.isEmpty {
            lines.append("Langsamste Schritte: " + top.map { String(format: "%@ %.0f ms", $0.key, $0.value) }.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }
}

/// Anzeige in den Einstellungen (Seite „Tippen“).
struct TypingMetricsView: View {
    @ObservedObject var metrics = TypingMetrics.shared
    var tint: Color
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Tipp-Messung", systemImage: "speedometer").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if metrics.measuring { metrics.stop() } else { metrics.start() }
                } label: {
                    Text(metrics.measuring ? "Stopp" : "Messen")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(tint))
                }
                .buttonStyle(.plain)
            }
            Text(metrics.report.isEmpty ? metrics.summary : metrics.report)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tipp auf „Messen“, schließe die Einstellungen und tippe 60 Sekunden lang. Danach hier wieder öffnen, einen Screenshot machen und an Claude schicken.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .glass(cornerRadius: 12)
        .id(tick)
        .onAppear { tick += 1 }
    }
}

// MARK: - Debug-Protokoll

/// Protokoll direkt in der Tastatur (nur im Speicher, max. 600 Einträge).
/// Pro Tipp wird nur ein kleiner Eintrag angehängt – Text wird erst beim Anzeigen gebaut.
final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    enum Kind: String { case system = "SYS", ui = "UI", tap = "TIPP", slow = "LANGSAM", stall = "RUCKLER", warning = "WARNUNG", error = "FEHLER", info = "INFO" }

    struct Entry {
        let time: Date
        let kind: Kind
        let text: String
        let value: Double
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 600
    /// Aufzeichnung an (Einstellung „Debug-Protokoll“) und Tastatur sichtbar.
    private(set) var active = false
    private var enabled = false
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    @Published private(set) var version = 0

    func setActive(_ on: Bool) {
        if on { enabled = SharedStore.shared.debugLog }
        let want = on && enabled
        guard want != active else { return }
        active = want
        if want {
            lastFrame = CACurrentMediaTime()
            let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        } else {
            link?.invalidate()
            link = nil
        }
    }

    func add(_ kind: Kind, _ text: String, value: Double = 0) {
        // System-Ereignisse und Fehler immer, alles andere nur bei aktiver Aufzeichnung
        guard active || kind == .system || kind == .error || kind == .warning else { return }
        entries.append(Entry(time: Date(), kind: kind, text: text, value: value))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }

    func tap(_ latencyMs: Double) {
        guard active else { return }
        add(.tap, "", value: latencyMs)
    }

    @objc private func frame(_ l: CADisplayLink) {
        let now = l.timestamp
        let gap = (now - lastFrame) * 1000
        lastFrame = now
        if gap > 50, gap < 1500 {
            add(.stall, String(format: "Bild hing %.0f ms (zuletzt: %@)", gap, TypingMetrics.shared.lastWork), value: gap)
        }
    }

    func clear() {
        entries.removeAll()
        version += 1
    }

    func refresh() { version += 1 }

    /// Speicherverbrauch der Tastatur in MB (wie iOS ihn fürs Limit zählt).
    static func memoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint / 1_048_576)
    }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func line(_ e: Entry) -> String {
        let t = Self.timeFormat.string(from: e.time)
        if e.kind == .tap { return String(format: "%@ TIPP  Reaktion %.0f ms", t, e.value) }
        return "\(t) \(e.kind.rawValue)  \(e.text)"
    }

    /// Kompletter Bericht zum Kopieren (für Claude).
    func report(store: SharedStore) -> String {
        let taps = entries.filter { $0.kind == .tap }
        let avg = taps.isEmpty ? 0 : taps.map(\.value).reduce(0, +) / Double(taps.count)
        let maxLat = taps.map(\.value).max() ?? 0
        let stalls = entries.filter { $0.kind == .stall }
        var head = [
            "Tastatur-KI Debug-Protokoll",
            "iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model) · Speicher \(Self.memoryMB()) MB",
            "Light-Modus: \(store.lightMode ? "an" : "aus") · Wischen: \(store.swipeTyping ? "an" : "aus") · Autokorrektur: \(store.autocorrect ? "an" : "aus") · Trefferzonen: \(store.smartTouch ? "an" : "aus") · Tipp-Korrektur: \(store.tapCorrection ? "an" : "aus") · Haptik: \(store.haptics ? "an" : "aus") · Ton: \(store.keySound ? "an" : "aus") · Vorschau: \(store.keyPopups ? "an" : "aus")",
            String(format: "Tipps: %d · Reaktion Ø %.0f ms · max %.0f ms · Ruckler: %d", taps.count, avg, maxLat, stalls.count),
            TypingMetrics.shared.summary,
            "",
        ]
        head.append(contentsOf: entries.map(line))
        return head.joined(separator: "\n")
    }
}

/// Anzeige des Protokolls in der Tastatur.
struct DebugLogPanel: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared
    @ObservedObject var log = DebugLog.shared

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                button(store.debugLog ? "Aufzeichnung an" : "Aufzeichnung aus", store.debugLog ? "record.circle.fill" : "record.circle", prominent: store.debugLog) {
                    store.debugLog.toggle()
                    DebugLog.shared.setActive(store.debugLog)
                    DebugLog.shared.add(.system, store.debugLog ? "Aufzeichnung gestartet" : "Aufzeichnung beendet")
                    log.refresh()
                }
                button("Kopieren", "doc.on.doc", prominent: false) {
                    guard state.hasFullAccess else { state.showToast("Kopieren braucht „Vollen Zugriff“."); return }
                    UIPasteboard.general.string = log.report(store: store)
                    state.lastChangeCount = UIPasteboard.general.changeCount
                    state.showToast("Protokoll kopiert – jetzt an Claude schicken 📋")
                }
                button("Leeren", "trash", prominent: false) { log.clear() }
            }
            ScrollViewReader { reader in
                ScrollView {
                    let list = Array(log.entries.suffix(250).enumerated())
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if list.isEmpty {
                            Text(store.debugLog ? "Noch keine Einträge – schließ das Protokoll und tippe etwas." : "Aufzeichnung ist aus. Tippe oben auf „Aufzeichnung“, dann ganz normal tippen und hier wieder reinschauen.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(list, id: \.offset) { i, e in
                            Text(log.line(e))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(color(e.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onAppear { if let last = shownIndices(log).last { reader.scrollTo(last, anchor: .bottom) } }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .id(log.version)
    }

    private func shownIndices(_ log: DebugLog) -> [Int] { Array(0..<min(log.entries.count, 250)) }

    private func color(_ k: DebugLog.Kind) -> Color {
        switch k {
        case .error, .stall: return .red
        case .slow, .warning: return .orange
        case .tap: return .secondary
        default: return .primary
        }
    }

    private func button(_ title: String, _ symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 32)
                .glassCapsule(tint: prominent ? state.tint : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
