import AppKit
import CaptureCore

final class TextAnnotationEditorView: NSScrollView, NSTextViewDelegate {

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
        layoutText(grow: false)
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
        layoutText(grow: false)
    }

    @discardableResult
    private func layoutText(grow: Bool) -> CGSize {
        guard let manager = textView.layoutManager, let container = textView.textContainer,
              let font = textView.font else { return frame.size }
        TextAnnotationLayout.configure(container, width: minimumContentSize.width, scale: scale)
        let usedHeight = TextAnnotationLayout.contentHeight(manager: manager, container: container, font: font)
        let requiredHeight = ceil(usedHeight + TextAnnotationLayout.verticalInset * scale * 2)
        var size = minimumContentSize
        if grow {
            size.height = max(size.height, min(maximumContentSize.height, requiredHeight))
            minimumContentSize = size
        }
        hasOverflow = requiredHeight > size.height
        setFrameSize(size)
        textView.textContainerInset = CGSize(
            width: TextAnnotationLayout.horizontalInset * scale,
            height: TextAnnotationLayout.verticalOffset(height: size.height, contentHeight: usedHeight, scale: scale))
        textView.setFrameSize(CGSize(width: size.width, height: max(size.height, requiredHeight)))
        if !hasOverflow { contentView.scroll(to: .zero) }
        reflectScrolledClipView(contentView)
        return size
    }

    func textDidChange(_ notification: Notification) {
        let size = layoutText(grow: true)
        onTextChanged?(textView.string, size)
    }

    func textDidEndEditing(_ notification: Notification) {
        onEditingEnded?(textView.string, frame.size)
    }

    private func configureTextView(
        text: String,
        font: NSFont,
        textColor: NSColor
    ) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: TextAnnotationLayout.attributes(font: font, color: textColor)))
        textView.font = font
        textView.textColor = textColor
        textView.drawsBackground = false
        textView.alignment = .center
        textView.typingAttributes = TextAnnotationLayout.attributes(font: font, color: textColor)
        textView.delegate = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = CGSize(width: TextAnnotationLayout.horizontalInset, height: TextAnnotationLayout.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.containerSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }
}
