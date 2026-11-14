import Foundation

/// Gespeicherte Anmeldung für „Sign in with ChatGPT“ (KI über das ChatGPT-Abo).
struct ChatGPTSession: Codable {
    var clientID: String
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var expiresAt: Date
    var scope: String
    var email: String
    var subject: String

    var planUsageAllowed: Bool { scope.split(separator: " ").contains("chatgpt.tokens.use.direct") }
}

enum ChatGPTAuthError: LocalizedError {
    case notSignedIn
    case planUsageMissing
    case signInAgain(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Nicht mit ChatGPT angemeldet. Öffne die App und tippe auf „Mit ChatGPT anmelden“."
        case .planUsageMissing: return "Die Berechtigung „ChatGPT-Abo nutzen“ wurde nicht erteilt. Bitte erneut anmelden und zustimmen."
        case .signInAgain(let m): return "ChatGPT-Anmeldung abgelaufen – bitte in der App neu anmelden. (\(m))"
        case .server(let m): return m
        }
    }
}

/// Token-Verwaltung für das ChatGPT-Abo. Wird von App (Anmeldung) und Tastatur (Nutzung) verwendet.
enum ChatGPTAuth {
    static let authorizeURL = "https://auth.openai.com/api/accounts/authorize"
    static let tokenURL = "https://auth.openai.com/api/accounts/oauth/token"
    static let discoveryURL = "https://auth.openai.com/.well-known/openid-configuration"
    static let resource = "https://api.openai.com/v1"
    static let apiBase = "https://api.openai.com/v1"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let callbackPath = "/auth/callback"
    static let appName = "Tastatur KI"
    static let defaultModel = "gpt-6.1-sol"

    private static var fileURL: URL { SharedStore.containerURL.appendingPathComponent("chatgpt-session.json") }
    private static let lock = NSLock()
    private static var refreshTask: Task<ChatGPTSession, Error>?

    // MARK: - Dauerhafte Werte

    /// Stabile Kennung dieser Installation (vom Dienst als „Host“ verlangt) – kein Geheimnis.
    static var hostID: String {
        let d = SharedStore.shared.defaults
        if let id = d.string(forKey: "chatgptHostID"), !id.isEmpty { return id }
        let id = "urn:uuid:" + UUID().uuidString.lowercased()
        d.set(id, forKey: "chatgptHostID")
        return id
    }

    /// Bei der ersten Anmeldung von OpenAI vergebene Client-ID (oaiapp_…), wird wiederverwendet.
    static var issuedClientID: String? {
        get { SharedStore.shared.defaults.string(forKey: "chatgptClientID") }
        set { SharedStore.shared.defaults.set(newValue, forKey: "chatgptClientID") }
    }

    // MARK: - Speichern / Laden

    static func load() -> ChatGPTSession? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ChatGPTSession.self, from: data)
    }

    static func save(_ session: ChatGPTSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Token-Austausch

    /// Tauscht den Anmelde-Code gegen Tokens (nach dem Browser-Login).
    static func exchange(code: String, verifier: String, redirectURI: String, clientID: String, nonce: String) async throws -> ChatGPTSession {
        let json = try await tokenRequest([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "resource": resource,
        ])
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else {
            throw ChatGPTAuthError.server("Unerwartete Antwort beim Anmelden.")
        }
        let idToken = json["id_token"] as? String ?? ""
        let claims = decodeJWT(idToken)
        if let n = claims["nonce"] as? String, n != nonce {
            throw ChatGPTAuthError.server("Sicherheitsprüfung fehlgeschlagen (nonce).")
        }
        if let exp = claims["exp"] as? Double, Date(timeIntervalSince1970: exp) < Date().addingTimeInterval(-300) {
            throw ChatGPTAuthError.server("Anmelde-Token ist abgelaufen.")
        }
        let session = ChatGPTSession(
            clientID: clientID,
            accessToken: access,
            refreshToken: refresh,
            idToken: idToken,
            expiresAt: Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600),
            scope: json["scope"] as? String ?? scope,
            email: claims["email"] as? String ?? "",
            subject: claims["sub"] as? String ?? ""
        )
        return session
    }

    /// Gültiges Zugangs-Token – erneuert es bei Bedarf automatisch (Tokens laufen nach 1 Stunde ab).
    static func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let session = load() else { throw ChatGPTAuthError.notSignedIn }
        guard session.planUsageAllowed else { throw ChatGPTAuthError.planUsageMissing }
        if !forceRefresh, session.expiresAt.timeIntervalSinceNow > 120 { return session.accessToken }
        return try await refreshed(staleToken: session.accessToken).accessToken
    }

    /// Erneuert die Tokens – nur eine Erneuerung gleichzeitig (Refresh-Tokens sind nur einmal gültig).
    private static func refreshed(staleToken: String) async throws -> ChatGPTSession {
        lock.lock()
        if let task = refreshTask {
            lock.unlock()
            return try await task.value
        }
        let task = Task<ChatGPTSession, Error> {
            // Vielleicht hat der andere Prozess (App/Tastatur) schon erneuert
            guard let current = load() else { throw ChatGPTAuthError.notSignedIn }
            if current.accessToken != staleToken, current.expiresAt.timeIntervalSinceNow > 120 { return current }
            do {
                let json = try await tokenRequest([
                    "grant_type": "refresh_token",
                    "client_id": current.clientID,
                    "refresh_token": current.refreshToken,
                    "resource": resource,
                ])
                guard let access = json["access_token"] as? String else { throw ChatGPTAuthError.server("Token-Erneuerung fehlgeschlagen.") }
                var next = current
                next.accessToken = access
                if let r = json["refresh_token"] as? String, !r.isEmpty { next.refreshToken = r }
                if let id = json["id_token"] as? String, !id.isEmpty { next.idToken = id }
                if let sc = json["scope"] as? String, !sc.isEmpty { next.scope = sc }
                next.expiresAt = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
                save(next)
                return next
            } catch ChatGPTAuthError.signInAgain(let msg) {
                // Der andere Prozess hat evtl. parallel erneuert – dann dessen Token nehmen
                if let other = load(), other.refreshToken != current.refreshToken { return other }
                throw ChatGPTAuthError.signInAgain(msg)
            }
        }
        refreshTask = task
        lock.unlock()
        defer { lock.lock(); refreshTask = nil; lock.unlock() }
        return try await task.value
    }

    private static let fatalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
        "refresh_token_invalidated", "refresh_token_reused",
    ]

    private static func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = formEncode(fields).data(using: .utf8)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch {
            throw OpenAIError.network(error.localizedDescription)
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let code = (json["error"] as? String) ?? ((json["error"] as? [String: Any])?["code"] as? String) ?? ""
            let desc = (json["error_description"] as? String) ?? ((json["error"] as? [String: Any])?["message"] as? String)
                ?? (json["detail"] as? String) ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
            if fatalRefreshErrors.contains(code) { throw ChatGPTAuthError.signInAgain(code) }
            throw ChatGPTAuthError.server("Anmeldefehler \(status): \(code.isEmpty ? desc : code + " – " + desc)")
        }
        return json
    }

    // MARK: - Abmelden

    static func signOut() async {
        let session = load()
        clear()
        guard let session else { return }
        // Refresh-Token widerrufen (best effort)
        var endpoint = "https://auth.openai.com/oauth/revoke"
        if let (data, _) = try? await URLSession.shared.data(from: URL(string: discoveryURL)!),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rev = json["revocation_endpoint"] as? String {
            endpoint = rev
        }
        guard let url = URL(string: endpoint) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncode([
            "token": session.refreshToken,
            "token_type_hint": "refresh_token",
            "client_id": session.clientID,
        ]).data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Modelle

    /// Modelle, die das Abo freigibt: [[slug, Anzeigename]] in der Reihenfolge des Servers.
    static func fetchModels() async throws -> [[String]] {
        let token = try await validAccessToken()
        var req = URLRequest(url: URL(string: apiBase + "/models")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatGPTAuthError.server("Modelle konnten nicht geladen werden (\(status)).")
        }
        let list = (json["models"] as? [[String: Any]]) ?? (json["data"] as? [[String: Any]]) ?? []
        return list.compactMap { m in
            let slug = (m["slug"] as? String) ?? (m["id"] as? String)
            guard let slug else { return nil }
            if let vis = m["visibility"] as? String, vis != "list" { return nil }
            return [slug, (m["display_name"] as? String) ?? slug]
        }
    }

    // MARK: - Fehlertexte

    /// Übersetzt bekannte Fehlercodes des Abo-Zugangs in verständliche Hinweise.
    static func message(forCode code: String, fallback: String) -> String {
        switch code {
        case "subscription_sharing_usage_limit_exceeded":
            return "Dein ChatGPT-Nutzungslimit ist erreicht. Später erneut versuchen (ChatGPT → Einstellungen → Nutzung)."
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            return "Der ChatGPT-Abo-Zugang ist gerade nicht verfügbar. Bitte gleich nochmal versuchen."
        case "subscription_sharing_user_not_eligible":
            return "Für dein Konto ist die Abo-Nutzung in anderen Apps nicht freigeschaltet (Plan oder Region)."
        case "subscription_sharing_unsupported_capability":
            return "Diese Funktion wird über das ChatGPT-Abo nicht unterstützt. (\(fallback))"
        case "subscription_sharing_invalid_user":
            return "ChatGPT-Anmeldung ungültig – bitte in der App neu anmelden."
        default:
            return fallback
        }
    }

    // MARK: - Helfer

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
    }

    /// Liest die Nutzdaten eines JWT (ohne Signaturprüfung – nur für Anzeige/nonce).
    static func decodeJWT(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }
}
