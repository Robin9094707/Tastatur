import UIKit
import SwiftUI

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
        cap.layer.shadowPath = UIBezierPath(roundedRect: cap.bounds, cornerRadius: 8.5).cgPath
        label.frame = cap.bounds.insetBy(dx: 2, dy: 0)
        icon.frame = cap.bounds
    }

    func configure(config: KeysConfig, dark: Bool) {
        let upper = config.layer == .letters && config.shift != .off
        label.isHidden = false
        icon.isHidden = true
        label.textColor = .label
        let sym = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        switch kind {
        case .char(let c):
            label.text = upper ? c.uppercased() : c
            label.font = .systemFont(ofSize: c.count > 1 ? 17 : 24, weight: .regular)
        case .shift:
            showIcon(config.shift == .caps ? "capslock.fill" : (config.shift == .on ? "shift.fill" : "shift"), sym)
            icon.tintColor = config.shift != .off ? .black : .label
        case .delete:
            showIcon(isPressed ? "delete.left.fill" : "delete.left", sym)
        case .space:
            label.text = "Leerzeichen"
            label.font = .systemFont(ofSize: 16)
            label.textColor = .secondaryLabel
        case .returnKey:
            if config.returnTitle == "⏎" {
                showIcon("return", sym)
            } else {
                label.text = config.returnTitle
                label.font = .systemFont(ofSize: 16, weight: .semibold)
                label.textColor = .white
            }
        case .numbers:
            label.text = "123"; label.font = .systemFont(ofSize: 16)
        case .letters:
            label.text = "ABC"; label.font = .systemFont(ofSize: 16)
        case .symbols:
            label.text = "#+="; label.font = .systemFont(ofSize: 16)
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
        icon.tintColor = .label
    }

    private var lastConfig: KeysConfig?
    private var lastDark = false

    func applyColors(config: KeysConfig, dark: Bool) {
        lastConfig = config
        lastDark = dark
        cap.layer.shadowOpacity = dark ? 0.45 : 0.25
        if case .returnKey = kind, config.returnTitle != "⏎" {
            cap.backgroundColor = tint.withAlphaComponent(isPressed ? 0.6 : 0.95)
            return
        }
        if case .shift = kind, config.shift != .off {
            cap.backgroundColor = UIColor.white.withAlphaComponent(isPressed ? 0.7 : 0.95)
            return
        }
        if dark {
            let base: CGFloat = isSpecial ? 0.13 : 0.30
            cap.backgroundColor = UIColor(white: 1, alpha: isPressed ? base + 0.25 : base)
        } else {
            if isSpecial {
                cap.backgroundColor = UIColor(white: isPressed ? 0.98 : 0.68, alpha: 0.85)
            } else {
                cap.backgroundColor = UIColor(white: isPressed ? 0.72 : 1.0, alpha: 0.95)
            }
        }
    }

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        if case .delete = kind {
            icon.image = UIImage(systemName: pressed ? "delete.left.fill" : "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18))
        }
        if let c = lastConfig { applyColors(config: c, dark: lastDark) }
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
        frame = CGRect(x: x, y: capFrame.minY - h - 4, width: w, height: h)
        bg.frame = CGRect(origin: .zero, size: frame.size)
        label.frame = bg.bounds
        isHidden = false
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
    private var config: KeysConfig?
    private var keys: [KeyCapView] = []
    private var rowsSpec: [[(KeyKind, Width)]] = []
    private let popup = KeyPopupView()
    private let alternates = AlternatesView()
    var rowHeight: CGFloat = 52

    private final class TouchInfo {
        var key: KeyCapView
        var startPoint: CGPoint
        var longPressTimer: Timer?
        var alternatesActive = false
        var cursorMode = false
        var cursorStep = 0
        var handled = false
        init(key: KeyCapView, startPoint: CGPoint) { self.key = key; self.startPoint = startPoint }
    }
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
    }

    required init?(coder: NSCoder) { fatalError() }

    private var dark: Bool { traitCollection.userInterfaceStyle == .dark }

    func apply(_ c: KeysConfig, rowHeight: CGFloat) {
        let structural = config == nil || c.layer != config!.layer || c.needsGlobe != config!.needsGlobe || c.numberRow != config!.numberRow
        let changed = c != config || rowHeight != self.rowHeight
        self.rowHeight = rowHeight
        config = c
        guard changed else { return }
        if structural { rebuild() } else { refreshKeys() }
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
            rows.append(KeyLayouts.letters[0].map { (KeyKind.char($0), Width.units(1)) })
            rows.append(KeyLayouts.letters[1].map { (KeyKind.char($0), Width.units(1)) })
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
        guard !rowsSpec.isEmpty else { return }
        let width = bounds.width - 6
        var y: CGFloat = 4
        var idx = 0
        let isLettersLayout = config?.layer == .letters
        for (r, row) in rowsSpec.enumerated() {
            let isBottom = r == rowsSpec.count - 1
            let unitsPerRow: CGFloat
            if isBottom { unitsPerRow = 10 } else if isLettersLayout && !(config?.numberRow == true && r == 0) { unitsPerRow = 11 } else { unitsPerRow = 10 }
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
    }

    // MARK: Treffer

    private func key(at p: CGPoint) -> KeyCapView? {
        if let k = keys.first(where: { $0.cellFrame.contains(p) }) { return k }
        // nächstgelegene Taste (z. B. Berührung ganz am Rand)
        return keys.min { a, b in
            dist(a.cellFrame, p) < dist(b.cellFrame, p)
        }
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
            guard let k = key(at: p) else { continue }
            // Schnelles Tippen: vorherige Zeichen-Taste sofort auslösen (Rollover)
            for id in touchOrder {
                if let info = touches[id], !info.handled, case .char = info.key.kind, !info.alternatesActive {
                    commit(info)
                }
            }
            let info = TouchInfo(key: k, startPoint: p)
            let id = ObjectIdentifier(t)
            touches[id] = info
            touchOrder.append(id)
            down(info)
        }
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
                // Finger rutscht auf andere Taste → neue Taste übernehmen
                if !info.key.cellFrame.insetBy(dx: -4, dy: -6).contains(p), let nk = key(at: p), case .char = nk.kind {
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
            if !info.handled { commit(info) }
            finish(id)
        }
    }

    override func touchesCancelled(_ set: Set<UITouch>, with event: UIEvent?) {
        for t in set {
            let id = ObjectIdentifier(t)
            guard let info = touches[id] else { continue }
            if case .delete = info.key.kind { state?.stopDelete() }
            finish(id)
        }
    }

    private func finish(_ id: ObjectIdentifier) {
        guard let info = touches[id] else { return }
        info.longPressTimer?.invalidate()
        info.key.setPressed(false)
        touches[id] = nil
        touchOrder.removeAll { $0 == id }
        if touches.values.allSatisfy({ !$0.key.isPressed }) { popup.hide() }
        if info.alternatesActive { alternates.isHidden = true }
        if info.cursorMode { state?.cursorMoveEnded() }
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
        info.longPressTimer?.invalidate()
        info.key.setPressed(false)
        if info.alternatesActive {
            if let s = alternates.selected { state.insertAlternate(s) }
            alternates.isHidden = true
            return
        }
        if info.cursorMode { return }
        switch info.key.kind {
        case .char(let c): state.tapKey(c)
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
        let dx = p.x - info.startPoint.x
        if !info.cursorMode, abs(dx) > 12 {
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

/// Bindet das UIKit-Tastenfeld in SwiftUI ein.
struct KeysRepresentable: UIViewRepresentable {
    @ObservedObject var state: KeyboardState
    @ObservedObject var store = SharedStore.shared

    func makeUIView(context: Context) -> KeysView {
        let v = KeysView()
        v.state = state
        return v
    }

    func updateUIView(_ v: KeysView, context: Context) {
        v.state = state
        v.apply(KeysConfig(layer: state.layer, shift: state.shift, returnTitle: state.returnTitle,
                           needsGlobe: state.needsGlobe, numberRow: store.showNumberRow,
                           tintIndex: store.keyboardTint, popups: store.keyPopups),
                rowHeight: state.keyRowHeight)
    }
}
