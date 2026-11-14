import UIKit
import SwiftUI
import Combine

/// Die normale Vorschlagsleiste (bis zu 3 Felder) in UIKit – wie bei der iOS-Tastatur wird beim Tippen
/// nur der Text getauscht. SwiftUI rechnet dabei nichts neu (die Messung zeigte bis zu 78 ms Ruckler
/// beim Neuzeichnen der SwiftUI-Leiste).
final class SuggestionStripView: UIView {
    var onPick: ((Suggestion) -> Void)?
    var tint: UIColor = .systemIndigo { didSet { if tint != oldValue { cells.forEach { $0.tint = tint }; apply() } } }
    private var cells: [SuggestionCell] = []
    private var separators: [UIView] = []
    private let placeholder = UILabel()
    private var items: [Suggestion] = []
    var cancellable: AnyCancellable?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        placeholder.font = .preferredFont(forTextStyle: .caption1)
        placeholder.textColor = .secondaryLabel
        placeholder.textAlignment = .center
        addSubview(placeholder)
        for _ in 0..<3 {
            let c = SuggestionCell()
            c.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            addSubview(c)
            cells.append(c)
        }
        for _ in 0..<2 {
            let s = UIView()
            s.backgroundColor = UIColor.label.withAlphaComponent(0.12)
            s.isUserInteractionEnabled = false
            addSubview(s)
            separators.append(s)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ list: [Suggestion]) {
        let list = Array(list.prefix(3))
        // Nichts geändert → nichts tun
        if list.map(\.text) == items.map(\.text), list.map(\.kind) == items.map(\.kind), list.map(\.display) == items.map(\.display) { return }
        items = list
        apply()
    }

    func setPlaceholder(_ text: String) {
        if placeholder.text != text { placeholder.text = text }
    }

    private func apply() {
        // Ohne implizite Animationen umsetzen – sofort wie bei iOS
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, c) in cells.enumerated() {
            if i < items.count {
                c.isHidden = false
                c.configure(items[i])
            } else {
                c.isHidden = true
            }
        }
        placeholder.isHidden = !items.isEmpty
        setNeedsLayout()
        layoutIfNeeded()
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let n = max(items.count, 1)
        let w = bounds.width / CGFloat(n)
        for (i, c) in cells.enumerated() where i < items.count {
            c.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height)
        }
        for (i, s) in separators.enumerated() {
            let visible = i + 1 < items.count
            s.isHidden = !visible
            if visible {
                s.frame = CGRect(x: CGFloat(i + 1) * w - 0.5, y: (bounds.height - 18) / 2, width: 1, height: 18)
            }
        }
        placeholder.frame = bounds.insetBy(dx: 8, dy: 0)
    }

    @objc private func tapped(_ sender: SuggestionCell) {
        guard let s = sender.item else { return }
        onPick?(s)
    }
}

/// Ein Feld der Leiste: Text, optional Markierung (Korrektur/Makro/Eintrag) und kleines Symbol.
final class SuggestionCell: UIControl {
    private let pill = UIView()
    private let label = UILabel()
    private(set) var item: Suggestion?
    var tint: UIColor = .systemIndigo

    override init(frame: CGRect) {
        super.init(frame: frame)
        pill.isUserInteractionEnabled = false
        pill.layer.cornerCurve = .continuous
        addSubview(pill)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.lineBreakMode = .byTruncatingTail
        label.isUserInteractionEnabled = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ s: Suggestion) {
        item = s
        let marked = s.kind == .correction || s.kind == .macro || s.kind == .token
        pill.isHidden = !marked
        pill.backgroundColor = tint.withAlphaComponent(0.28)
        let font = UIFont.systemFont(ofSize: 16, weight: s.kind == .correction ? .semibold : .regular)
        let color: UIColor = s.kind == .typed ? .secondaryLabel : .label
        let text = s.display ?? s.text
        var symbol: String?
        if s.kind == .ai { symbol = "sparkle" } else if s.kind == .token { symbol = "person.crop.circle.badge.checkmark" }
        if let symbol, let img = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: s.kind == .ai ? 9 : 11))?
            .withTintColor(tint, renderingMode: .alwaysOriginal) {
            let att = NSTextAttachment(image: img)
            let str = NSMutableAttributedString(attachment: att)
            str.append(NSAttributedString(string: " " + text, attributes: [.font: font, .foregroundColor: color]))
            label.attributedText = str
        } else {
            label.attributedText = nil
            label.text = text
            label.font = font
            label.textColor = color
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 6, dy: 0)
        pill.frame = bounds.insetBy(dx: 3, dy: 3)
        pill.layer.cornerRadius = pill.bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            alpha = isHighlighted ? 0.45 : 1
        }
    }
}

/// SwiftUI-Hülle: abonniert die Vorschläge direkt (ohne SwiftUI-Beobachtung).
struct SuggestionStrip: UIViewRepresentable {
    let state: KeyboardState
    var placeholder: String
    var tint: Color
    var dark: Bool

    func makeUIView(context: Context) -> SuggestionStripView {
        let v = SuggestionStripView()
        v.onPick = { [weak state] s in state?.pickSuggestion(s) }
        v.tint = UIColor(tint)
        v.cancellable = state.bar.suggestionStream.sink { [weak v] list in v?.show(list) }
        v.setPlaceholder(placeholder)
        return v
    }

    func updateUIView(_ v: SuggestionStripView, context: Context) {
        v.setPlaceholder(placeholder)
        v.tint = UIColor(tint)
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        if v.overrideUserInterfaceStyle != style { v.overrideUserInterfaceStyle = style }
    }

    static func dismantleUIView(_ v: SuggestionStripView, coordinator: ()) {
        v.cancellable = nil
    }
}

/// Viele Vorschläge / KI-Sätze: scrollbar (selten, nur in Tipp-Pausen).
struct WideSuggestions<Item: View, Phrase: View>: View {
    @ObservedObject var bar: BarModel
    @State private var items: [Suggestion] = []
    let item: (Suggestion) -> Item
    let phrase: (Suggestion) -> Phrase

    init(bar: BarModel, item: @escaping (Suggestion) -> Item, phrase: @escaping (Suggestion) -> Phrase) {
        self.bar = bar
        self.item = item
        self.phrase = phrase
        _items = State(initialValue: bar.suggestions)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Color.clear.frame(width: 1).id("start")
                    ForEach(items) { s in item(s) }
                    ForEach(bar.phrases) { p in phrase(p) }
                }
                .padding(.horizontal, 4)
            }
            .onReceive(bar.suggestionStream) { list in
                if list.map(\.text) != items.map(\.text) {
                    items = list
                    reader.scrollTo("start", anchor: .leading)
                }
            }
        }
    }
}
