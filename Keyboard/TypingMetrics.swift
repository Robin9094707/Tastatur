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
    func touchArrived(_ t: UITouch) {
        let ms = (CACurrentMediaTime() - t.timestamp) * 1000
        guard ms >= 0, ms < 5000 else { return }
        taps += 1
        latencySum += ms
        if ms > latencyMax { latencyMax = ms }
        if ms > 34 { slowTaps += 1 }
    }

    /// Misst einen Arbeitsschritt (nur wenn er spürbar lang war, wird er gemerkt).
    @inline(__always)
    func measure<T>(_ label: String, _ work: () -> T) -> T {
        let start = CACurrentMediaTime()
        let r = work()
        let ms = (CACurrentMediaTime() - start) * 1000
        lastWork = label
        if ms > 4, ms > (slowest[label] ?? 0) { slowest[label] = ms }
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
        if gap > 50, gap < 1000 { // > 1 s = Tastatur war weg, kein Ruckler
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
