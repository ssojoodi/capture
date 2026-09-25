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
    private var maximumContentSize: CGSize
    private var scale: CGFloat
    private(set) var hasOverflow = false
    var resizeHandleHitTest: ((NSPoint) -> Bool)?

    init(
        frame: CGRect,
        text: String,
        font: NSFont,
        textColor: NSColor,
        maximumSize: CGSize,
        scale: CGFloat
    ) {
        textView = NSTextView(frame: CGRect(origin: .zero, size: frame.size))
        minimumContentSize = frame.size
        maximumContentSize = maximumSize
        self.scale = scale
        super.init(frame: frame)

        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        // The canvas paints the annotation background once, beneath this editor.
        drawsBackground = false
        contentView.drawsBackground = false

        configureTextView(
            text: text,
            font: font,
            textColor: textColor
        )
        documentView = textView
        resizeToFitContent()
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if resizeHandleHitTest?(point) == true { return nil }
        return super.hitTest(point)
    }

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
        maximumSize: CGSize,
        scale: CGFloat
    ) {
        setFrameOrigin(frame.origin)
        minimumContentSize = frame.size
        maximumContentSize = maximumSize
        self.scale = scale
        textView.font = font
        textView.textColor = textColor
        resizeToFitContent()
    }

    @discardableResult
    func resizeToFitContent() -> CGSize {
        let size = preferredContentSize()
        setFrameSize(size)
        let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        textView.setFrameSize(CGSize(width: size.width, height: max(size.height, ceil(usedHeight + Layout.verticalInset * scale * 2))))
        return size
    }

    func preferredContentSize() -> CGSize {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return minimumContentSize
        }

        let width = min(minimumContentSize.width, maximumContentSize.width)
        textView.textContainerInset = CGSize(width: Layout.horizontalInset * scale, height: Layout.verticalInset * scale)
        textContainer.containerSize = CGSize(width: max(1, width - Layout.horizontalInset * scale * 2), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = ceil(usedRect.height + (Layout.verticalInset * 2 + Layout.measurementPadding) * scale)
        hasOverflow = height > maximumContentSize.height
        return CGSize(
            width: width,
            height: min(maximumContentSize.height, max(minimumContentSize.height, height))
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
        textColor: NSColor
    ) {
        textView.string = text
        textView.font = font
        textView.textColor = textColor
        textView.drawsBackground = false
        textView.alignment = .center
        textView.delegate = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = CGSize(width: Layout.horizontalInset, height: Layout.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.containerSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }
}
