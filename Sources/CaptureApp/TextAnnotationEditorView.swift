import AppKit

final class TextAnnotationEditorView: NSScrollView, NSTextViewDelegate {
    private enum Layout {
        static let horizontalInset: CGFloat = 10
        static let verticalInset: CGFloat = 6
        static let measurementPadding: CGFloat = 2
    }

    let textView: NSTextView
    var onTextChanged: ((String, CGSize) -> Void)?
    var onEditingEnded: ((String, CGSize) -> Void)?

    private var minimumContentSize: CGSize

    init(
        frame: CGRect,
        text: String,
        font: NSFont,
        textColor: NSColor,
        backgroundColor: NSColor,
        drawsBackground: Bool
    ) {
        textView = NSTextView(frame: CGRect(origin: .zero, size: frame.size))
        minimumContentSize = frame.size
        super.init(frame: frame)

        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = false
        self.drawsBackground = drawsBackground
        self.backgroundColor = drawsBackground ? backgroundColor : .clear

        configureTextView(
            text: text,
            font: font,
            textColor: textColor,
            backgroundColor: backgroundColor,
            drawsBackground: drawsBackground
        )
        documentView = textView
        resizeToFitContent()
    }

    required init?(coder: NSCoder) { nil }

    var text: String {
        textView.string
    }

    func focusAtEnd() {
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    }

    func updateFrame(
        _ frame: CGRect,
        font: NSFont,
        textColor: NSColor,
        backgroundColor: NSColor,
        drawsBackground: Bool
    ) {
        setFrameOrigin(frame.origin)
        minimumContentSize = frame.size
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        textView.drawsBackground = drawsBackground
        self.drawsBackground = drawsBackground
        self.backgroundColor = drawsBackground ? backgroundColor : .clear
        resizeToFitContent()
    }

    @discardableResult
    func resizeToFitContent() -> CGSize {
        let size = preferredContentSize()
        setFrameSize(size)
        textView.setFrameSize(size)
        return size
    }

    func preferredContentSize() -> CGSize {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return minimumContentSize
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let width = ceil(usedRect.width + Layout.horizontalInset * 2 + Layout.measurementPadding)
        let height = ceil(usedRect.height + Layout.verticalInset * 2 + Layout.measurementPadding)
        return CGSize(
            width: max(minimumContentSize.width, width),
            height: max(minimumContentSize.height, height)
        )
    }

    func textDidChange(_ notification: Notification) {
        let size = resizeToFitContent()
        onTextChanged?(textView.string, size)
    }

    func textDidEndEditing(_ notification: Notification) {
        onEditingEnded?(textView.string, preferredContentSize())
    }

    private func configureTextView(
        text: String,
        font: NSFont,
        textColor: NSColor,
        backgroundColor: NSColor,
        drawsBackground: Bool
    ) {
        textView.string = text
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        textView.drawsBackground = drawsBackground
        textView.alignment = .center
        textView.delegate = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = CGSize(width: Layout.horizontalInset, height: Layout.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }
}
