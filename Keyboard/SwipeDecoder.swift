import UIKit

/// Gesten-Tippen: erkennt Wörter aus der Fingerbahn über die Tasten.
/// Bewertung: Form der Bahn (Vergleich mit der Ideal-Linie über die Tastenmitten),
/// Worthäufigkeit, gelernte Wörter und der Satzkontext.
/// Wortliste: Häufigkeitslisten aus „FrequencyWords“ (hermitdave, CC BY-SA 4.0), auf Deutsch + Englisch gekürzt.
final class SwipeDecoder {
    static let shared = SwipeDecoder()

    private var byEnds: [String: [(word: String, rank: Int)]] = [:]
    private var byLength: [Int: [(word: String, rank: Int)]] = [:]
    private var rankOf: [String: Int] = [:]
    private(set) var ready = false
    private var loading = false

    func loadIfNeeded() {
        guard !ready, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var map: [String: [(word: String, rank: Int)]] = [:]
            var lengths: [Int: [(word: String, rank: Int)]] = [:]
            var ranks: [String: Int] = [:]
            if let url = Bundle.main.url(forResource: "swipe-words", withExtension: "txt"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                var rank = 0
                text.enumerateLines { line, _ in
                    guard let f = line.first, let l = line.last else { return }
                    map[Self.endsKey(f, l), default: []].append((line, rank))
                    if line.count >= 2, line.count <= 18 { lengths[line.count, default: []].append((line, rank)) }
                    if ranks[line] == nil { ranks[line] = rank }
                    rank += 1
                }
            }
            DispatchQueue.main.async {
                self?.byLength = lengths
                self?.rankOf = ranks
                self?.byEnds = map
                self?.ready = true
                self?.loading = false
            }
        }
    }

    static func keyChar(_ c: Character) -> Character { c == "ß" ? "s" : c }

    /// Häufigkeitsrang eines Wortes (nil = unbekannt).
    func rank(of word: String) -> Int? { rankOf[word.lowercased()] }

    // MARK: Tipp-Korrektur über die echten Fingerpositionen

    /// Findet das Wort gleicher Länge, das am besten zu den getippten Punkten passt.
    /// Rückgabe: Wort, räumliche Kosten (Summe der quadrierten Abstände in Tastenbreiten) und Gesamtwert.
    func tapCorrect(typed: String, taps: [CGPoint], centers: [Character: CGPoint], kw: CGFloat,
                    learned: [String: Int], context: (String) -> Double) -> (word: String, spatial: Double, score: Double)? {
        let n = typed.count
        guard ready, n >= 2, taps.count == n, kw > 0 else { return nil }
        var pool = byLength[n] ?? []
        for (w, c) in learned where w.count == n && rankOf[w] == nil { pool.append((w, max(0, 3000 - c * 200))) }
        let limit = 3.2 + Double(n) * 0.25
        var best: (String, Double, Double)?
        for (word, rank) in pool {
            var cost = 0.0
            var i = 0
            var ok = true
            for ch in word {
                guard let c = centers[Self.keyChar(ch)] else { ok = false; break }
                let t = taps[i]
                // horizontal genauer als vertikal (Reihenhöhe > Tastenbreite)
                let dx = Double((t.x - c.x) / kw), dy = Double((t.y - c.y) / (kw * 1.45))
                cost += dx * dx + dy * dy
                if cost > limit { ok = false; break }
                i += 1
            }
            guard ok else { continue }
            let learnedBonus = learned[word].map { min(0.8, Double($0) * 0.1) } ?? 0
            let score = cost + log(Double(rank) + 2) * 0.22 - learnedBonus - context(word)
            if best == nil || score < best!.2 { best = (word, cost, score) }
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }
    static func endsKey(_ f: Character, _ l: Character) -> String { String(keyChar(f)) + String(keyChar(l)) }

    struct Input {
        var points: [CGPoint]
        var centers: [Character: CGPoint]
        var keyWidth: CGFloat
        /// Zusatzwörter (gelernt) mit Gewicht.
        var learned: [String: Int]
        /// Kontextbonus (z. B. Bigramm mit dem vorherigen Wort).
        var context: (String) -> Double
    }

    /// Liefert die besten Wörter (bestes zuerst) und die überstrichenen Tasten.
    func decode(_ input: Input, limit: Int = 5) -> (words: [String], keys: String) {
        let pts = input.points
        guard pts.count >= 2, !input.centers.isEmpty else { return ([], "") }
        let kw = max(input.keyWidth, 10)
        let keySeq = Self.keySequence(pts, input.centers)
        guard ready else { return ([], keySeq) }

        let starts = nearestKeys(pts.first!, input.centers, kw, max: 3)
        let ends = nearestKeys(pts.last!, input.centers, kw, max: 3)
        var pool: [(String, Int)] = []
        var seen = Set<String>()
        for s in starts {
            for e in ends {
                for item in byEnds[String(s) + String(e)] ?? [] where seen.insert(item.word).inserted {
                    pool.append((item.word, item.rank))
                }
            }
        }
        // Gelernte Wörter (auch Namen, Slang) zusätzlich
        for (w, count) in input.learned where count > 0 {
            let lw = w.lowercased()
            guard let f = lw.first, let l = lw.last, starts.contains(Self.keyChar(f)), ends.contains(Self.keyChar(l)),
                  seen.insert(lw).inserted else { continue }
            pool.append((lw, max(0, 3000 - count * 200)))
        }

        let userPath = Self.resample(pts, 32)
        let userLen = Self.length(pts)
        var scored: [(String, Double)] = []
        for (word, rank) in pool {
            let letters = Self.collapsed(word)
            guard letters.count <= keySeq.count + 2,
                  let ideal = idealPath(letters, input.centers),
                  Self.matchesInOrder(letters, pts, input.centers, tolerance: kw * 1.0) else { continue }
            let shape = Self.meanDistance(userPath, Self.resample(ideal, 32)) / kw
            let lengthPenalty = abs(log(Double((userLen + kw) / (Self.length(ideal) + kw)))) * 0.4
            let freq = log(Double(rank) + 2) * 0.11
            let learnedBonus = input.learned[word].map { min(0.5, Double($0) * 0.08) } ?? 0
            let score = shape + lengthPenalty + freq - learnedBonus - input.context(word)
            scored.append((word, score))
        }
        scored.sort { $0.1 < $1.1 }
        return (Array(scored.prefix(limit).map(\.0)), keySeq)
    }

    // MARK: Helfer

    private func nearestKeys(_ p: CGPoint, _ centers: [Character: CGPoint], _ kw: CGFloat, max n: Int) -> [Character] {
        let sorted = centers.map { ($0.key, hypot($0.value.x - p.x, $0.value.y - p.y)) }.sorted { $0.1 < $1.1 }
        guard let best = sorted.first else { return [] }
        return sorted.prefix(n).filter { $0.1 <= best.1 + kw * 0.55 }.map(\.0)
    }

    private func idealPath(_ letters: [Character], _ centers: [Character: CGPoint]) -> [CGPoint]? {
        var out: [CGPoint] = []
        for c in letters {
            guard let p = centers[c] else { return nil }
            out.append(p)
        }
        if out.count == 1 { out.append(out[0]) }
        return out
    }

    /// Buchstaben ohne direkte Doppelungen („hallo“ → h a l o), ß wie s.
    static func collapsed(_ word: String) -> [Character] {
        var out: [Character] = []
        for ch in word.lowercased() {
            let c = keyChar(ch)
            if out.last != c { out.append(c) }
        }
        return out
    }

    /// Jeder Buchstabe muss – in Reihenfolge – nahe an der Bahn liegen.
    static func matchesInOrder(_ letters: [Character], _ pts: [CGPoint], _ centers: [Character: CGPoint], tolerance: CGFloat) -> Bool {
        var i = 0
        for (n, c) in letters.enumerated() {
            guard let k = centers[c] else { return false }
            var found = false
            // Erster/letzter Buchstabe: großzügiger, weil Start/Ende ungenau sind
            let tol = (n == 0 || n == letters.count - 1) ? tolerance * 1.25 : tolerance
            while i < pts.count {
                if hypot(pts[i].x - k.x, pts[i].y - k.y) <= tol { found = true; break }
                i += 1
            }
            if !found { return false }
        }
        return true
    }

    static func keySequence(_ pts: [CGPoint], _ centers: [Character: CGPoint]) -> String {
        var out = ""
        for p in pts {
            guard let c = centers.min(by: { hypot($0.value.x - p.x, $0.value.y - p.y) < hypot($1.value.x - p.x, $1.value.y - p.y) })?.key else { continue }
            if out.last != c { out.append(c) }
        }
        return out
    }

    static func resample(_ pts: [CGPoint], _ n: Int) -> [CGPoint] {
        guard pts.count > 1 else { return Array(repeating: pts.first ?? .zero, count: n) }
        var total: CGFloat = 0
        for i in 1..<pts.count { total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        guard total > 0 else { return Array(repeating: pts[0], count: n) }
        let step = total / CGFloat(n - 1)
        var out = [pts[0]]
        var acc: CGFloat = 0
        var prev = pts[0]
        var i = 1
        while i < pts.count, out.count < n {
            let cur = pts[i]
            let d = hypot(cur.x - prev.x, cur.y - prev.y)
            if acc + d >= step, d > 0 {
                let t = (step - acc) / d
                let q = CGPoint(x: prev.x + t * (cur.x - prev.x), y: prev.y + t * (cur.y - prev.y))
                out.append(q)
                prev = q
                acc = 0
            } else {
                acc += d
                prev = cur
                i += 1
            }
        }
        while out.count < n { out.append(pts[pts.count - 1]) }
        return out
    }

    static func length(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<pts.count { total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        return total
    }

    static func meanDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 99 }
        var sum: CGFloat = 0
        for i in 0..<n { sum += hypot(a[i].x - b[i].x, a[i].y - b[i].y) }
        return Double(sum / CGFloat(n))
    }
}
