import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var state: KeyboardState?
    private var host: UIHostingController<KeyboardRootView>!
    private var heightConstraint: NSLayoutConstraint?

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
