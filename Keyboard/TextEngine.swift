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
    private let language: String

    init() {
        let langs = UITextChecker.availableLanguages
        language = langs.first { $0.hasPrefix("de") } ?? "de_DE"
        learned = store.loadLearnedWords()
        bigrams = Self.loadBigrams()
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
        if result.count < limit + 1 {
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
        if let en = UITextChecker.availableLanguages.first(where: { $0.hasPrefix("en") }) {
            let missEN = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: en)
            if missEN.location == NSNotFound { return nil }
        }
        let guesses = checker.guesses(forWordRange: range, in: word, language: language) ?? []
        let maxDist = word.count <= 4 ? 1 : 2
        // Bevorzuge häufige Wörter
        let ranked = guesses.prefix(6).sorted { a, b in
            let ca = CommonWords.rank[a.lowercased()] ?? Int.max
            let cb = CommonWords.rank[b.lowercased()] ?? Int.max
            if ca != cb { return ca < cb }
            return false
        }
        for g in ranked {
            if g.contains(" ") { continue }
            if Self.distance(word.lowercased(), g.lowercased()) <= maxDist {
                return matchCase(of: word, g).replacingFirstCaseIfNoun(original: word, guess: g)
            }
        }
        return nil
    }

    // MARK: - Lernen

    func learn(word: String, previous: String?, weight: Int = 1) {
        guard store.learnWords, word.count >= 2, word.count <= 40,
              word.rangeOfCharacter(from: .letters) != nil else { return }
        learned[word, default: 0] += weight
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
        guard dirty > 0 else { return }
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
