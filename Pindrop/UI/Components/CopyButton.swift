import SwiftUI
import AppKit

struct CopyButton: View {
    let text: String
    var label: String? = nil
    var size: CGFloat = 12
    var showBackground: Bool = false
    
    @State private var isCopied = false
    
    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: size))
                    .foregroundStyle(isCopied ? .green : AppColors.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                
                if let label {
                    Text(isCopied ? "Copied!" : label)
                        .font(.caption)
                        .foregroundStyle(isCopied ? .green : AppColors.textTertiary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, showBackground ? 8 : 0)
            .padding(.vertical, showBackground ? 4 : 0)
            .background(
                showBackground
                    ? AnyShapeStyle(isCopied ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                    : AnyShapeStyle(Color.clear),
                in: Capsule()
            )
            .animation(.easeInOut(duration: 0.2), value: isCopied)
        }
        .buttonStyle(.plain)
        .help(isCopied ? "Copied!" : "Copy to clipboard")
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

struct CopyButtonWithCallback: View {
    var label: String? = nil
    var size: CGFloat = 12
    var showBackground: Bool = false
    let onCopy: () -> Void
    
    @State private var isCopied = false
    
    var body: some View {
        Button {
            performCopy()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: size))
                    .foregroundStyle(isCopied ? .green : AppColors.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                
                if let label {
                    Text(isCopied ? "Copied!" : label)
                        .font(.caption)
                        .foregroundStyle(isCopied ? .green : AppColors.textTertiary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, showBackground ? 8 : 0)
            .padding(.vertical, showBackground ? 4 : 0)
            .background(
                showBackground
                    ? AnyShapeStyle(isCopied ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                    : AnyShapeStyle(Color.clear),
                in: Capsule()
            )
            .animation(.easeInOut(duration: 0.2), value: isCopied)
        }
        .buttonStyle(.plain)
        .help(isCopied ? "Copied!" : "Copy to clipboard")
    }
    
    private func performCopy() {
        onCopy()
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview("Copy Button - Icon Only") {
    CopyButton(text: "Hello, World!")
        .padding()
}

#Preview("Copy Button - With Label") {
    CopyButton(text: "Hello, World!", label: "Copy", showBackground: true)
        .padding()
}

#Preview("Copy Button - Large") {
    CopyButton(text: "Hello, World!", label: "Copy Text", size: 16, showBackground: true)
        .padding()
}
