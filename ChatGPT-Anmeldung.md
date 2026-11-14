# „Mit ChatGPT anmelden“ in einer iOS-App (Swift) – Anleitung + Code

Dieser Code stammt aus der App „Tastatur KI“. Er meldet den Nutzer mit seinem **ChatGPT-Konto** an
(OAuth 2.0 mit PKCE über die offizielle OpenAI-Anmeldeseite). Danach laufen KI-Anfragen über das
**ChatGPT-Abo** des Nutzers statt über einen bezahlten API-Schlüssel.

## So funktioniert der Ablauf

1. **PKCE vorbereiten:** zufälliger `code_verifier`, `state` und `nonce`. `code_challenge` = Base64URL(SHA256(verifier)).
2. **Lokaler Rückruf-Server:** Die App startet mit `NWListener` einen Mini-HTTP-Server auf `127.0.0.1:1455`
   (bei belegtem Port 1456–1462). Redirect-URI: `http://127.0.0.1:<port>/auth/callback`. OpenAI verlangt diese Loopback-Adresse.
3. **Anmeldeseite öffnen** mit `ASWebAuthenticationSession`:
   `https://auth.openai.com/api/accounts/authorize` mit den Parametern
   - `client_id` = beim ersten Mal `dynamic_agent_client`, danach die von OpenAI vergebene ID (`oaiapp_…`)
   - `ext_agent_host_id` = feste UUID dieser Installation (`urn:uuid:…`)
   - `response_type=code`, `redirect_uri`, `state`, `nonce`, `code_challenge`, `code_challenge_method=S256`
   - `scope` = `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`
   - `resource` = `https://api.openai.com/v1`
   - beim ersten Mal zusätzlich `agent_name_hint` = Name der App.

   Wichtig: `+` in der Query als `%2B` kodieren.
4. **Rückruf:** Der Browser ruft `http://127.0.0.1:<port>/auth/callback?code=…&state=…&client_id=…` auf.
   - `state` prüfen.
   - Bei der ersten Anmeldung kommt hier die **vergebene Client-ID** (`client_id`) mit. Sie wird gespeichert und später wiederverwendet.
   - Danach eine kleine HTML-Seite „Angemeldet ✓“ zurückgeben.
5. **Code gegen Tokens tauschen:** `POST https://auth.openai.com/api/accounts/oauth/token`
   (`application/x-www-form-urlencoded`) mit
   - `grant_type=authorization_code`, `client_id`, `code`, `code_verifier`, `redirect_uri`, `resource`.

   Zurück kommen `access_token`, `refresh_token`, `id_token` (JWT mit `email`, `sub`, `nonce`), `expires_in` und `scope`.
   - `nonce` im `id_token` prüfen.
   - Nur wenn der `scope` den Eintrag `chatgpt.tokens.use.direct` enthält, darf das Abo genutzt werden.
6. **Token erneuern** (läuft nach ca. 1 Stunde ab): `grant_type=refresh_token` an dieselbe Token-Adresse.
   - Refresh-Tokens sind nur **einmal** gültig. Deshalb gibt es immer nur eine Erneuerung gleichzeitig (Lock + gemeinsamer Task).
   - Den neuen Refresh-Token sofort speichern.
7. **KI-Anfragen:** `POST https://api.openai.com/v1/responses` mit `Authorization: Bearer <access_token>`.
   - Immer `"store": false` und `"stream": true` (Server-Sent Events: `response.output_text.delta`, `response.completed`, `response.failed`).
   - Systemtexte gehen in `instructions`.
   - Bei 401 einmal mit erneuertem Token wiederholen.
8. **Modelle:** `GET https://api.openai.com/v1/models` mit demselben Token. Liefert die Modelle, die das Abo freigibt.
9. **Abmelden:** Refresh-Token an den `revocation_endpoint` aus
   `https://auth.openai.com/.well-known/openid-configuration` schicken und die Sitzung löschen.

## Was an das eigene Projekt angepasst werden muss

- `SharedStore` ist der Einstellungsspeicher dieser App. Er wird genutzt für:
  - `defaults` (UserDefaults)
  - `containerURL` (Ordner zum Speichern)
  - `chatgptAccount`, `chatgptModels`, `chatgptModel`, `aiProvider`, `usesAppGroup`

  Durch den eigenen Speicher ersetzen.
- `OpenAIError` ist ein eigener Fehlertyp (`.network`, `.http(code, msg)`, `.empty`, `.invalidResponse`). Er lässt sich leicht nachbauen.
- `ChatMessage` hat die Felder `role` und `content`.
- Der „Kopplungscode“ (`transferCode`/`importTransferCode`) ist nur nötig, wenn zwei Prozesse sich die Anmeldung
  **nicht** über eine App Group teilen können (hier: App → Tastatur-Erweiterung). Für eine normale App kann er weg.
- Sicherheit: Passwort und 2FA gibt der Nutzer **nur** auf der Seite von OpenAI ein, nie in der App.
  Die Tokens werden als Datei mit `completeFileProtectionUntilFirstUserAuthentication` gespeichert. Die Schlüsselbund (Keychain) wäre noch besser.
- `Info.plist` braucht keine besonderen Einträge. `ASWebAuthenticationSession` braucht ein Fenster als `presentationAnchor`.

---

## 1. `ChatGPTAuth.swift` – Tokens, Erneuerung, Modelle, Abmelden

```swift
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

    // MARK: - Kopplungscode (App → Tastatur, falls keine App Group geteilt wird)

    static let transferPrefix = "tastaturki-chatgpt1:"

    private struct Transfer: Codable {
        var session: ChatGPTSession
        var models: [[String]]
        var model: String
    }

    static func isTransferCode(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(transferPrefix)
    }

    /// Erzeugt den Code, mit dem die Tastatur die Anmeldung übernimmt.
    static func transferCode(_ session: ChatGPTSession, models: [[String]], model: String) -> String? {
        guard let data = try? JSONEncoder().encode(Transfer(session: session, models: models, model: model)) else { return nil }
        return transferPrefix + data.base64EncodedString()
    }

    /// Übernimmt die Anmeldung aus einem Kopplungscode und speichert sie für diesen Prozess.
    @discardableResult
    static func importTransferCode(_ code: String, into store: SharedStore) -> Bool {
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix(transferPrefix),
              let data = Data(base64Encoded: String(t.dropFirst(transferPrefix.count))),
              let tr = try? JSONDecoder().decode(Transfer.self, from: data),
              !tr.session.refreshToken.isEmpty else { return false }
        save(tr.session)
        store.chatgptAccount = tr.session.email.isEmpty ? "ChatGPT-Konto" : tr.session.email
        if !tr.models.isEmpty { store.chatgptModels = tr.models }
        store.chatgptModel = tr.model.isEmpty ? (tr.models.first?.first ?? defaultModel) : tr.model
        store.aiProvider = "chatgpt"
        return true
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
```

## 2. `ChatGPTLogin.swift` – Anmeldeablauf (PKCE, lokaler Server, Browser)

```swift
import Foundation
import Network
import CryptoKit
import AuthenticationServices
import UIKit

/// „Mit ChatGPT anmelden“: OAuth mit PKCE über die offizielle OpenAI-Anmeldeseite.
/// Benutzername, Passwort und 2FA werden nur auf der Seite von OpenAI eingegeben – nie in dieser App.
/// Die Rückmeldung kommt über einen kleinen lokalen Server auf 127.0.0.1 (so verlangt es OpenAI).
@MainActor
final class ChatGPTLogin: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var busy = false
    @Published var status: String?
    @Published var ok = false

    private var listener: NWListener?
    private var session: ASWebAuthenticationSession?
    private var verifier = ""
    private var state = ""
    private var nonce = ""
    private var redirectURI = ""
    private var requestedClientID = ""
    private var finished = false

    // MARK: - Start

    func start() {
        guard !busy else { return }
        busy = true
        ok = false
        finished = false
        status = "Starte Anmeldung …"
        verifier = Self.randomURLSafe(48)
        state = Self.randomURLSafe(24)
        nonce = Self.randomURLSafe(24)
        startListener(ports: Array(1455...1462))
    }

    private func startListener(ports: [UInt16]) {
        guard let port = ports.first else {
            fail("Kein freier lokaler Port für die Anmeldung gefunden.")
            return
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        guard let l = try? NWListener(using: params) else {
            startListener(ports: Array(ports.dropFirst()))
            return
        }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.handle(conn) }
        }
        l.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                guard let self, self.listener === l else { return }
                switch st {
                case .ready:
                    self.redirectURI = "http://127.0.0.1:\(port)\(ChatGPTAuth.callbackPath)"
                    self.openBrowser()
                case .failed:
                    l.cancel()
                    self.listener = nil
                    self.startListener(ports: Array(ports.dropFirst()))
                default: break
                }
            }
        }
        l.start(queue: .main)
    }

    private func openBrowser() {
        let existing = ChatGPTAuth.issuedClientID
        requestedClientID = existing ?? "dynamic_agent_client"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: requestedClientID),
            URLQueryItem(name: "ext_agent_host_id", value: ChatGPTAuth.hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: ChatGPTAuth.scope),
            URLQueryItem(name: "resource", value: ChatGPTAuth.resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if existing == nil { items.append(URLQueryItem(name: "agent_name_hint", value: ChatGPTAuth.appName)) }
        var comps = URLComponents(string: ChatGPTAuth.authorizeURL)!
        comps.queryItems = items
        // „+“ und andere Sonderzeichen sicher kodieren
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = comps.url else { fail("Anmelde-Adresse ungültig."); return }

        status = "Melde dich bei OpenAI an …"
        // Das Rücksprung-Schema wird nie aufgerufen – der Code kommt über 127.0.0.1 an.
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "tastatur-auth") { [weak self] _, error in
            Task { @MainActor in
                guard let self, !self.finished else { return }
                if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    self.fail("Anmeldung abgebrochen.")
                } else {
                    self.fail(error?.localizedDescription ?? "Anmeldung beendet.")
                }
            }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        session = s
        if !s.start() { fail("Anmeldefenster konnte nicht geöffnet werden.") }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }

    // MARK: - Lokaler Rückruf

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { conn.cancel(); return }
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let firstLine = text.split(separator: "\r\n").first.map(String.init) ?? ""
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2, let comps = URLComponents(string: "http://127.0.0.1" + parts[1]),
                      comps.path == ChatGPTAuth.callbackPath else {
                    self.respond(conn, status: "404 Not Found", html: "")
                    return
                }
                let q = Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
                self.callback(q, conn: conn)
            }
        }
    }

    private func callback(_ q: [String: String], conn: NWConnection) {
        guard !finished else { respond(conn, status: "200 OK", html: Self.page("Bereits erledigt", "Du kannst dieses Fenster schließen.")); return }
        guard q["state"] == state else {
            respond(conn, status: "400 Bad Request", html: Self.page("Fehler", "Ungültige Anfrage (state)."))
            return
        }
        if let err = q["error"] {
            respond(conn, status: "200 OK", html: Self.page("Abgebrochen", "Die Anmeldung wurde nicht abgeschlossen."))
            fail(err == "access_denied" ? "Zustimmung abgelehnt – ohne sie kann das Abo nicht genutzt werden." : "Anmeldefehler: \(err) \(q["error_description"] ?? "")")
            return
        }
        guard let code = q["code"], !code.isEmpty else {
            respond(conn, status: "400 Bad Request", html: Self.page("Fehler", "Kein Anmelde-Code erhalten."))
            return
        }
        // Bei der ersten Anmeldung vergibt OpenAI hier die eigene Client-ID (oaiapp_…)
        var clientID = requestedClientID
        if let issued = q["client_id"], !issued.isEmpty, issued != "dynamic_agent_client" {
            if let existing = ChatGPTAuth.issuedClientID, existing != issued {
                respond(conn, status: "400 Bad Request", html: Self.page("Fehler", "Unerwartete Client-ID."))
                fail("Unerwartete Client-ID bei der Anmeldung.")
                return
            }
            clientID = issued
        }
        guard clientID != "dynamic_agent_client" else {
            respond(conn, status: "200 OK", html: Self.page("Fehler", "Registrierung unvollständig."))
            fail("Registrierung bei OpenAI unvollständig (keine Client-ID erhalten).")
            return
        }
        finished = true
        respond(conn, status: "200 OK", html: Self.page("Angemeldet ✓", "Zurück zu Tastatur KI …"))
        status = "Hole Zugang …"
        let verifier = self.verifier, redirect = self.redirectURI, nonce = self.nonce
        Task { @MainActor in
            do {
                let s = try await ChatGPTAuth.exchange(code: code, verifier: verifier, redirectURI: redirect, clientID: clientID, nonce: nonce)
                ChatGPTAuth.issuedClientID = clientID
                ChatGPTAuth.save(s)
                self.session?.cancel()
                self.stopListener()
                guard s.planUsageAllowed else {
                    self.fail(ChatGPTAuthError.planUsageMissing.localizedDescription)
                    return
                }
                let store = SharedStore.shared
                store.chatgptAccount = s.email.isEmpty ? "ChatGPT-Konto" : s.email
                store.aiProvider = "chatgpt"
                self.status = "Lade Modelle …"
                if let models = try? await ChatGPTAuth.fetchModels(), !models.isEmpty {
                    store.chatgptModels = models
                    if !models.contains(where: { $0[0] == store.chatgptModel }) { store.chatgptModel = models[0][0] }
                } else if store.chatgptModel.isEmpty {
                    store.chatgptModel = ChatGPTAuth.defaultModel
                }
                self.busy = false
                self.ok = true
                if self.copyTransferCode() {
                    self.status = "Verbunden ✓ – Kopplungscode kopiert. Öffne jetzt die Tastatur: Sie übernimmt den Code automatisch (oder ⚙︎ → KI & API → „Kopplungscode einfügen“)."
                } else {
                    self.status = "Verbunden ✓ – Die Tastatur nutzt jetzt dein ChatGPT-Abo."
                }
            } catch {
                self.session?.cancel()
                self.fail(error.localizedDescription)
            }
        }
    }

    private func respond(_ conn: NWConnection, status: String, html: String) {
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func fail(_ message: String) {
        stopListener()
        session = nil
        busy = false
        ok = false
        status = message
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Kopplung mit der Tastatur

    /// Ob ein Code kopiert werden kann (Anmeldung liegt in der App vor).
    var canCopyCode: Bool { ChatGPTAuth.load() != nil }

    /// Kopiert den Kopplungscode (läuft nach 10 Minuten aus, nur auf diesem Gerät).
    /// Ohne geteilte App Group übergibt die App die Anmeldung an die Tastatur und vergisst sie selbst –
    /// sonst würden beide denselben Erneuerungs-Token verbrauchen und sich gegenseitig abmelden.
    @discardableResult
    func copyTransferCode() -> Bool {
        let store = SharedStore.shared
        guard let session = ChatGPTAuth.load(),
              let code = ChatGPTAuth.transferCode(session, models: store.chatgptModels, model: store.chatgptModel) else {
            status = "Kein Code vorhanden – bitte neu anmelden."
            ok = false
            return false
        }
        UIPasteboard.general.setItems([["public.utf8-plain-text": code]], options: [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(600),
        ])
        if !store.usesAppGroup { ChatGPTAuth.clear() }
        objectWillChange.send()
        status = "Kopplungscode kopiert ✓ – jetzt die Tastatur öffnen, sie übernimmt ihn automatisch."
        ok = true
        return true
    }

    // MARK: - Abmelden

    func signOut() {
        let store = SharedStore.shared
        store.chatgptAccount = ""
        store.aiProvider = "apikey"
        status = "Abgemeldet."
        ok = false
        Task { await ChatGPTAuth.signOut() }
    }

    // MARK: - PKCE

    static func randomURLSafe(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func page(_ title: String, _ text: String) -> String {
        """
        <!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title><style>body{font-family:-apple-system,sans-serif;background:#111;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center}h1{font-size:28px}</style></head>
        <body><div><h1>\(title)</h1><p>\(text)</p></div></body></html>
        """
    }
}
```

## 3. Ausschnitt aus `OpenAIClient.swift` – Anfragen über das Abo (Responses-API, Streaming)

```swift
    // MARK: - ChatGPT-Abo (Responses-API mit Anmelde-Token)

    private static var planNoEffort = Set<String>()

    /// Anfrage über das ChatGPT-Abo: immer `store: false` und Streaming (so verlangt es OpenAI).
    private func chatGPTPlan(messages: [ChatMessage], effort: String, onPartial: ((String) -> Void)?) async throws -> String {
        var candidates: [String] = []
        let models = store.chatgptModels.compactMap(\.first)
        for m in [store.chatgptModel] + models + [ChatGPTAuth.defaultModel] where !m.isEmpty && !candidates.contains(m) {
            candidates.append(m)
        }
        var lastError: Error = OpenAIError.invalidResponse
        for model in candidates.prefix(4) {
            Self.lock.lock()
            let useEffort = !Self.planNoEffort.contains(model + "|" + effort)
            Self.lock.unlock()
            do {
                let r = try await planRequest(messages: messages, model: model, effort: useEffort ? effort : nil, onPartial: onPartial)
                guard !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenAIError.empty }
                return r
            } catch let error as OpenAIError where error.isModelError {
                lastError = error
                continue
            } catch let error as OpenAIError where error.isParameterError && useEffort {
                Self.lock.lock(); Self.planNoEffort.insert(model + "|" + effort); Self.lock.unlock()
                return try await planRequest(messages: messages, model: model, effort: nil, onPartial: onPartial)
            }
        }
        throw lastError
    }

    private func planRequest(messages: [ChatMessage], model: String, effort: String?, onPartial: ((String) -> Void)?, retried: Bool = false) async throws -> String {
        let token = try await ChatGPTAuth.validAccessToken(forceRefresh: retried)
        let instructions = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
        let input: [[String: Any]] = messages.filter { $0.role != "system" }.map { m in
            ["type": "message", "role": m.role == "assistant" ? "assistant" : "user", "content": m.content]
        }
        var body: [String: Any] = [
            "model": model,
            "input": input,
            "store": false,
            "stream": true,
        ]
        if !instructions.isEmpty { body["instructions"] = instructions }
        if let effort, !effort.isEmpty, effort != "standard", Self.isReasoningModel(model) {
            body["reasoning"] = ["effort": effort]
        }
        var req = URLRequest(url: URL(string: ChatGPTAuth.apiBase + "/responses")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let pair: (URLSession.AsyncBytes, URLResponse)
        do { pair = try await Self.session.bytes(for: req) } catch { throw OpenAIError.network(error.localizedDescription) }
        let (bytes, resp) = pair
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await b in bytes { data.append(b) }
            // Abgelaufenes Token: einmal erneuern und wiederholen
            if http.statusCode == 401, !retried {
                return try await planRequest(messages: messages, model: model, effort: effort, onPartial: onPartial, retried: true)
            }
            throw Self.planError(status: http.statusCode, data: data)
        }
        var text = ""
        var lastEmit = Date.distantPast
        var completed = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            switch type {
            case "response.output_text.delta":
                if let piece = json["delta"] as? String {
                    text += piece
                    if Date().timeIntervalSince(lastEmit) > 0.05 {
                        lastEmit = Date()
                        onPartial?(text)
                    }
                }
            case "response.completed":
                completed = true
            case "response.incomplete":
                completed = !text.isEmpty
            case "response.failed", "error":
                let err = ((json["response"] as? [String: Any])?["error"] as? [String: Any]) ?? (json["error"] as? [String: Any]) ?? json
                let code = err["code"] as? String ?? ""
                let msg = err["message"] as? String ?? "Anfrage fehlgeschlagen."
                throw OpenAIError.http(code == "subscription_sharing_usage_limit_exceeded" ? 429 : 400, ChatGPTAuth.message(forCode: code, fallback: msg))
            default:
                continue
            }
            if completed { break }
        }
        if !completed && text.isEmpty { throw OpenAIError.network("Verbindung zu ChatGPT unterbrochen") }
        onPartial?(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func planError(status: Int, data: Data) -> Error {
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let err = json["error"] as? [String: Any]
        let code = err?["code"] as? String ?? ""
        var msg = (err?["message"] as? String) ?? (json["detail"] as? String) ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
        if let param = err?["param"] as? String, !param.isEmpty { msg += " (\(param))" }
        if status == 401 { return ChatGPTAuthError.signInAgain(code.isEmpty ? "401" : code) }
        return OpenAIError.http(status, ChatGPTAuth.message(forCode: code, fallback: msg))
    }
```

## 4. Benutzung in SwiftUI (Beispiel)

```swift
struct LoginButton: View {
    @StateObject private var login = ChatGPTLogin()

    var body: some View {
        VStack {
            Button(login.busy ? "Anmeldung läuft …" : "Mit ChatGPT anmelden") { login.start() }
                .disabled(login.busy)
            if let s = login.status { Text(s).font(.footnote) }
        }
    }
}
```
