import UIKit

/// Lokale Autovervollständigung + Autokorrektur. Arbeitet komplett offline.
final class TextEngine {
    private let checker = UITextChecker()
    private let store = SharedStore.shared
    private var learned: [String: Int] = [:]
    private var bigrams: [String: [String: Int]] = [:]
    private var lexicon: [String: String] = [:]   // Textersetzungen aus iOS + Kontakte
    private var lexiconWords = Set<String>()
    private var dirty = 0
    private var language: String
    private var loaded = false

    private var englishLanguage: String?
    private var warmedUp = false

    init() {
        language = "de_DE"
        // Gelernte Wörter im Hintergrund laden – die Tastatur erscheint sofort.
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let words = store.loadLearnedWords()
            let grams = Self.loadBigrams()
            DispatchQueue.main.async {
                guard let self else { return }
                // bereits in dieser Sitzung Gelerntes behalten
                for (k, v) in words { self.learned[k, default: 0] += v }
                for (k, v) in grams { self.bigrams[k] = (self.bigrams[k] ?? [:]).merging(v, uniquingKeysWith: +) }
                self.loaded = true
                self.buildPrefixes()
            }
        }
    }

    // MARK: - Präfixe für intelligente Trefferzonen

    private var prefixes = Set<String>()
    private var plausibleCache: [String: Bool] = [:]

    private func buildPrefixes() {
        let words = CommonWords.german + Array(learned.keys)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var set = Set<String>()
            for w in words {
                let lw = w.lowercased()
                var p = ""
                for ch in lw.prefix(16) { p.append(ch); set.insert(p) }
            }
            DispatchQueue.main.async { self?.prefixes.formUnion(set) }
        }
    }

    /// Kann `prefix` der Anfang eines echten Wortes sein?
    func isPlausiblePrefix(_ prefix: String) -> Bool {
        let p = prefix.lowercased()
        if p.count <= 1 { return true }
        if prefixes.contains(p) { return true }
        if let c = plausibleCache[p] { return c }
        if !warmedUp { warmUp() }
        let ns = p as NSString
        let range = NSRange(location: 0, length: ns.length)
        var ok = !(checker.completions(forPartialWordRange: range, in: p, language: language) ?? []).isEmpty
        if !ok {
            ok = checker.rangeOfMisspelledWord(in: p, range: range, startingAt: 0, wrap: false, language: language).location == NSNotFound
        }
        if plausibleCache.count > 3000 { plausibleCache.removeAll() }
        plausibleCache[p] = ok
        return ok
    }

    func isLearned(_ word: String) -> Bool {
        learned[word] != nil || learned[word.lowercased()] != nil
    }

    /// Lädt das Systemwörterbuch einmalig vor (erste Abfrage ist sonst spürbar langsam).
    func warmUp() {
        guard !warmedUp else { return }
        warmedUp = true
        let langs = UITextChecker.availableLanguages
        language = langs.first { $0.hasPrefix("de") } ?? "de_DE"
        englishLanguage = langs.first { $0.hasPrefix("en") }
        _ = checker.rangeOfMisspelledWord(in: "hallo", range: NSRange(location: 0, length: 5), startingAt: 0, wrap: false, language: language)
    }

    func setLexicon(_ lex: UILexicon) {
        for entry in lex.entries {
            if entry.userInput != entry.documentText {
                lexicon[entry.userInput.lowercased()] = entry.documentText
            }
            lexiconWords.insert(entry.documentText.lowercased())
        }
    }

    /// iOS-Textersetzung (Einstellungen → Tastatur → Textersetzung)
    func textReplacement(for word: String) -> String? {
        lexicon[word.lowercased()]
    }

    // MARK: - Vorschläge

    func completions(prefix: String, previousWord: String?, limit: Int = 3) -> [String] {
        if prefix.isEmpty {
            return predictions(after: previousWord, limit: limit)
        }
        let lower = prefix.lowercased()
        var result: [String] = []
        func add(_ w: String) {
            guard result.count < limit + 2 else { return }
            if !result.contains(where: { $0.lowercased() == w.lowercased() }) { result.append(w) }
        }

        // 1. Bigramm-Treffer mit passendem Präfix
        if let prev = previousWord?.lowercased(), let next = bigrams[prev] {
            for (w, _) in next.sorted(by: { $0.value > $1.value }) where w.lowercased().hasPrefix(lower) && w.count > prefix.count {
                add(w)
            }
        }
        // 2. Gelernte Wörter nach Häufigkeit
        for (w, _) in learned.filter({ $0.key.lowercased().hasPrefix(lower) && $0.key.count > prefix.count }).sorted(by: { $0.value > $1.value }).prefix(4) {
            add(w)
        }
        // 3. Häufige deutsche Wörter (Liste ist nach Häufigkeit sortiert)
        for w in CommonWords.german where w.lowercased().hasPrefix(lower) && w.count > prefix.count {
            add(w)
            if result.count >= limit + 1 { break }
        }
        // 4. Systemwörterbuch
        if result.count < limit + 1, warmedUp {
            let ns = prefix as NSString
            let comps = checker.completions(forPartialWordRange: NSRange(location: 0, length: ns.length), in: prefix, language: language) ?? []
            for w in comps.sorted(by: { $0.count < $1.count }).prefix(6) { add(w) }
        }
        return result.prefix(limit).map { matchCase(of: prefix, $0) }
    }

    func predictions(after previousWord: String?, limit: Int) -> [String] {
        guard let prev = previousWord?.lowercased(), let next = bigrams[prev], !next.isEmpty else {
            return []
        }
        return next.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    private func matchCase(of prefix: String, _ word: String) -> String {
        guard let first = prefix.first else { return word }
        if prefix.count > 1, prefix == prefix.uppercased(), prefix.rangeOfCharacter(from: .letters) != nil {
            return word.uppercased()
        }
        if first.isUppercase {
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        return word
    }

    // MARK: - Autokorrektur

    func isKnown(_ word: String) -> Bool {
        let lower = word.lowercased()
        if learned[word] != nil || learned[lower] != nil { return true }
        if lexiconWords.contains(lower) { return true }
        if CommonWords.set.contains(lower) { return true }
        return false
    }

    func correction(for word: String) -> String? {
        guard word.count >= 2,
              word.rangeOfCharacter(from: .decimalDigits) == nil,
              word.rangeOfCharacter(from: CharacterSet.letters.inverted.subtracting(CharacterSet(charactersIn: "-'"))) == nil,
              !isKnown(word) else { return nil }
        if word.count > 1, word == word.uppercased() { return nil } // Abkürzungen
        let ns = word as NSString
        let range = NSRange(location: 0, length: ns.length)
        let miss = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language)
        guard miss.location != NSNotFound else { return nil }
        // Auch im Englischen korrekt? Dann nicht korrigieren.
        if !warmedUp { warmUp() }
        if let en = englishLanguage {
            let missEN = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: en)
            if missEN.location == NSNotFound { return nil }
        }
        let guesses = checker.guesses(forWordRange: range, in: word, language: language) ?? []
        let maxDist: Double = word.count <= 4 ? 1 : 2
        let lw = word.lowercased()
        var best: (String, Double, Int)?
        for g in guesses.prefix(8) where !g.contains(" ") {
            let d = Self.keyboardDistance(lw, g.lowercased())
            guard d <= maxDist else { continue }
            let rank = CommonWords.rank[g.lowercased()] ?? Int.max
            if best == nil || d < best!.1 - 0.01 || (abs(d - best!.1) < 0.01 && rank < best!.2) {
                best = (g, d, rank)
            }
        }
        if let best {
            return matchCase(of: word, best.0).replacingFirstCaseIfNoun(original: word, guess: best.0)
        }
        return nil
    }

    // MARK: - Lernen

    func learn(word: String, previous: String?, weight: Int = 1) {
        guard store.learnWords, word.count >= 2, word.count <= 40,
              word.rangeOfCharacter(from: .letters) != nil else { return }
        learned[word, default: 0] += weight
        var p = ""
        for ch in word.lowercased().prefix(16) { p.append(ch); prefixes.insert(p) }
        if let prev = previous?.lowercased(), !prev.isEmpty {
            bigrams[prev, default: [:]][word, default: 0] += weight
            if let count = bigrams[prev]?.count, count > 30 {
                // nur die häufigsten behalten
                let top = bigrams[prev]!.sorted { $0.value > $1.value }.prefix(20)
                bigrams[prev] = Dictionary(uniqueKeysWithValues: top.map { ($0.key, $0.value) })
            }
        }
        dirty += 1
        if dirty >= 15 { save() }
    }

    func save() {
        guard dirty > 0, loaded else { return }
        dirty = 0
        if learned.count > 5000 {
            learned = Dictionary(uniqueKeysWithValues: learned.sorted { $0.value > $1.value }.prefix(4000).map { ($0.key, $0.value) })
        }
        if bigrams.count > 3000 {
            bigrams = Dictionary(uniqueKeysWithValues: bigrams.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }.prefix(2500).map { ($0.key, $0.value) })
        }
        store.saveLearnedWords(learned)
        Self.saveBigrams(bigrams)
    }

    private static var bigramURL: URL { SharedStore.containerURL.appendingPathComponent("bigrams.json") }

    private static func loadBigrams() -> [String: [String: Int]] {
        guard let data = try? Data(contentsOf: bigramURL),
              let dict = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else { return [:] }
        return dict
    }

    private static func saveBigrams(_ b: [String: [String: Int]]) {
        if let data = try? JSONEncoder().encode(b) { try? data.write(to: bigramURL, options: .atomic) }
    }

    // MARK: - Tastatur-gewichtete Distanz

    /// Nachbartasten auf QWERTZ – Vertipper dorthin kosten weniger.
    private static let neighbors: [Character: Set<Character>] = {
        let rows: [[Character]] = [Array("qwertzuiopü"), Array("asdfghjklöä"), Array("yxcvbnm")]
        var map: [Character: Set<Character>] = [:]
        for (r, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() {
                var n = Set<Character>()
                if i > 0 { n.insert(row[i - 1]) }
                if i < row.count - 1 { n.insert(row[i + 1]) }
                // Versatz der Reihen wie auf dem iPhone (QWERTZ)
                let shifts: [(Int, [Int])] = r == 0 ? [(1, [-1, 0])] : (r == 1 ? [(0, [0, 1]), (2, [-2, -1])] : [(1, [1, 2])])
                for (rr, offs) in shifts {
                    let other = rows[rr]
                    for o in offs where i + o >= 0 && i + o < other.count { n.insert(other[i + o]) }
                }
                map[ch] = n
            }
        }
        map["ä"]?.insert("a"); map["ö"]?.insert("o"); map["ü"]?.insert("u")
        map["a"]?.insert("ä"); map["o"]?.insert("ö"); map["u"]?.insert("ü"); map["s"]?.insert("ß")
        return map
    }()

    static func keyboardDistance(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return Double(b.count) }
        if b.isEmpty { return Double(a.count) }
        var prev = (0...b.count).map { Double($0) }
        var cur = [Double](repeating: 0, count: b.count + 1)
        var prevPrev = prev
        for i in 1...a.count {
            cur[0] = Double(i)
            for j in 1...b.count {
                let sub: Double
                if a[i - 1] == b[j - 1] { sub = 0 }
                else if neighbors[a[i - 1]]?.contains(b[j - 1]) == true { sub = 0.5 }
                else { sub = 1 }
                var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + sub)
                // Buchstabendreher (z. B. „dei“ → „die“)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { v = min(v, prevPrev[j - 2] + 0.5) }
                cur[j] = v
            }
            prevPrev = prev
            prev = cur
        }
        return prev[b.count]
    }

    // MARK: - Levenshtein

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}

private extension String {
    /// Deutsche Substantive bleiben groß, auch wenn der Nutzer klein getippt hat.
    func replacingFirstCaseIfNoun(original: String, guess: String) -> String {
        if let f = guess.first, f.isUppercase, let o = original.first, o.isLowercase {
            return guess
        }
        return self
    }
}
