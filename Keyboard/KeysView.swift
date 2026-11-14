import UIKit
import SwiftUI
import Combine

enum KeyKind: Equatable {
    case char(String)
    case shift, delete, space, returnKey, numbers, letters, symbols, globe, emoji
}

/// Konfiguration, die von SwiftUI an die UIKit-Tasten übergeben wird.
struct KeysConfig: Equatable {
    var layer: KeyboardLayer
    var shift: ShiftState
    var returnTitle: String
    var needsGlobe: Bool
    var numberRow: Bool
    var tintIndex: Int
    var popups: Bool
    var keyOpacity: CGFloat = 1
    var cornerRadius: CGFloat = 8.5
    var fontScale: CGFloat = 1
    var forceDark: Bool? = nil
    var style: String = "glass"
    var keyColorHex: String = "#FFFFFF"
    var textColorHex: String = ""
    var fontDesign: String = "default"
    var hideUmlauts: Bool = false
}

// MARK: - Einzelne Taste

final class KeyCapView: UIView {
    let kind: KeyKind
    var cellFrame: CGRect = .zero
    private let cap = UIView()
    private let label = UILabel()
    private let icon = UIImageView()
    private(set) var isPressed = false
    var tint: UIColor = .systemIndigo

    init(kind: KeyKind) {
        self.kind = kind
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        cap.layer.cornerRadius = 8.5
        cap.layer.cornerCurve = .continuous
        cap.layer.shadowColor = UIColor.black.cgColor
        cap.layer.shadowOffset = CGSize(width: 0, height: 1)
        cap.layer.shadowRadius = 0
        cap.layer.shadowOpacity = 0.3
        addSubview(cap)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        cap.addSubview(label)
        icon.contentMode = .center
        icon.tintColor = .label
        cap.addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    var isSpecial: Bool {
        switch kind {
        case .char, .space: return false
        default: return true
        }
    }

    var capFrameInParent: CGRect { cap.frame.offsetBy(dx: frame.minX, dy: frame.minY) }

    override func layoutSubviews() {
        super.layoutSubviews()
        cap.frame = bounds.insetBy(dx: 3, dy: 5.5)
        if isCapsule { cap.layer.cornerRadius = min(cap.bounds.height, cap.bounds.width) / 2 }
        cap.layer.shadowPath = UIBezierPath(roundedRect: cap.bounds, cornerRadius: cap.layer.cornerRadius).cgPath
        label.frame = cap.bounds.insetBy(dx: 2, dy: 0)
        icon.frame = cap.bounds
    }

    func configure(config: KeysConfig, dark: Bool) {
        let upper = config.layer == .letters && config.shift != .off
        label.isHidden = false
        icon.isHidden = true
        label.textColor = .label
        let sym = UIImage.SymbolConfiguration(pointSize: 18 * config.fontScale, weight: .regular)
        let fs = config.fontScale
        if !isCapsule, cap.layer.cornerRadius != config.cornerRadius {
            cap.layer.cornerRadius = config.cornerRadius
            setNeedsLayout()
        }
        switch kind {
        case .char(let c):
            label.text = upper ? c.uppercased() : c
            label.font = KeyStyleKit.font(size: (c.count > 1 ? 17 : 24) * fs, weight: .regular, design: config.fontDesign)
        case .shift:
            showIcon(config.shift == .caps ? "capslock.fill" : (config.shift == .on ? "shift.fill" : "shift"), sym)
        case .delete:
            showIcon(isPressed ? "delete.left.fill" : "delete.left", sym)
        case .space:
            label.text = "Leerzeichen"
            label.font = KeyStyleKit.font(size: 15 * fs, weight: .regular, design: config.fontDesign)
        case .returnKey:
            if config.returnTitle == "⏎" {
                showIcon("return", sym)
            } else {
                label.text = config.returnTitle
                label.font = KeyStyleKit.font(size: 16 * fs, weight: .semibold, design: config.fontDesign)
            }
        case .numbers:
            label.text = "123"; label.font = KeyStyleKit.font(size: 16 * fs, weight: .regular, design: config.fontDesign)
        case .letters:
            label.text = "ABC"; label.font = KeyStyleKit.font(size: 16 * fs, weight: .regular, design: config.fontDesign)
        case .symbols:
            label.text = "#+="; label.font = KeyStyleKit.font(size: 16 * fs, weight: .regular, design: config.fontDesign)
        case .globe:
            showIcon("globe", sym)
        case .emoji:
            showIcon("face.smiling", sym)
        }
        applyColors(config: config, dark: dark)
    }

    private func showIcon(_ name: String, _ cfg: UIImage.SymbolConfiguration) {
        label.isHidden = true
        icon.isHidden = false
        icon.image = UIImage(systemName: name, withConfiguration: cfg)
    }

    private var lastConfig: KeysConfig?
    private var lastDark = false

    private var cachedColors: KeyColors?
    private var cachedKey = ""

    func applyColors(config: KeysConfig, dark: Bool) {
        lastConfig = config
        lastDark = dark
        let style = KeyStyle(rawValue: config.style) ?? .glass
        let cacheKey = "\(config.style)|\(dark)|\(config.tintIndex)|\(config.keyColorHex)|\(config.textColorHex)|\(config.keyOpacity)"
        let colors: KeyColors
        if let c = cachedColors, cachedKey == cacheKey {
            colors = c
        } else {
            colors = KeyStyleKit.colors(style: style, dark: dark, tint: tint,
                                        keyColor: Theme.uiColor(hex: config.keyColorHex),
                                        textColor: config.textColorHex.isEmpty ? nil : Theme.uiColor(hex: config.textColorHex),
                                        opacity: config.keyOpacity)
            cachedColors = colors
            cachedKey = cacheKey
        }
        let wantsCapsule = colors.capsule
        if wantsCapsule != isCapsule {
            isCapsule = wantsCapsule
            setNeedsLayout()
        }
        cap.layer.shadowColor = colors.shadowColor.cgColor
        cap.layer.shadowOpacity = colors.shadowOpacity
        cap.layer.shadowRadius = colors.shadowRadius
        cap.layer.shadowOffset = CGSize(width: 0, height: colors.shadowOffsetY)
        cap.layer.borderColor = colors.border.cgColor
        cap.layer.borderWidth = colors.borderWidth

        var textColor = isSpecial ? colors.specialText : colors.text
        if case .returnKey = kind, config.returnTitle != "⏎" {
            cap.backgroundColor = tint.withAlphaComponent(isPressed ? 0.6 : 0.95)
            textColor = .white
        } else if case .shift = kind, config.shift != .off {
            cap.backgroundColor = isPressed ? colors.fillPressed : (style == .neon ? tint.withAlphaComponent(0.5) : UIColor.white)
            textColor = style == .neon ? .white : .black
        } else if isSpecial {
            cap.backgroundColor = isPressed ? colors.specialFillPressed : colors.specialFill
        } else {
            cap.backgroundColor = isPressed ? colors.fillPressed : colors.fill
        }
        label.textColor = textColor
        icon.tintColor = textColor
        if style == .neon {
            label.layer.shadowColor = tint.cgColor
            label.layer.shadowRadius = 4
            label.layer.shadowOpacity = 0.9
            label.layer.shadowOffset = .zero
        } else if label.layer.shadowOpacity != 0 {
            label.layer.shadowOpacity = 0
        }
    }

    private var isCapsule = false

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        if case .delete = kind {
            icon.image = UIImage(systemName: pressed ? "delete.left.fill" : "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))
        }
        // Schneller Pfad: nur die Füllfarbe tauschen (keine Farb-/Schatten-Neuberechnung pro Tipp).
        // Drücken sofort, Loslassen mit kurzem Ausblenden – wie bei der iOS-Tastatur.
        let apply = { [weak self] in
            guard let self else { return }
            if let c = self.lastConfig, let colors = self.cachedColors { self.applyFill(colors, c) } else if let c = self.lastConfig { self.applyColors(config: c, dark: self.lastDark) }
        }
        if pressed {
            cap.layer.removeAnimation(forKey: "backgroundColor")
            apply()
        } else {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut], animations: apply)
        }
    }

    private func applyFill(_ colors: KeyColors, _ config: KeysConfig) {
        let style = KeyStyle(rawValue: config.style) ?? .glass
        if case .returnKey = kind, config.returnTitle != "⏎" {
            cap.backgroundColor = tint.withAlphaComponent(isPressed ? 0.6 : 0.95)
        } else if case .shift = kind, config.shift != .off {
            cap.backgroundColor = isPressed ? colors.fillPressed : (style == .neon ? tint.withAlphaComponent(0.5) : UIColor.white)
        } else if isSpecial {
            cap.backgroundColor = isPressed ? colors.specialFillPressed : colors.specialFill
        } else {
            cap.backgroundColor = isPressed ? colors.fillPressed : colors.fill
        }
    }

    /// Nur Groß-/Kleinschreibung wechseln (Umschalttaste) – ohne Farben, Schriften und Schatten neu zu setzen.
    func updateShift(config: KeysConfig, dark: Bool) {
        switch kind {
        case .char(let c):
            let upper = config.layer == .letters && config.shift != .off
            label.text = upper ? c.uppercased() : c
            lastConfig = config
        default:
            configure(config: config, dark: dark)
        }
    }
}

// MARK: - Vorschau-Ballon

final class KeyPopupView: UIView {
    private let label = UILabel()
    private let bg = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        bg.layer.cornerRadius = 10
        bg.layer.cornerCurve = .continuous
        bg.layer.shadowColor = UIColor.black.cgColor
        bg.layer.shadowOpacity = 0.3
        bg.layer.shadowRadius = 5
        bg.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(bg)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 34, weight: .regular)
        bg.addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(text: String, above capFrame: CGRect, dark: Bool, in container: CGRect) {
        label.text = text
        label.textColor = .label
        bg.backgroundColor = dark ? UIColor(white: 0.42, alpha: 1) : .white
        let w = max(capFrame.width + 16, 48)
        let h: CGFloat = 54
        var x = capFrame.midX - w / 2
        x = min(max(x, container.minX + 2), container.maxX - w - 2)
        let newFrame = CGRect(x: x, y: capFrame.minY - h - 4, width: w, height: h)
        // Ohne Animationen umsetzen und Schattenform vorgeben – sonst rechnet die GPU den Schatten bei jedem Tipp neu
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frame.size != newFrame.size {
            frame = newFrame
            bg.frame = CGRect(origin: .zero, size: newFrame.size)
            label.frame = bg.bounds
            bg.layer.shadowPath = UIBezierPath(roundedRect: bg.bounds, cornerRadius: bg.layer.cornerRadius).cgPath
        } else {
            frame = newFrame
        }
        isHidden = false
        CATransaction.commit()
    }

    func hide() { isHidden = true }
}

// MARK: - Akzent-Auswahl

final class AlternatesView: UIView {
    private(set) var options: [String] = []
    private var labels: [UILabel] = []
    private let bg = UIView()
    private(set) var selectedIndex = 0
    var tint: UIColor = .systemIndigo
    private let cellWidth: CGFloat = 40

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        bg.layer.cornerRadius = 12
        bg.layer.cornerCurve = .continuous
        bg.layer.shadowColor = UIColor.black.cgColor
        bg.layer.shadowOpacity = 0.35
        bg.layer.shadowRadius = 6
        bg.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(bg)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(options: [String], above capFrame: CGRect, dark: Bool, in container: CGRect) {
        self.options = options
        labels.forEach { $0.removeFromSuperview() }
        labels = options.map { o in
            let l = UILabel()
            l.text = o
            l.textAlignment = .center
            l.font = .systemFont(ofSize: 26)
            l.layer.cornerRadius = 8
            l.layer.cornerCurve = .continuous
            l.clipsToBounds = true
            bg.addSubview(l)
            return l
        }
        bg.backgroundColor = dark ? UIColor(white: 0.32, alpha: 1) : .white
        let w = CGFloat(options.count) * cellWidth + 8
        let h: CGFloat = 52
        var x = capFrame.midX - cellWidth / 2 - 4
        x = min(max(x, container.minX + 2), container.maxX - w - 2)
        frame = CGRect(x: x, y: capFrame.minY - h - 4, width: w, height: h)
        bg.frame = CGRect(origin: .zero, size: frame.size)
        bg.layer.shadowPath = UIBezierPath(roundedRect: bg.bounds, cornerRadius: bg.layer.cornerRadius).cgPath
        for (i, l) in labels.enumerated() {
            l.frame = CGRect(x: 4 + CGFloat(i) * cellWidth, y: 4, width: cellWidth, height: h - 8)
        }
        select(0)
        isHidden = false
    }

    func update(touchX: CGFloat) {
        let local = touchX - frame.minX - 4
        let idx = Int(floor(local / cellWidth))
        select(min(max(idx, 0), options.count - 1))
    }

    private func select(_ i: Int) {
        selectedIndex = i
        for (j, l) in labels.enumerated() {
            l.backgroundColor = j == i ? tint : .clear
            l.textColor = j == i ? .white : .label
        }
    }

    var selected: String? { options.indices.contains(selectedIndex) ? options[selectedIndex] : nil }
}

// MARK: - Tastenfeld

/// Komplettes Tastenfeld in UIKit: schnelles Multitouch, keine toten Zonen, Vorschau-Ballons.
final class KeysView: UIView {
    weak var state: KeyboardState?
    var cancellables = Set<AnyCancellable>()
    private var config: KeysConfig?
    private var keys: [KeyCapView] = []
    private var rowsSpec: [[(KeyKind, Width)]] = []
    private let popup = KeyPopupView()
    private let alternates = AlternatesView()
    var rowHeight: CGFloat = 52

    private final class TouchInfo {
        var key: KeyCapView
        var startPoint: CGPoint
        /// Zeitpunkt des Aufsetzens – kurze, schnelle Tipps werden nie als Wischen/Cursor gedeutet.
        let startTime = CACurrentMediaTime()
        var age: CFTimeInterval { CACurrentMediaTime() - startTime }
        var longPressTimer: Timer?
        var alternatesActive = false
        var cursorMode = false
        var cursorStep = 0
        var handled = false
        // Gesten-Tippen
        var path: [CGPoint] = []
        var pathLength: CGFloat = 0
        var swiping = false
        init(key: KeyCapView, startPoint: CGPoint) { self.key = key; self.startPoint = startPoint; path = [startPoint] }
    }
    private let trail = CAShapeLayer()
    private let trailGlow = CAShapeLayer()
    private var touches: [ObjectIdentifier: TouchInfo] = [:]
    private var touchOrder: [ObjectIdentifier] = []

    enum Width { case units(CGFloat), flex }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        clipsToBounds = false
        backgroundColor = .clear
        alternates.isHidden = true
        for l in [trailGlow, trail] {
            l.fillColor = UIColor.clear.cgColor
            l.lineCap = .round
            l.lineJoin = .round
            l.zPosition = 50
            layer.addSublayer(l)
        }
        trail.lineWidth = 5
        trailGlow.lineWidth = 14
    }

    required init?(coder: NSCoder) { fatalError() }

    private var dark: Bool { traitCollection.userInterfaceStyle == .dark }

    func apply(_ c: KeysConfig, rowHeight: CGFloat) {
        let structural = config == nil || c.layer != config!.layer || c.needsGlobe != config!.needsGlobe || c.numberRow != config!.numberRow || c.hideUmlauts != config!.hideUmlauts
        let changed = c != config || rowHeight != self.rowHeight
        let oldConfig = config, oldRowHeight = self.rowHeight
        self.rowHeight = rowHeight
        config = c
        let style: UIUserInterfaceStyle = c.forceDark.map { $0 ? .dark : .light } ?? .unspecified
        if overrideUserInterfaceStyle != style { overrideUserInterfaceStyle = style; popup.overrideUserInterfaceStyle = style }
        guard changed else { return }
        if structural {
            rebuild()
            setNeedsLayout()
            return
        }
        // Nur Umschalten geändert? Dann bloß die Beschriftungen tauschen (passiert bei jedem Satzanfang).
        if let old = oldConfig, rowHeight == oldRowHeight {
            var same = old
            same.shift = c.shift
            if same == c {
                for k in keys { k.updateShift(config: c, dark: dark) }
                return
            }
        }
        refreshKeys()
        setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        refreshKeys()
    }

    private func rebuild() {
        guard let c = config else { return }
        keys.forEach { $0.removeFromSuperview() }
        keys = []
        var rows: [[(KeyKind, Width)]] = []
        if c.numberRow && c.layer == .letters {
            rows.append(KeyLayouts.numberRow.map { (KeyKind.char($0), Width.units(1)) })
        }
        switch c.layer {
        case .letters:
            let hidden: Set<String> = c.hideUmlauts ? ["ä", "ö", "ü"] : []
            rows.append(KeyLayouts.letters[0].filter { !hidden.contains($0) }.map { (KeyKind.char($0), Width.units(1)) })
            rows.append(KeyLayouts.letters[1].filter { !hidden.contains($0) }.map { (KeyKind.char($0), Width.units(1)) })
            rows.append([(KeyKind.shift, Width.flex)] + KeyLayouts.letters[2].map { (KeyKind.char($0), Width.units(1)) } + [(KeyKind.delete, Width.flex)])
        case .numbers:
            rows.append(KeyLayouts.numbers[0].map { (KeyKind.char($0), Width.units(1)) })
            rows.append(KeyLayouts.numbers[1].map { (KeyKind.char($0), Width.units(1)) })
            rows.append([(KeyKind.symbols, Width.flex)] + KeyLayouts.numbers[2].map { (KeyKind.char($0), Width.units(1.4)) } + [(KeyKind.delete, Width.flex)])
        case .symbols:
            rows.append(KeyLayouts.symbols[0].map { (KeyKind.char($0), Width.units(1)) })
            rows.append(KeyLayouts.symbols[1].map { (KeyKind.char($0), Width.units(1)) })
            rows.append([(KeyKind.numbers, Width.flex)] + KeyLayouts.symbols[2].map { (KeyKind.char($0), Width.units(1.4)) } + [(KeyKind.delete, Width.flex)])
        }
        var bottom: [(KeyKind, Width)] = [(c.layer == .letters ? KeyKind.numbers : KeyKind.letters, Width.units(1.3))]
        if c.needsGlobe { bottom.append((KeyKind.globe, Width.units(1.05))) }
        bottom.append((KeyKind.emoji, Width.units(1.05)))
        bottom.append((KeyKind.space, Width.flex))
        bottom.append((KeyKind.char("."), Width.units(0.95)))
        bottom.append((KeyKind.returnKey, Width.units(2.0)))
        rows.append(bottom)
        rowsSpec = rows
        for row in rows {
            for (kind, _) in row {
                let k = KeyCapView(kind: kind)
                addSubview(k)
                keys.append(k)
            }
        }
        bringSubviewToFront(popup)
        if popup.superview == nil { addSubview(popup) }
        if alternates.superview == nil { addSubview(alternates) }
        bringSubviewToFront(popup)
        bringSubviewToFront(alternates)
        refreshKeys()
    }

    private func refreshKeys() {
        guard let c = config else { return }
        let tint = UIColor(Theme.tint(c.tintIndex))
        alternates.tint = tint
        for k in keys {
            k.tint = tint
            k.configure(config: c, dark: dark)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let st = state { rowHeight = st.keyRowHeight }
        guard !rowsSpec.isEmpty else { return }
        let width = bounds.width - 6
        var y: CGFloat = 4
        var idx = 0
        let isLettersLayout = config?.layer == .letters
        for (r, row) in rowsSpec.enumerated() {
            let isBottom = r == rowsSpec.count - 1
            let unitsPerRow: CGFloat
            if isBottom { unitsPerRow = 10 } else if isLettersLayout && !(config?.numberRow == true && r == 0) { unitsPerRow = config?.hideUmlauts == true ? 10 : 11 } else { unitsPerRow = 10 }
            let unit = width / unitsPerRow
            let fixed = row.reduce(CGFloat(0)) { acc, item in
                if case .units(let u) = item.1 { return acc + u * unit }
                return acc
            }
            let flexCount = CGFloat(row.filter { if case .flex = $0.1 { return true }; return false }.count)
            let flexWidth = flexCount > 0 ? max(0, (width - fixed) / flexCount) : 0
            // Reihen ohne Flex-Tasten zentrieren
            var x: CGFloat = 3 + (flexCount == 0 ? (width - fixed) / 2 : 0)
            for (i, item) in row.enumerated() {
                var w: CGFloat
                if case .units(let u) = item.1 { w = u * unit } else { w = flexWidth }
                let key = keys[idx]
                // Randtasten dehnen ihre Trefferfläche bis zum Rand aus
                var cell = CGRect(x: x, y: y, width: w, height: rowHeight)
                if i == 0 { cell.size.width += cell.minX; cell.origin.x = 0 }
                if i == row.count - 1 { cell.size.width = bounds.width - cell.minX }
                key.frame = CGRect(x: x, y: y, width: w, height: rowHeight)
                key.cellFrame = cell
                x += w
                idx += 1
            }
            y += rowHeight
        }
        reportGeometry()
    }

    /// Teilt dem Zustand die Tastenmitten mit (für Tipp-Korrektur und Lernen der Trefferzonen).
    private func reportGeometry() {
        guard config?.layer == .letters, let state else { return }
        var centers: [Character: CGPoint] = [:]
        for k in keys {
            if case .char(let c) = k.kind, c.count == 1, let ch = c.lowercased().first, ch.isLetter {
                centers[ch] = CGPoint(x: k.frame.midX, y: k.frame.midY)
            }
        }
        // Umlaute ausgeblendet: ä/ö/ü liegen beim Wischen auf a/o/u
        for (u, base) in [("ä", "a"), ("ö", "o"), ("ü", "u")] as [(Character, Character)] where centers[u] == nil {
            centers[u] = centers[base]
        }
        state.keyGeometry = KeyboardState.KeyGeometry(centers: centers, keyWidth: letterKeyWidth, rowHeight: rowHeight)
    }

    // MARK: Treffer

    private func key(at p: CGPoint) -> KeyCapView? {
        // Buchstaben: persönliche Trefferzonen (gelernte Abweichung je Taste)
        if config?.layer == .letters, let state, state.store.adaptiveTouch, let k = adaptiveLetter(at: p, state) { return k }
        if let k = keys.first(where: { $0.cellFrame.contains(p) }) { return k }
        // nächstgelegene Taste (z. B. Berührung ganz am Rand)
        return keys.min { a, b in
            dist(a.cellFrame, p) < dist(b.cellFrame, p)
        }
    }

    /// Wählt den Buchstaben, dessen (persönlich verschobene) Mitte am nächsten liegt.
    private func adaptiveLetter(at p: CGPoint, _ state: KeyboardState) -> KeyCapView? {
        guard let hit = keys.first(where: { $0.cellFrame.contains(p) }) else { return nil }
        guard case .char(let hc) = hit.kind, hc.count == 1, hc.first?.isLetter == true else { return hit }
        let model = state.touchModel
        guard !model.isEmpty else { return hit }
        let kw = max(hit.frame.width, 1), kh = max(hit.frame.height, 1)
        var best: (KeyCapView, CGFloat)?
        for k in keys {
            guard case .char(let c) = k.kind, c.count == 1, let ch = c.lowercased().first, ch.isLetter,
                  abs(k.frame.midY - p.y) < kh * 1.2, abs(k.frame.midX - p.x) < kw * 1.6 else { continue }
            let off = model[ch] ?? .zero
            let cx = k.frame.midX + off.x, cy = k.frame.midY + off.y
            let d = hypot((p.x - cx) / kw, (p.y - cy) / (kh * 1.1))
            if best == nil || d < best!.1 { best = (k, d) }
        }
        return best?.0 ?? hit
    }

    private func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    // MARK: Touches

    override func touchesBegan(_ set: Set<UITouch>, with event: UIEvent?) {
        for t in set {
            let p = t.location(in: self)
            // Schnelles Tippen: vorherige Tasten zuerst auslösen (Rollover), damit die Reihenfolge stimmt
            for id in touchOrder {
                guard let info = touches[id], !info.handled, !info.alternatesActive, !info.cursorMode, !info.swiping else { continue }
                switch info.key.kind {
                case .char, .space, .returnKey: commit(info)
                default: break
                }
            }
            guard let k = smartKey(at: p) else { continue }
            let info = TouchInfo(key: k, startPoint: p)
            let id = ObjectIdentifier(t)
            touches[id] = info
            touchOrder.append(id)
            down(info)
        }
    }

    /// Intelligente Trefferzonen: Liegt die Berührung zwischen zwei Buchstaben,
    /// gewinnt der, der ein echtes Wort ergibt (wie bei der iOS-Tastatur).
    private func smartKey(at p: CGPoint) -> KeyCapView? {
        guard let primary = key(at: p) else { return nil }
        if let space = spaceRescue(primary, p) { return space }
        guard config?.layer == .letters, let state, state.store.smartTouch,
              case .char(let pc) = primary.kind, pc.count == 1, pc.first?.isLetter == true else { return primary }
        let w = max(primary.frame.width, 1)
        let h = max(primary.frame.height, 1)
        let dPrimary = hypot((p.x - primary.frame.midX) / w, (p.y - primary.frame.midY) / h)
        // Klar in der Mitte getroffen → nichts ändern (ohne den Text überhaupt zu lesen)
        guard dPrimary > 0.3 else { return primary }
        let word = state.currentWord
        guard !word.isEmpty else { return primary }
        if state.isPlausibleContinuation(pc, word: word) { return primary }
        var best: (KeyCapView, CGFloat)?
        for k in keys where k !== primary {
            guard case .char(let c) = k.kind, c.count == 1, c.first?.isLetter == true else { continue }
            let d = hypot((p.x - k.frame.midX) / w, (p.y - k.frame.midY) / h)
            guard d < 0.95 else { continue }
            guard state.isSurelyPlausibleContinuation(c, word: word) else { continue }
            if best == nil || d < best!.1 { best = (k, d) }
        }
        return best?.0 ?? primary
    }

    /// Schnelles Tippen: Wer am Wortende knapp über der Leertaste auf c/v/b/n/m landet, meint fast immer „Leer“.
    private func spaceRescue(_ primary: KeyCapView, _ p: CGPoint) -> KeyCapView? {
        guard config?.layer == .letters, let state, state.store.smartTouch,
              case .char(let c) = primary.kind, "cvbnm".contains(c.lowercased()),
              p.y > primary.frame.maxY - primary.frame.height * 0.24,
              !state.currentWordIsEmpty, state.currentWordIsComplete, !state.isPlausibleContinuation(c),
              let space = keys.first(where: { if case .space = $0.kind { return true }; return false }),
              p.x >= space.frame.minX - 4, p.x <= space.frame.maxX + 4 else { return nil }
        return space
    }

    override func touchesMoved(_ set: Set<UITouch>, with event: UIEvent?) {
        for t in set {
            guard let info = touches[ObjectIdentifier(t)], !info.handled else { continue }
            let p = t.location(in: self)
            if info.alternatesActive {
                alternates.update(touchX: p.x)
                continue
            }
            switch info.key.kind {
            case .space:
                spaceMoved(info, p)
            case .delete:
                // Nach links wischen auf ⌫ löscht ganze Wörter
                break
            case .char:
                if trackSwipe(info, p) { continue }
                // Finger rutscht auf andere Taste → neue Taste übernehmen
                // Bei schnellen Tipps zählt die Taste, auf der der Finger aufsetzt (wie bei iOS)
                if info.age > 0.14, !info.key.cellFrame.insetBy(dx: -4, dy: -6).contains(p), let nk = key(at: p), case .char = nk.kind {
                    info.key.setPressed(false)
                    info.longPressTimer?.invalidate()
                    info.key = nk
                    nk.setPressed(true)
                    showPopup(for: nk)
                    scheduleLongPress(info)
                }
            default:
                break
            }
        }
    }

    override func touchesEnded(_ set: Set<UITouch>, with event: UIEvent?) {
        for t in set {
            let id = ObjectIdentifier(t)
            guard let info = touches[id] else { continue }
            if info.swiping {
                info.handled = true
                endSwipe(info)
            } else if !info.handled {
                commit(info)
            }
            finish(id)
        }
    }

    override func touchesCancelled(_ set: Set<UITouch>, with event: UIEvent?) {
        for t in set {
            let id = ObjectIdentifier(t)
            // Bricht iOS eine Berührung ab (z. B. System-Geste am unteren Rand), ging beim schnellen
            // Tippen der Buchstabe verloren. Kurze, ruhige Tipps deshalb trotzdem auslösen.
            if let info = touches[id], !info.handled, !info.swiping, !info.cursorMode, !info.alternatesActive,
               info.age < 0.3, info.pathLength < letterKeyWidth * 0.8 {
                switch info.key.kind {
                case .char, .space, .returnKey: commit(info)
                default: break
                }
            }
            finish(id)
        }
    }

    // MARK: Keine Verzögerung durch Gesten-Erkenner

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        disableAncestorTouchDelays()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.disableAncestorTouchDelays() }
    }

    /// Gesten-Erkenner in den Eltern-Views (SwiftUI, System) halten Berührungen sonst zurück –
    /// besonders das Loslassen (delaysTouchesEnded), auf das jeder Buchstabe wartet.
    func disableAncestorTouchDelays() {
        var v: UIView? = self
        while let current = v {
            current.gestureRecognizers?.forEach {
                $0.delaysTouchesBegan = false
                $0.delaysTouchesEnded = false
            }
            v = current.superview
        }
    }

    /// Sicherheitsnetz: Wird das Tastenfeld entfernt, laufen keine Wiederholungen weiter.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            state?.stopDelete()
            for id in Array(touches.keys) { finish(id) }
            popup.hide()
            alternates.isHidden = true
        }
    }

    private func finish(_ id: ObjectIdentifier) {
        guard let info = touches[id] else { return }
        info.longPressTimer?.invalidate()
        if case .delete = info.key.kind { state?.stopDelete() }
        info.key.setPressed(false)
        touches[id] = nil
        touchOrder.removeAll { $0 == id }
        if touches.values.allSatisfy({ !$0.key.isPressed }) { popup.hide() }
        if info.alternatesActive { alternates.isHidden = true }
        if info.cursorMode { state?.cursorMoveEnded() }
        if info.swiping { fadeTrail() }
    }

    private func down(_ info: TouchInfo) {
        let k = info.key
        k.setPressed(true)
        state?.keyDownFeedback(special: k.isSpecial)
        switch k.kind {
        case .char:
            showPopup(for: k)
            scheduleLongPress(info)
        case .delete:
            info.handled = true
            state?.noteKeystroke()
            state?.startDelete()
        case .shift:
            info.handled = true
            state?.tapShift()
        default:
            break
        }
    }

    private func commit(_ info: TouchInfo) {
        guard !info.handled, let state else { return }
        info.handled = true
        state.noteKeystroke()
        info.longPressTimer?.invalidate()
        info.key.setPressed(false)
        if info.alternatesActive {
            if let s = alternates.selected { state.insertAlternate(s) }
            alternates.isHidden = true
            return
        }
        if info.cursorMode { return }
        switch info.key.kind {
        case .char(let c):
            state.pendingTapPoint = info.startPoint
            state.tapKey(c)
        case .space: state.tapSpace()
        case .returnKey: state.tapReturn()
        case .numbers: state.setLayer(.numbers)
        case .letters: state.setLayer(.letters)
        case .symbols: state.setLayer(.symbols)
        case .globe: state.controller?.advanceToNextInputMode()
        case .emoji: state.toggle(.emoji)
        case .delete: state.stopDelete()
        case .shift: break
        }
    }

    // MARK: Gesten-Tippen

    private var letterKeyWidth: CGFloat {
        keys.first { if case .char(let c) = $0.kind { return c.count == 1 && c.first?.isLetter == true }; return false }?.frame.width ?? 34
    }

    /// Verfolgt die Fingerbahn. true = Wischgeste aktiv (normale Tastenlogik überspringen).
    private func trackSwipe(_ info: TouchInfo, _ p: CGPoint) -> Bool {
        guard config?.layer == .letters, let state, state.store.swipeTyping, !info.alternatesActive else { return false }
        if let last = info.path.last {
            let d = hypot(p.x - last.x, p.y - last.y)
            guard d > 2 else { return info.swiping }
            info.pathLength += d
        }
        info.path.append(p)
        if !info.swiping {
            // Nur mit einem Finger und erst ab einer klaren Bewegung über mehrere Tasten
            // Schnelles Mehrfinger-Tippen: kurze Tipps mit leichtem Rutschen sind nie eine Wischgeste
            guard touches.count == 1, info.pathLength > letterKeyWidth * 1.35,
                  info.age > 0.11 || info.pathLength > letterKeyWidth * 2.6 else { return false }
            info.swiping = true
            info.longPressTimer?.invalidate()
            info.key.setPressed(false)
            popup.hide()
            SwipeDecoder.shared.loadIfNeeded()
            let tint = UIColor(Theme.tint(config?.tintIndex ?? 0))
            trail.strokeColor = tint.withAlphaComponent(0.9).cgColor
            trailGlow.strokeColor = tint.withAlphaComponent(0.25).cgColor
            trail.removeAllAnimations()
            trailGlow.removeAllAnimations()
            trail.opacity = 1
            trailGlow.opacity = 1
            state.feedback()
        }
        let path = UIBezierPath()
        // Nur die letzten Punkte zeichnen: wirkt wie ein leuchtender Schweif
        let tail = info.path.suffix(42)
        if let first = tail.first {
            path.move(to: first)
            for q in tail.dropFirst() { path.addLine(to: q) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trail.path = path.cgPath
        trailGlow.path = path.cgPath
        CATransaction.commit()
        return true
    }

    private func endSwipe(_ info: TouchInfo) {
        guard let state else { return }
        var centers: [Character: CGPoint] = [:]
        for k in keys {
            if case .char(let c) = k.kind, c.count == 1, let ch = c.lowercased().first, ch.isLetter {
                centers[ch] = CGPoint(x: k.frame.midX, y: k.frame.midY)
            }
        }
        let input = SwipeDecoder.Input(points: info.path, centers: centers, keyWidth: letterKeyWidth,
                                       learned: state.engine.swipeLearned(), context: state.swipeContext())
        let result = SwipeDecoder.shared.decode(input)
        state.commitSwipe(result.words, keys: result.keys)
    }

    private func fadeTrail() {
        for l in [trail, trailGlow] {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1
            a.toValue = 0
            a.duration = 0.28
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            l.opacity = 0
            l.add(a, forKey: "fade")
        }
    }

    private func showPopup(for k: KeyCapView) {
        guard config?.popups == true, case .char(let c) = k.kind else { return }
        let upper = config?.layer == .letters && config?.shift != .off
        popup.show(text: upper ? c.uppercased() : c, above: k.capFrameInParent, dark: dark, in: bounds)
        bringSubviewToFront(popup)
    }

    private func scheduleLongPress(_ info: TouchInfo) {
        info.longPressTimer?.invalidate()
        guard case .char(let c) = info.key.kind, let alts = KeyLayouts.alternates[c.lowercased()] else { return }
        info.longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self, weak info] _ in
            guard let self, let info, !info.handled else { return }
            info.alternatesActive = true
            self.popup.hide()
            let upper = self.config?.layer == .letters && self.config?.shift != .off
            let options = [upper ? c.uppercased() : c] + alts.map { upper ? $0.uppercased() : $0 }
            self.alternates.show(options: options, above: info.key.capFrameInParent, dark: self.dark, in: self.bounds)
            self.bringSubviewToFront(self.alternates)
            self.state?.feedback(.medium)
        }
    }

    private func spaceMoved(_ info: TouchInfo, _ p: CGPoint) {
        guard state?.store.spaceCursor != false else { return }
        let dx = p.x - info.startPoint.x
        // Schnelles Tippen: Daumen rutscht oft ein paar Punkte – das ist noch kein Cursor-Wischen
        if !info.cursorMode, (abs(dx) > 14 && info.age > 0.16) || abs(dx) > 42 {
            info.cursorMode = true
            info.key.setPressed(true)
            state?.feedback(.medium)
        }
        guard info.cursorMode else { return }
        let step = Int(dx / 8)
        if step != info.cursorStep {
            state?.moveCursor(step - info.cursorStep)
            info.cursorStep = step
        }
    }
}

/// Bindet das UIKit-Tastenfeld in SwiftUI ein – ohne SwiftUI-Beobachtung:
/// Das Tastenfeld abonniert seine Daten selbst und aktualisiert sich direkt.
struct KeysRepresentable: UIViewRepresentable {
    let state: KeyboardState

    func makeUIView(context: Context) -> KeysView {
        let v = KeysView()
        v.bind(to: state)
        return v
    }

    func updateUIView(_ v: KeysView, context: Context) {}
}

extension KeysView {
    func bind(to state: KeyboardState) {
        self.state = state
        let km = state.keyModel
        let store = state.store
        cancellables.removeAll()
        // Sofort (ohne Umweg über SwiftUI) auf Umschalt-/Ebenenwechsel reagieren
        Publishers.CombineLatest4(km.$layer, km.$shift, km.$returnTitle, km.$needsGlobe)
            .sink { [weak self, weak state] layer, shift, title, globe in
                guard let self, let state else { return }
                self.apply(KeysView.makeConfig(store: store, layer: layer, shift: shift, returnTitle: title, needsGlobe: globe),
                           rowHeight: state.keyRowHeight)
            }
            .store(in: &cancellables)
        // Design-Änderungen (seltener) gesammelt im nächsten Durchlauf übernehmen
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak state] _ in
                guard let self, let state else { return }
                self.apply(KeysView.makeConfig(store: store, layer: km.layer, shift: km.shift, returnTitle: km.returnTitle, needsGlobe: km.needsGlobe),
                           rowHeight: state.keyRowHeight)
            }
            .store(in: &cancellables)
    }

    static func makeConfig(store: SharedStore, layer: KeyboardLayer, shift: ShiftState, returnTitle: String, needsGlobe: Bool) -> KeysConfig {
        KeysConfig(layer: layer, shift: shift, returnTitle: returnTitle,
                   needsGlobe: needsGlobe, numberRow: store.showNumberRow,
                   tintIndex: store.keyboardTint, popups: store.keyPopups,
                   keyOpacity: CGFloat(store.keyOpacity), cornerRadius: CGFloat(store.keyCornerRadius),
                   fontScale: CGFloat(store.keyFontScale), forceDark: Theme.backgroundIsDark(store),
                   style: store.keyStyle, keyColorHex: store.keyColorHex,
                   textColorHex: store.keyTextColorHex, fontDesign: store.keyFontDesign,
                   hideUmlauts: store.hideUmlauts)
    }
}
