import Foundation

enum OpenAIError: LocalizedError {
    case missingKey
    case http(Int, String)
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Kein OpenAI-API-Schlüssel hinterlegt. Öffne die App „Tastatur KI“ und trage deinen Schlüssel ein."
        case .http(let code, let msg):
            switch code {
            case 401: return "Der API-Schlüssel ist ungültig (401)."
            case 429: return "Limit erreicht oder kein Guthaben (429). \(msg)"
            default: return "OpenAI-Fehler \(code): \(msg)"
            }
        case .invalidResponse:
            return "Unerwartete Antwort von OpenAI."
        case .network(let msg):
            return "Netzwerkfehler: \(msg). Ist „Vollen Zugriff erlauben“ für die Tastatur aktiviert?"
        }
    }

    var isModelError: Bool {
        if case .http(let code, let msg) = self {
            let m = msg.lowercased()
            return (code == 400 || code == 404) && (m.contains("model") || m.contains("modell"))
        }
        return false
    }

    var isParameterError: Bool {
        if case .http(let code, let msg) = self {
            let m = msg.lowercased()
            return code == 400 && (m.contains("reasoning") || m.contains("unsupported") || m.contains("parameter"))
        }
        return false
    }
}

struct ChatMessage: Codable {
    var role: String
    var content: String
}

/// Schlanker OpenAI-Client ohne Abhängigkeiten.
final class OpenAIClient {
    let store: SharedStore

    init(store: SharedStore = .shared) {
        self.store = store
    }

    private var base: String {
        var b = store.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { b = "https://api.openai.com/v1" }
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }

    private var key: String { store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 180
        return URLSession(configuration: cfg)
    }()

    // MARK: - System-Prompt

    func systemPrompt(extra: String? = nil) -> String {
        var parts: [String] = []
        parts.append("""
        Du bist der KI-Assistent in einer Smartphone-Tastatur. Du bearbeitest Texte des Nutzers direkt im Eingabefeld.
        Regeln:
        - Gib AUSSCHLIESSLICH den fertigen Text zurück – keine Einleitung, keine Erklärung, keine Anführungszeichen, kein Markdown (außer der Nutzer will Listen).
        - Behalte die Sprache des Originaltextes bei, sofern nicht anders verlangt.
        - Erfinde keine Fakten.
        """)
        let personal = store.personalContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !personal.isEmpty { parts.append("Über den Nutzer:\n\(personal)") }
        let style = store.writingStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !style.isEmpty { parts.append("Schreibstil des Nutzers:\n\(style)") }
        if let profile = store.activeProfile, !profile.context.isEmpty {
            parts.append("Aktives Profil „\(profile.name)“:\n\(profile.context)")
        }
        if let extra, !extra.isEmpty { parts.append(extra) }
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEEE, dd.MM.yyyy HH:mm"
        parts.append("Aktuelles Datum: \(df.string(from: Date()))")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Chat

    func chat(messages: [ChatMessage], model: String? = nil, maxTokens: Int? = nil) async throws -> String {
        guard !key.isEmpty else { throw OpenAIError.missingKey }
        let model = (model ?? store.chatModel).trimmingCharacters(in: .whitespaces)
        do {
            return try await chatRequest(messages: messages, model: model, maxTokens: maxTokens, effort: store.reasoningEffort)
        } catch let error as OpenAIError where error.isParameterError {
            // Manche Modelle unterstützen reasoning_effort nicht → ohne erneut versuchen.
            return try await chatRequest(messages: messages, model: model, maxTokens: maxTokens, effort: nil)
        }
    }

    private func chatRequest(messages: [ChatMessage], model: String, maxTokens: Int?, effort: String?) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if let effort, !effort.isEmpty, effort != "standard", Self.isReasoningModel(model) {
            body["reasoning_effort"] = effort
        }
        if let maxTokens, !Self.isReasoningModel(model) {
            body["max_completion_tokens"] = maxTokens
        }
        let json = try await postJSON(path: "/chat/completions", body: body)
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isReasoningModel(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") || m.hasPrefix("gpt-5") || m.hasPrefix("gpt-6")
    }

    /// Wendet eine Anweisung auf einen Text an.
    func transform(text: String, instruction: String, appContext: String? = nil) async throws -> String {
        var user = "Anweisung: \(instruction)\n\nText:\n\(text)"
        if let appContext, !appContext.isEmpty {
            user = "Kontext (umgebender Text im Eingabefeld, nur zur Orientierung):\n\(appContext)\n\n" + user
        }
        let result = try await chat(messages: [
            ChatMessage(role: "system", content: systemPrompt()),
            ChatMessage(role: "user", content: user),
        ])
        return Self.cleanup(result)
    }

    /// Freie Frage / Text generieren.
    func compose(prompt: String, context: String?) async throws -> String {
        var user = prompt
        if let context, !context.isEmpty {
            user = "Bisheriger Text im Eingabefeld:\n\(context)\n\nAufgabe: \(prompt)"
        }
        let result = try await chat(messages: [
            ChatMessage(role: "system", content: systemPrompt(extra: "Der Nutzer gibt dir eine Aufgabe. Schreibe den Text, der direkt ins Eingabefeld eingefügt wird.")),
            ChatMessage(role: "user", content: user),
        ])
        return Self.cleanup(result)
    }

    /// Schnelle KI-Wortvorschläge (3 Fortsetzungen).
    func suggestions(context: String) async throws -> [String] {
        let result = try await chat(messages: [
            ChatMessage(role: "system", content: "Du bist eine Autovervollständigung für eine Tastatur. Gib genau 3 sehr kurze, wahrscheinliche Fortsetzungen (je 1–3 Wörter) für den Text des Nutzers zurück, eine pro Zeile, ohne Nummerierung, ohne Anführungszeichen. Wenn das letzte Wort unvollständig ist, vervollständige es zuerst."),
            ChatMessage(role: "user", content: String(context.suffix(400))),
        ], model: store.fastModel, maxTokens: 30)
        return result.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"„“-•0123456789. ")) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0) }
    }

    static func cleanup(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"", "\""), ("„", "“"), ("“", "”")] where t.hasPrefix(open) && t.hasSuffix(close) && t.count > 2 {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }

    // MARK: - Modelle

    func listModels() async throws -> [String] {
        guard !key.isEmpty else { throw OpenAIError.missingKey }
        var req = URLRequest(url: URL(string: base + "/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await perform(req)
        try check(resp, data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { throw OpenAIError.invalidResponse }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    // MARK: - Transkription

    func transcribe(fileURL: URL) async throws -> String {
        guard !key.isEmpty else { throw OpenAIError.missingKey }
        let preferred = store.transcribeModel.trimmingCharacters(in: .whitespaces)
        var candidates = [preferred]
        for fallback in ["gpt-transcribe", "gpt-4o-mini-transcribe", "whisper-1"] where !candidates.contains(fallback) {
            candidates.append(fallback)
        }
        var lastError: Error = OpenAIError.invalidResponse
        for model in candidates where !model.isEmpty {
            do {
                return try await transcribe(fileURL: fileURL, model: model)
            } catch let error as OpenAIError where error.isModelError {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private func transcribe(fileURL: URL, model: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: base + "/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("response_format", "json")
        let lang = store.dictationLanguage
        if !lang.isEmpty && lang != "auto" { field("language", lang) }
        let vocab = store.dictationVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.isEmpty { field("prompt", "Fachbegriffe und Namen: \(vocab)") }
        let audio = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await perform(req)
        try check(resp, data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else { throw OpenAIError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bereitet ein Diktat auf (Füllwörter, Satzzeichen, Absätze).
    func polishDictation(_ text: String) async throws -> String {
        let result = try await chat(messages: [
            ChatMessage(role: "system", content: systemPrompt(extra: """
            Du bekommst ein rohes Sprachdiktat. Bereinige es: entferne Füllwörter (äh, ähm, also, halt), korrigiere Satzzeichen, Groß-/Kleinschreibung und offensichtliche Erkennungsfehler.
            Setze gesprochene Befehle um („Punkt“, „Komma“, „neue Zeile“, „Absatz“, „Fragezeichen“) wenn sie eindeutig als Befehl gemeint sind.
            Wenn sich der Sprecher korrigiert („nein, ich meine…“), übernimm nur die korrigierte Version. Ändere sonst nichts am Inhalt.
            """)),
            ChatMessage(role: "user", content: text),
        ], model: store.fastModel)
        return Self.cleanup(result)
    }

    // MARK: - HTTP

    private func postJSON(path: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await perform(req)
        try check(resp, data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIError.invalidResponse
        }
        return json
    }

    private func perform(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch {
            throw OpenAIError.network(error.localizedDescription)
        }
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            var msg = String(data: data, encoding: .utf8) ?? ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let m = err["message"] as? String {
                msg = m
            }
            throw OpenAIError.http(http.statusCode, msg)
        }
    }
}
