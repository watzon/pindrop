//
//  MarkdownEditor.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import SwiftUI
import AppKit

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = MarkdownTextView()
        
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor(AppColors.textPrimary)
        
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        context.coordinator.textView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.applyMarkdownStyling()
            textView.selectedRanges = selectedRanges
        }
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: MarkdownTextView?
        
        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            parent.text = textView.string
            textView.applyMarkdownStyling()
        }
    }
}

class MarkdownTextView: NSTextView {
    
    private let baseFont = NSFont.systemFont(ofSize: 14)
    private let headingFonts: [NSFont] = [
        NSFont.systemFont(ofSize: 24, weight: .bold),
        NSFont.systemFont(ofSize: 20, weight: .bold),
        NSFont.systemFont(ofSize: 18, weight: .semibold),
        NSFont.systemFont(ofSize: 16, weight: .semibold),
        NSFont.systemFont(ofSize: 14, weight: .semibold),
        NSFont.systemFont(ofSize: 14, weight: .medium)
    ]
    private let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    
    func applyMarkdownStyling() {
        guard let textStorage = textStorage else { return }
        
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string
        
        textStorage.beginEditing()
        
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor(AppColors.textPrimary)
        ], range: fullRange)
        
        applyHeadings(to: textStorage, text: text)
        applyBold(to: textStorage, text: text)
        applyItalic(to: textStorage, text: text)
        applyBoldItalic(to: textStorage, text: text)
        applyInlineCode(to: textStorage, text: text)
        applyStrikethrough(to: textStorage, text: text)
        applyLinks(to: textStorage, text: text)
        applyBlockquotes(to: textStorage, text: text)
        applyListItems(to: textStorage, text: text)
        
        textStorage.endEditing()
    }
    
    private func applyHeadings(to textStorage: NSTextStorage, text: String) {
        let pattern = "^(#{1,6})\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let hashRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            let level = min(hashRange.length - 1, 5)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary)
            ], range: hashRange)
            
            textStorage.addAttributes([
                .font: headingFonts[level],
                .foregroundColor: NSColor(AppColors.textPrimary)
            ], range: contentRange)
        }
    }
    
    private func applyBold(to textStorage: NSTextStorage, text: String) {
        let pattern = "\\*\\*(?!\\*)(.+?)\\*\\*(?!\\*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            
            let syntaxStart = NSRange(location: fullRange.location, length: 2)
            let syntaxEnd = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxStart)
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxEnd)
            
            textStorage.addAttributes([
                .font: NSFont.boldSystemFont(ofSize: 14)
            ], range: contentRange)
        }
    }
    
    private func applyItalic(to textStorage: NSTextStorage, text: String) {
        let pattern = "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            
            let syntaxStart = NSRange(location: fullRange.location, length: 1)
            let syntaxEnd = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxStart)
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxEnd)
            
            textStorage.addAttributes([
                .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            ], range: contentRange)
        }
    }
    
    private func applyBoldItalic(to textStorage: NSTextStorage, text: String) {
        let pattern = "\\*\\*\\*(.+?)\\*\\*\\*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            
            let syntaxStart = NSRange(location: fullRange.location, length: 3)
            let syntaxEnd = NSRange(location: fullRange.location + fullRange.length - 3, length: 3)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxStart)
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxEnd)
            
            let boldItalicFont = NSFontManager.shared.convert(
                NSFont.boldSystemFont(ofSize: 14),
                toHaveTrait: .italicFontMask
            )
            textStorage.addAttributes([
                .font: boldItalicFont
            ], range: contentRange)
        }
    }
    
    private func applyInlineCode(to textStorage: NSTextStorage, text: String) {
        let pattern = "`([^`]+)`"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            
            let syntaxStart = NSRange(location: fullRange.location, length: 1)
            let syntaxEnd = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxStart)
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxEnd)
            
            textStorage.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor(AppColors.accent),
                .backgroundColor: NSColor(AppColors.surfaceBackground)
            ], range: contentRange)
        }
    }
    
    private func applyStrikethrough(to textStorage: NSTextStorage, text: String) {
        let pattern = "~~(.+?)~~"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            
            let syntaxStart = NSRange(location: fullRange.location, length: 2)
            let syntaxEnd = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxStart)
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: syntaxEnd)
            
            textStorage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor(AppColors.textSecondary)
            ], range: contentRange)
        }
    }
    
    private func applyLinks(to textStorage: NSTextStorage, text: String) {
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let fullRange = match.range(at: 0)
            let textRange = match.range(at: 1)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.accent),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: textRange)
            
            let bracketStart = NSRange(location: fullRange.location, length: 1)
            let bracketEnd = NSRange(location: textRange.location + textRange.length, length: 1)
            let urlPart = NSRange(location: bracketEnd.location + 1, length: fullRange.length - textRange.length - 3)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: bracketStart)
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: bracketEnd)
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textTertiary).withAlphaComponent(0.5)
            ], range: urlPart)
        }
    }
    
    private func applyBlockquotes(to textStorage: NSTextStorage, text: String) {
        let pattern = "^>\\s*(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let fullRange = match.range(at: 0)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.textSecondary),
                .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            ], range: fullRange)
        }
    }
    
    private func applyListItems(to textStorage: NSTextStorage, text: String) {
        let pattern = "^(\\s*)([-*+]|\\d+\\.)\\s"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let bulletRange = match.range(at: 2)
            
            textStorage.addAttributes([
                .foregroundColor: NSColor(AppColors.accent)
            ], range: bulletRange)
        }
    }
}

#Preview {
    MarkdownEditor(text: .constant("""
    # Heading 1
    ## Heading 2
    
    This is **bold** and this is *italic* and this is ***bold italic***.
    
    Here's some `inline code` in a sentence.
    
    ~~Strikethrough text~~
    
    [Link text](https://example.com)
    
    > This is a blockquote
    
    - List item 1
    - List item 2
    * Another item
    
    1. Numbered item
    2. Another numbered
    """))
    .frame(width: 500, height: 400)
    .padding()
}
