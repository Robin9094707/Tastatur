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
            let toks: [String: Int] = Self.loadJSON("tokens.json") ?? [:]
            let tris: [String: [String: Int]] = Self.loadJSON("trigrams.json") ?? [:]
            DispatchQueue.main.async {
                guard let self else { return }
                // bereits in dieser Sitzung Gelerntes behalten
                for (k, v) in words { self.learned[k, default: 0] += v }
                for (k, v) in grams { self.bigrams[k] = (self.bigrams[k] ?? [:]).merging(v, uniquingKeysWith: +) }
                for (k, v) in toks { self.tokens[k, default: 0] += v }
                for (k, v) in tris { self.trigrams[k] = (self.trigrams[k] ?? [:]).merging(v, uniquingKeysWith: +) }
                self.loaded = true
                self.rebuildLearnedIndex()
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

    /// Schnelle Variante für den Tipp-Moment (nur Speicher-Abfragen, nie das Systemwörterbuch).
    /// nil = unbekannt → wird in der nächsten Tipp-Pause im Hintergrund nachgeschlagen.
    func isPlausiblePrefixFast(_ prefix: String) -> Bool? {
        let p = prefix.lowercased()
        if p.count <= 1 { return true }
        if prefixes.contains(p) { return true }
        if let c = plausibleCache[p] { return c }
        if SwipeDecoder.shared.hasWord(withPrefix: p) == true { return true }
        if pendingPlausible.count < 24, !pendingPlausible.contains(p) { pendingPlausible.append(p) }
        return nil
    }

    private var pendingPlausible: [String] = []

    /// In Tipp-Pausen: offene Präfix-Fragen mit dem Systemwörterbuch klären (wenige pro Pause).
    func warmPendingPrefixes(max n: Int = 4) {
        guard !pendingPlausible.isEmpty else { return }
        let batch = pendingPlausible.prefix(n)
        pendingPlausible.removeFirst(batch.count)
        for p in batch { _ = isPlausiblePrefix(p) }
    }

    /// Kann `prefix` der Anfang eines echten Wortes sein?
    func isPlausiblePrefix(_ prefix: String) -> Bool {
        let p = prefix.lowercased()
        if p.count <= 1 { return true }
        if prefixes.contains(p) { return true }
        if let c = plausibleCache[p] { return c }
        if SwipeDecoder.shared.hasWord(withPrefix: p) == true { return true }
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
        // 2. Gelernte Wörter nach Häufigkeit (nur der Anfangsbuchstaben-Topf, nicht alle Wörter)
        if let first = lower.first, let bucket = learnedIndex[first] {
            var hits: [(String, Int)] = []
            for (w, lw) in bucket where lw.hasPrefix(lower) && lw.count > lower.count {
                hits.append((w, learned[w] ?? 0))
            }
            for (w, _) in hits.sorted(by: { $0.1 > $1.1 }).prefix(4) { add(w) }
        }
        // 3. Häufige deutsche Wörter (Liste ist nach Häufigkeit sortiert)
        for w in CommonWords.german where w.lowercased().hasPrefix(lower) && w.count > prefix.count {
            add(w)
            if result.count >= limit + 1 { break }
        }
        // 4. Große Wortliste (nach Häufigkeit, Binärsuche – sehr schnell)
        if result.count < limit + 1, lower.count >= 2 {
            for w in SwipeDecoder.shared.completions(prefix: lower, limit: limit + 1) {
                add(casedCached(w))
                if result.count >= limit + 1 { break }
            }
        }
        // 5. Systemwörterbuch (nur wenn sonst nichts passt, mit Zwischenspeicher)
        if result.count < limit, warmedUp {
            let comps: [String]
            if let c = systemCompletionCache[lower] {
                comps = c
            } else {
                let ns = prefix as NSString
                comps = Array((checker.completions(forPartialWordRange: NSRange(location: 0, length: ns.length), in: prefix, language: language) ?? [])
                    .sorted(by: { $0.count < $1.count }).prefix(6))
                if systemCompletionCache.count > 400 { systemCompletionCache.removeAll() }
                systemCompletionCache[lower] = comps
            }
            for w in comps { add(w) }
        }
        return result.prefix(limit).map { matchCase(of: prefix, $0) }
    }

    func predictions(after previousWord: String?, prev2: String? = nil, limit: Int) -> [String] {
        var result: [String] = []
        if let p1 = previousWord?.lowercased(), let p2 = prev2?.lowercased(), let next = trigrams[p2 + " " + p1] {
            for (w, c) in next.sorted(by: { $0.value > $1.value }) where c >= 2 && result.count < limit { result.append(w) }
        }
        if let prev = previousWord?.lowercased(), let next = bigrams[prev] {
            for (w, _) in next.sorted(by: { $0.value > $1.value }) where result.count < limit && !result.contains(w) { result.append(w) }
        }
        return result
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

    /// Zusätzliche bekannte Wörter (z. B. Namen aus den Kontakten) – werden nie autokorrigiert.
    private var extraKnown = Set<String>()
    func setExtraKnown(_ words: Set<String>) {
        extraKnown = words
        correctionCache.removeAll()
    }

    func isKnown(_ word: String) -> Bool {
        let lower = word.lowercased()
        if extraKnown.contains(lower) { return true }
        if learned[word] != nil || learned[lower] != nil { return true }
        if lexiconWords.contains(lower) { return true }
        if CommonWords.set.contains(lower) { return true }
        return false
    }

    /// Zwischenspeicher: Die Korrektur wird meist schon in der Tipp-Pause berechnet – beim Leerzeichen ist sie dann sofort da.
    private var correctionCache: [String: String?] = [:]
    private var systemCompletionCache: [String: [String]] = [:]

    func correction(for word: String) -> String? {
        if let c = correctionCache[word] { return c }
        let r = correctionUncached(for: word)
        if correctionCache.count > 600 { correctionCache.removeAll() }
        correctionCache[word] = .some(r)
        return r
    }

    /// Richtige Großschreibung (Nomen) für Vorschläge aus der Wortliste – zwischengespeichert.
    private var casedCache: [String: String] = [:]
    private func casedCached(_ word: String) -> String {
        if let c = casedCache[word] { return c }
        let r = swipeCased(word)
        if casedCache.count > 800 { casedCache.removeAll() }
        casedCache[word] = r
        return r
    }

    // MARK: - Index der gelernten Wörter (nach Anfangsbuchstabe, klein)

    private var learnedIndex: [Character: [String: String]] = [:]

    private func rebuildLearnedIndex() {
        var idx: [Character: [String: String]] = [:]
        for w in learned.keys {
            let lw = w.lowercased()
            if let f = lw.first { idx[f, default: [:]][w] = lw }
        }
        learnedIndex = idx
    }

    private func correctionUncached(for word: String) -> String? {
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

    // MARK: - Gesten-Tippen

    private var swipeLearnedCache: [String: Int]?
    private var learnsSinceCache = 0

    /// Gelernte Wörter (klein) für das Wischen – nur mehrfach benutzte.
    func swipeLearned() -> [String: Int] {
        if let c = swipeLearnedCache { return c }
        var out: [String: Int] = [:]
        for (w, c) in learned where c >= 2 && w.count >= 2 {
            out[w.lowercased(), default: 0] += c
        }
        swipeLearnedCache = out
        return out
    }

    private var spelledCache: [String: Bool] = [:]

    /// Richtig geschrieben laut Systemwörterbuch (Deutsch oder Englisch)? Mit Zwischenspeicher.
    func spelledCorrectly(_ word: String) -> Bool {
        if let c = spelledCache[word] { return c }
        let r = spelledCorrectlyUncached(word)
        if spelledCache.count > 1500 { spelledCache.removeAll() }
        spelledCache[word] = r
        return r
    }

    private func spelledCorrectlyUncached(_ word: String) -> Bool {
        let ns = word as NSString
        let range = NSRange(location: 0, length: ns.length)
        if checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language).location == NSNotFound { return true }
        if !warmedUp { warmUp() }
        if let en = englishLanguage,
           checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: en).location == NSNotFound { return true }
        return false
    }

    func casedLike(_ typed: String, _ word: String) -> String { matchCase(of: typed, word) }

    /// Wörter, die auf `prev` folgten (klein) – als Kopie für Hintergrund-Berechnungen.
    func bigramNext(_ prev: String) -> [String: Int] {
        guard let next = bigrams[prev.lowercased()] else { return [:] }
        var out: [String: Int] = [:]
        for (w, c) in next { out[w.lowercased(), default: 0] += c }
        return out
    }

    func bigramCount(_ prev: String, _ word: String) -> Int {
        guard let next = bigrams[prev.lowercased()] else { return 0 }
        var total = 0
        for (w, c) in next where w.lowercased() == word { total += c }
        return total
    }

    /// Richtige Schreibweise für ein gewischtes Wort (Nomen groß, gelernte Namen).
    func swipeCased(_ word: String) -> String {
        let cap = word.prefix(1).uppercased() + word.dropFirst()
        let capCount = learned[cap] ?? 0
        let lowCount = learned[word] ?? 0
        if capCount >= 3, capCount > lowCount * 2 { return cap }
        if CommonWords.german.contains(cap) { return cap }
        if CommonWords.set.contains(word), CommonWords.german.contains(word) { return word }
        // Systemwörterbuch: klein falsch, groß richtig → Nomen
        let ns = word as NSString
        let lowWrong = checker.rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: ns.length), startingAt: 0, wrap: false, language: language).location != NSNotFound
        if lowWrong {
            let capNS = cap as NSString
            let capWrong = checker.rangeOfMisspelledWord(in: cap, range: NSRange(location: 0, length: capNS.length), startingAt: 0, wrap: false, language: language).location != NSNotFound
            if !capWrong { return cap }
        }
        return word
    }

    // MARK: - Lernen

    func learn(word: String, previous: String?, weight: Int = 1) {
        guard store.learnWords, word.count >= 2, word.count <= 40,
              word.rangeOfCharacter(from: .letters) != nil else { return }
        let isNew = learned[word] == nil
        learned[word, default: 0] += weight
        if isNew {
            let lw = word.lowercased()
            if let f = lw.first { learnedIndex[f, default: [:]][word] = lw }
            correctionCache.removeAll()
        }
        // Zwischenspeicher fürs Wischen nur ab und zu neu bauen (spart Arbeit bei jedem Wort)
        learnsSinceCache += 1
        if learnsSinceCache > 25 || (swipeLearnedCache != nil && learned[word] == weight) { swipeLearnedCache = nil; learnsSinceCache = 0 }
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
        // Dreier-Folgen: „ich bin gleich“ → „da“
        if let prev = previous?.lowercased(), history.count >= 2, history[history.count - 1].lowercased() == prev {
            let key = history[history.count - 2].lowercased() + " " + prev
            trigrams[key, default: [:]][word, default: 0] += weight
            if let c = trigrams[key]?.count, c > 20 {
                let top = trigrams[key]!.sorted { $0.value > $1.value }.prefix(12)
                trigrams[key] = Dictionary(uniqueKeysWithValues: top.map { ($0.key, $0.value) })
            }
        }
        if previous == nil { history.removeAll() }
        history.append(word)
        if history.count > 3 { history.removeFirst() }
        dirty += 1
        if dirty >= 15 { save() }
    }

    // MARK: - Persönliche Einträge (E-Mail, Links, Nummern, @Namen)

    private var tokens: [String: Int] = [:]
    private var trigrams: [String: [String: Int]] = [:]
    private var history: [String] = []

    static func isPersonalToken(_ t: String) -> Bool {
        guard t.count >= 4, t.count <= 120, !t.contains(" ") else { return false }
        let lower = t.lowercased()
        if lower.range(of: #"^[^@\s]+@[^@\s]+\.[a-z]{2,}$"#, options: .regularExpression) != nil { return true } // E-Mail
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") { return true }
        if lower.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(/\S*)?$"#, options: .regularExpression) != nil { return true } // Domain
        if t.hasPrefix("@") && t.count >= 3 { return true } // @Name
        let digits = t.filter(\.isNumber).count
        if digits >= 6, t.allSatisfy({ $0.isNumber || "+-/() ".contains($0) }) { return true } // Telefon
        if digits >= 2, t.rangeOfCharacter(from: .letters) != nil, t.count >= 6, t.allSatisfy({ $0.isLetter || $0.isNumber || "-_.".contains($0) }) {
            return true // z. B. Kennungen, Kundennummern
        }
        return false
    }

    func learnToken(_ t: String) {
        guard store.learnWords, store.learnPersonal, Self.isPersonalToken(t) else { return }
        tokens[t, default: 0] += 1
        if tokens.count > 400 {
            tokens = Dictionary(uniqueKeysWithValues: tokens.sorted { $0.value > $1.value }.prefix(300).map { ($0.key, $0.value) })
        }
        dirty += 1
        if dirty >= 15 { save() }
    }

    /// Persönliche Einträge, die zum angefangenen Text passen.
    func tokenCompletions(prefix: String, limit: Int = 2) -> [String] {
        guard prefix.count >= 2 else { return [] }
        let lp = prefix.lowercased()
        return tokens
            .filter { $0.key.lowercased().hasPrefix(lp) && $0.key.count > prefix.count && ($0.value >= 2 || prefix.count >= 3) }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    var allTokens: [(String, Int)] { tokens.sorted { $0.value > $1.value }.map { ($0.key, $0.value) } }

    func forgetToken(_ t: String) {
        tokens[t] = nil
        dirty += 1
        save(force: true)
    }

    private static func loadJSON<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: SharedStore.containerURL.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func saveJSON<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: SharedStore.containerURL.appendingPathComponent(name), options: .atomic)
        }
    }

    func save(force: Bool = false) {
        guard (dirty > 0 || force), loaded else { return }
        dirty = 0
        if learned.count > 5000 {
            learned = Dictionary(uniqueKeysWithValues: learned.sorted { $0.value > $1.value }.prefix(4000).map { ($0.key, $0.value) })
            rebuildLearnedIndex()
        }
        if bigrams.count > 3000 {
            bigrams = Dictionary(uniqueKeysWithValues: bigrams.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }.prefix(2500).map { ($0.key, $0.value) })
        }
        if trigrams.count > 3000 {
            trigrams = Dictionary(uniqueKeysWithValues: trigrams.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }.prefix(2500).map { ($0.key, $0.value) })
        }
        // Schreiben im Hintergrund – blockiert das Tippen nicht
        let w = learned, b = bigrams, t = tokens, tr = trigrams
        let store = self.store
        DispatchQueue.global(qos: .utility).async {
            store.saveLearnedWords(w)
            Self.saveBigrams(b)
            Self.saveJSON(t, "tokens.json")
            Self.saveJSON(tr, "trigrams.json")
        }
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
