import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var state: KeyboardState?
    private var host: UIHostingController<KeyboardRootView>!
    private var heightConstraint: NSLayoutConstraint?
    private var lastLandscape: Bool?

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
        state.onHeightChange = { [weak self] h in self?.setHeight(h) }
        setHeight(state.totalHeight)
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
