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
                self.status = "Verbunden ✓ – Die Tastatur nutzt jetzt dein ChatGPT-Abo. Du kannst zurück zu deiner App wechseln."
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
