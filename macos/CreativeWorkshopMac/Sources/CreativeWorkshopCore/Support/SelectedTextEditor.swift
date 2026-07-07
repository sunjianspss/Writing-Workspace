import AppKit
import SwiftUI

package struct SelectedTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    package var font: NSFont = .systemFont(ofSize: 16)
    /// 生成后轻量自检信号（18.3.5）：命中的原文片段用背景高亮标出，纯展示、不修改正文。
    package var highlightExcerpts: [String] = []

    package init(
        text: Binding<String>,
        selectedRange: Binding<NSRange>,
        font: NSFont = .systemFont(ofSize: 16),
        highlightExcerpts: [String] = []
    ) {
        self._text = text
        self._selectedRange = selectedRange
        self.font = font
        self.highlightExcerpts = highlightExcerpts
    }

    package func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    package func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 44, right: 0)

        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = font
        textView.typingAttributes[.font] = font
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.allowsNonContiguousLayout = false

        scrollView.documentView = textView
        return scrollView
    }

    package func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.font != font {
            textView.font = font
            textView.typingAttributes[.font] = font
        }

        let coordinator = context.coordinator
        if textView.hasMarkedText() {
            return
        }

        if textView.string != text {
            // 中文输入法组词/刚提交时，SwiftUI 可能因为自动保存或其他状态刷新，
            // 用上一帧的绑定值回调 updateNSView。此时不能把旧文本写回 NSTextView，
            // 否则光标和候选字会被拉回旧位置，表现为“输入飘移”。
            if coordinator.isUserEditing(textView),
               coordinator.hasPendingUserSync || text == coordinator.lastSeenTextBinding {
                return
            }

            coordinator.cancelPendingSync()
            coordinator.isApplyingSwiftUIUpdate = true
            let clampedRange = Self.clampedRange(selectedRange, in: text)
            textView.string = text
            textView.setSelectedRange(clampedRange)
            coordinator.isApplyingSwiftUIUpdate = false
            coordinator.lastSeenTextBinding = text
            coordinator.lastSeenSelectionBinding = clampedRange
            coordinator.lastHighlightedExcerpts = highlightExcerpts
            Self.applyHighlights(highlightExcerpts, to: textView)
            return
        }

        coordinator.lastSeenTextBinding = text
        let clampedRange = Self.clampedRange(selectedRange, in: text)
        let selectionBindingChanged = clampedRange != coordinator.lastSeenSelectionBinding
        if textView.selectedRange() != clampedRange,
           selectionBindingChanged,
           coordinator.shouldApplySelectionFromBinding(clampedRange, textView: textView) {
            coordinator.isApplyingSwiftUIUpdate = true
            textView.setSelectedRange(clampedRange)
            // 定点定位（如从诊断 issue 跳转）后把选区滚动到可见区域，长文本中不这样做用户会看不到发生了什么。
            textView.scrollRangeToVisible(clampedRange)
            coordinator.isApplyingSwiftUIUpdate = false
        }
        coordinator.lastSeenSelectionBinding = clampedRange

        if coordinator.lastHighlightedExcerpts != highlightExcerpts,
           !textView.hasMarkedText(),
           !coordinator.hasPendingUserSync {
            coordinator.lastHighlightedExcerpts = highlightExcerpts
            Self.applyHighlights(highlightExcerpts, to: textView)
        }
    }

    private static func applyHighlights(_ excerpts: [String], to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

        guard !excerpts.isEmpty else { return }
        let haystack = textView.string as NSString
        for excerpt in excerpts {
            let needle = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { continue }
            let found = haystack.range(of: needle)
            guard found.location != NSNotFound else { continue }
            layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.28), forCharacterRange: found)
        }
    }

    private static func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let length = text.utf16.count
        let location = min(max(0, range.location), length)
        let upperBound = min(length, location + max(0, range.length))
        return NSRange(location: location, length: upperBound - location)
    }

    package final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange
        package var isApplyingSwiftUIUpdate = false
        package var lastHighlightedExcerpts: [String] = []
        package var lastSeenTextBinding: String
        package var lastSeenSelectionBinding: NSRange
        private var pendingSyncWorkItem: DispatchWorkItem?
        private var pendingText: String?
        private var pendingSelection: NSRange?
        private let compositionRetryDelay: TimeInterval = 0.05
        private let userSyncDelay: TimeInterval = 0.03

        package var hasPendingUserSync: Bool {
            pendingSyncWorkItem != nil
        }

        package init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            _text = text
            _selectedRange = selectedRange
            lastSeenTextBinding = text.wrappedValue
            lastSeenSelectionBinding = selectedRange.wrappedValue
        }

        package func isUserEditing(_ textView: NSTextView) -> Bool {
            textView.window?.firstResponder === textView
        }

        package func textDidChange(_ notification: Notification) {
            guard !isApplyingSwiftUIUpdate,
                  let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() {
                scheduleUserSyncAfterComposition(from: textView)
                return
            }
            scheduleUserSync(from: textView)
        }

        package func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingSwiftUIUpdate,
                  let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() {
                scheduleUserSyncAfterComposition(from: textView)
                return
            }
            if textView.string != text {
                scheduleUserSync(from: textView)
            } else {
                updateSelectionFromTextView(textView)
            }
        }

        package func textDidEndEditing(_ notification: Notification) {
            guard !isApplyingSwiftUIUpdate,
                  let textView = notification.object as? NSTextView else { return }
            cancelPendingSync()
            text = textView.string
            publishSelectionIfNeeded(textView.selectedRange())
            lastSeenTextBinding = textView.string
        }

        package func cancelPendingSync() {
            pendingSyncWorkItem?.cancel()
            pendingSyncWorkItem = nil
            pendingText = nil
            pendingSelection = nil
        }

        private func scheduleUserSync(from textView: NSTextView) {
            pendingText = textView.string
            pendingSelection = textView.selectedRange()
            pendingSyncWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self, weak textView] in
                self?.flushPendingUserSync(from: textView)
            }
            pendingSyncWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + userSyncDelay, execute: workItem)
        }

        private func scheduleUserSyncAfterComposition(from textView: NSTextView) {
            pendingText = textView.string
            pendingSelection = textView.selectedRange()
            rescheduleAfterComposition(textView)
        }

        private func flushPendingUserSync(from textView: NSTextView?) {
            if let textView, textView.hasMarkedText() {
                pendingText = textView.string
                pendingSelection = textView.selectedRange()
                rescheduleAfterComposition(textView)
                return
            }

            let nextText = textView?.string ?? pendingText
            let nextSelection = textView?.selectedRange() ?? pendingSelection
            guard let nextText, let nextSelection else {
                pendingSyncWorkItem = nil
                return
            }

            text = nextText
            publishSelectionIfNeeded(nextSelection)
            lastSeenTextBinding = nextText
            self.pendingText = nil
            self.pendingSelection = nil
            pendingSyncWorkItem = nil
        }

        private func rescheduleAfterComposition(_ textView: NSTextView) {
            pendingSyncWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                self?.flushPendingUserSync(from: textView)
            }
            pendingSyncWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + compositionRetryDelay, execute: workItem)
        }

        private func updateSelectionFromTextView(_ textView: NSTextView) {
            publishSelectionIfNeeded(textView.selectedRange())
        }

        private func publishSelectionIfNeeded(_ range: NSRange) {
            guard shouldPublishSelection(range) else { return }
            selectedRange = range
            lastSeenSelectionBinding = range
        }

        private func shouldPublishSelection(_ range: NSRange) -> Bool {
            range.length > 0 || selectedRange.length > 0
        }

        package func shouldApplySelectionFromBinding(_ range: NSRange, textView: NSTextView) -> Bool {
            guard isUserEditing(textView) else { return true }
            return range.length > 0 || selectedRange.length > 0
        }
    }
}
