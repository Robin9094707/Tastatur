import UIKit
import SwiftUI
import Combine

final class KeyboardViewController: UIInputViewController {
    private var state: KeyboardState?
    private var host: UIHostingController<KeyboardRootView>!
    private var heightConstraint: NSLayoutConstraint?
    private var lastLandscape: Bool?
    /// Tastenfeld direkt im Controller – wie bei der Apple-Tastatur kein SwiftUI dazwischen.
    /// So kann keine SwiftUI-Geste Berührungen verzögern, abbrechen oder schlucken.
    private let keysView = KeysView()
    private var keysTop: NSLayoutConstraint?
    private var keysLeading: NSLayoutConstraint?
    private var keysTrailing: NSLayoutConstraint?
    private var subscriptions = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        GlassConfig.lightweight = true
        let state = KeyboardState(controller: self)
        self.state = state
        let root = KeyboardRootView(state: state)
        host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // Tastenfeld über die SwiftUI-Ebene legen (dort ist an dieser Stelle nur der Hintergrund)
        keysView.translatesAutoresizingMaskIntoConstraints = false
        keysView.bind(to: state)
        view.addSubview(keysView)
        let top = keysView.topAnchor.constraint(equalTo: view.topAnchor, constant: state.toolbarHeight)
        let lead = keysView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let trail = keysView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        NSLayoutConstraint.activate([top, lead, trail, keysView.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        keysTop = top; keysLeading = lead; keysTrailing = trail
        // Sichtbar nur ohne Panel (bzw. mit Schnellleiste)
        state.$panel
            .sink { [weak self] p in self?.updateKeysVisibility(p) }
            .store(in: &subscriptions)
        // Leistenhöhe ändert sich z. B. im Eingabe-Modus
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncKeysFrame() }
            .store(in: &subscriptions)
        state.onHeightChange = { [weak self] h in
            self?.setHeight(h)
            self?.syncKeysFrame()
        }
        setHeight(state.totalHeight)
    }

    private func updateKeysVisibility(_ p: Panel) {
        let show = p == .none || p == .tools
        guard show == keysView.isHidden else { return }
        if show {
            keysView.alpha = 0
            keysView.isHidden = false
            UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { self.keysView.alpha = 1 }
        } else {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState], animations: { self.keysView.alpha = 0 }) { done in
                if done, let s = self.state, !(s.panel == .none || s.panel == .tools) { self.keysView.isHidden = true }
            }
        }
    }

    private func syncKeysFrame() {
        guard let state else { return }
        let t = state.toolbarHeight
        if keysTop?.constant != t { keysTop?.constant = t }
        let side = state.sideInset
        if keysLeading?.constant != side { keysLeading?.constant = side }
        if keysTrailing?.constant != -side { keysTrailing?.constant = -side }
    }

    /// Hält Höhe und seitliche Ränder aktuell – wichtig beim Drehen ins Querformat.
    private func updateLayoutMetrics() {
        guard let state else { return }
        if lastLandscape != state.isLandscape {
            lastLandscape = state.isLandscape
            state.objectWillChange.send() // SwiftUI-Höhen neu berechnen
        }
        let h = state.totalHeight
        if heightConstraint?.constant != h { setHeight(h) }
        let insets = view.window?.safeAreaInsets ?? view.safeAreaInsets
        var side = max(insets.left, insets.right, view.safeAreaInsets.left, view.safeAreaInsets.right)
        if state.isLandscape && !state.isPad {
            // Wie bei der Apple-Tastatur: im Querformat etwas Abstand zu den runden Ecken
            side = max(side, 44)
        } else {
            side = 0
        }
        if abs(state.sideInset - side) > 0.5 { state.sideInset = side }
        syncKeysFrame()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateLayoutMetrics()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateLayoutMetrics()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updateLayoutMetrics()
        }, completion: { [weak self] _ in
            self?.updateLayoutMetrics()
            self?.view.setNeedsLayout()
        })
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Speicher freigeben, damit iOS die Tastatur nicht beendet
        URLCache.shared.removeAllCachedResponses()
        state?.handleMemoryWarning()
    }

    private func setHeight(_ h: CGFloat) {
        if let c = heightConstraint {
            c.constant = h
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: h)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyAppearance()
        state?.appear()
    }

    /// Übernimmt Hell/Dunkel des Textfelds – wie die iOS-Tastatur.
    private func applyAppearance() {
        let style: UIUserInterfaceStyle
        switch textDocumentProxy.keyboardAppearance {
        case .dark?: style = .dark
        case .light?: style = .light
        default: style = .unspecified
        }
        if view.overrideUserInterfaceStyle != style { view.overrideUserInterfaceStyle = style }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // iOS verzögert Berührungen am Bildschirmrand (System-Gesten). Für eine Tastatur
        // bremst das die untere Reihe – deshalb abschalten, wie bei der Apple-Tastatur.
        disableTouchDelays()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.disableTouchDelays() }
        state?.setHostApp(bundleID: hostBundleID())
    }

    /// Versucht, die App zu erkennen, in der getippt wird. Apple hat das ab iOS 26.4 gesperrt –
    /// dort wird es gar nicht erst versucht (manuelle Auswahl in der Tastatur).
    private func hostBundleID() -> String? {
        if #available(iOS 26.4, *) { return nil }
        let sel = NSSelectorFromString("_hostBundleID")
        let candidates: [NSObject] = [self, parent].compactMap { $0 }
        for obj in candidates where obj.responds(to: sel) {
            guard let value = obj.perform(sel)?.takeUnretainedValue() as? String else { continue }
            if !value.isEmpty, value != "<null>" { return value }
        }
        return nil
    }

    private func disableTouchDelays() {
        keysView.disableAncestorTouchDelays()
        var v: UIView? = view
        while let current = v {
            current.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false; $0.delaysTouchesEnded = false }
            v = current.superview
        }
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false; $0.delaysTouchesEnded = false }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        state?.disappear()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        applyAppearance()
        state?.textDidChange()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        state?.textDidChange()
    }

    /// Öffnet eine URL aus der Tastatur heraus (z. B. die App für Einstellungen).
    func openURL(_ url: URL) {
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:options:completionHandler:")
        while let r = responder {
            if r.responds(to: selector), r is UIApplication || NSStringFromClass(type(of: r)).contains("UIApplication") {
                typealias OpenFn = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let imp = r.method(for: selector)
                let fn = unsafeBitCast(imp, to: OpenFn.self)
                fn(r, selector, url as NSURL, NSDictionary(), nil)
                return
            }
            responder = r.next
        }
        // Fallback für ältere Systeme
        extensionContext?.open(url, completionHandler: nil)
    }
}
