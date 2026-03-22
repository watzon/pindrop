//
//  SearchableDropdown.swift
//  Pindrop
//
//  Created on 2026-02-15.
//

import AppKit
import SwiftUI
import Foundation

public protocol SearchableDropdownItem: Identifiable {
   var displayName: String { get }
   var searchableValues: [String] { get }
}

public extension SearchableDropdownItem {
   var searchableValues: [String] { [displayName] }
}

public struct SelectFieldOption: Identifiable, Hashable {
   public let id: String
   public let displayName: String
   public let isEnabled: Bool

   public init(id: String, displayName: String, isEnabled: Bool = true) {
      self.id = id
      self.displayName = displayName
      self.isEnabled = isEnabled
   }
}

public struct SelectField: View {
   let options: [SelectFieldOption]
   let placeholder: String
   @Binding var selection: String
   @Environment(\.locale) private var locale
   @State private var isOpen = false
   @State private var hoveredOptionID: String?

   public init(
      options: [SelectFieldOption],
      selection: Binding<String>,
      placeholder: String = "Select an option"
   ) {
      self.options = options
      self._selection = selection
      self.placeholder = placeholder
   }

   private var localizedPlaceholder: String {
      localized(placeholder, locale: locale)
   }

   public var body: some View {
      Button {
         isOpen.toggle()
      } label: {
         HStack(spacing: 8) {
            Text(selectedLabel)
               .lineLimit(1)
               .truncationMode(.tail)

            Spacer(minLength: 0)

            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
               .font(.caption.weight(.semibold))
               .foregroundStyle(AppColors.textSecondary)
               .allowsHitTesting(false)
         }
         .frame(maxWidth: .infinity, alignment: .leading)
         .contentShape(RoundedRectangle(cornerRadius: AISettingsFieldStyle.cornerRadius))
         .aiSettingsInputChrome(isFocused: isOpen, trailingInset: 2)
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
         FloatingDropdownPresenter(
            isPresented: $isOpen,
            panelHeight: dropdownHeight,
            content: { width in
               AnyView(
                  dropdown
                     .frame(width: width)
               )
            },
            onDismiss: {
               isOpen = false
            }
         )
      }
   }

   private var selectedLabel: String {
      options.first(where: { $0.id == selection })?.displayName ?? localizedPlaceholder
   }

   private var dropdown: some View {
      VStack(spacing: 0) {
         ForEach(options) { option in
            Button {
               guard option.isEnabled else { return }
               selection = option.id
               isOpen = false
            } label: {
               HStack(spacing: 0) {
                  Text(option.displayName)
                     .font(.body)
                     .foregroundStyle(option.isEnabled ? AppColors.textPrimary : AppColors.textSecondary)

                  Spacer(minLength: 0)

                  if option.id == selection {
                     Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                  }
               }
               .frame(
                  maxWidth: .infinity,
                  minHeight: AISettingsFieldStyle.minHeight,
                  alignment: .leading
                )
                .padding(.horizontal, AISettingsFieldStyle.horizontalPadding)
                .background(rowBackground(isHovered: hoveredOptionID == option.id, isSelected: option.id == selection))
                .contentShape(Rectangle())
             }
             .frame(maxWidth: .infinity, alignment: .leading)
             .buttonStyle(.plain)
             .disabled(!option.isEnabled)
             .opacity(option.isEnabled ? 1.0 : 0.55)
             .onHover { isHovered in
                hoveredOptionID = isHovered ? option.id : nil
             }
          }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
         AISettingsFieldStyle.backgroundColor,
         in: RoundedRectangle(cornerRadius: AISettingsFieldStyle.cornerRadius)
      )
      .overlay {
         RoundedRectangle(cornerRadius: AISettingsFieldStyle.cornerRadius)
            .stroke(AISettingsFieldStyle.borderColor, lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
   }

   private var dropdownHeight: CGFloat {
      CGFloat(max(options.count, 1)) * AISettingsFieldStyle.minHeight
   }

   @ViewBuilder
   private func rowBackground(isHovered: Bool, isSelected: Bool) -> some View {
      if isHovered || isSelected {
         RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? AppColors.accent.opacity(0.18) : AppColors.surfaceBackground)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
      } else {
         Color.clear
      }
   }
}

private enum AISettingsFieldStyle {
   static let cornerRadius: CGFloat = 8
   static let minHeight: CGFloat = 40
   static let horizontalPadding: CGFloat = 12
   static let verticalPadding: CGFloat = 10
   static let dropdownSpacing: CGFloat = 6
   static let dropdownMaxHeight: CGFloat = 220
   static let backgroundColor = AppColors.inputBackground
   static let borderColor = AppColors.inputBorder
   static let focusedBorderColor = AppColors.inputBorderFocused
}

extension View {
   func aiSettingsInputChrome(isFocused: Bool = false, trailingInset: CGFloat = 0) -> some View {
      self
         .font(.body)
         .foregroundStyle(AppColors.textPrimary)
         .padding(.horizontal, AISettingsFieldStyle.horizontalPadding)
         .padding(.vertical, AISettingsFieldStyle.verticalPadding)
         .padding(.trailing, trailingInset)
         .frame(
            maxWidth: .infinity,
            minHeight: AISettingsFieldStyle.minHeight,
            alignment: .leading
         )
         .background(
            AISettingsFieldStyle.backgroundColor,
            in: RoundedRectangle(cornerRadius: AISettingsFieldStyle.cornerRadius)
         )
         .overlay {
            RoundedRectangle(cornerRadius: AISettingsFieldStyle.cornerRadius)
               .stroke(
                  isFocused ? AISettingsFieldStyle.focusedBorderColor : AISettingsFieldStyle.borderColor,
                  lineWidth: 1
               )
         }
   }
}

public struct SearchableDropdown<Item: SearchableDropdownItem>: View where Item.ID == String {
    let items: [Item]
    let placeholder: String
    let emptyMessage: String
    let searchPlaceholder: String
    @Binding var selection: Item.ID?

    @Environment(\.locale) private var locale
    @FocusState private var isFieldFocused: Bool
    @State private var query = ""
    @State private var isOpen = false
    @State private var closeTask: Task<Void, Never>?
    @State private var hoveredItemID: Item.ID?

    public init(
       items: [Item],
       selection: Binding<Item.ID?>,
       placeholder: String = "Select an item",
       emptyMessage: String = "No items found.",
       searchPlaceholder: String = "Search..."
    ) {
       self.items = items
       self._selection = selection
       self.placeholder = placeholder
       self.emptyMessage = emptyMessage
       self.searchPlaceholder = searchPlaceholder
    }

    private var localizedEmptyMessage: String {
        localized(emptyMessage, locale: locale)
    }

    private var localizedSearchPlaceholder: String {
        localized(searchPlaceholder, locale: locale)
    }

   public var body: some View {
      field
         .background {
            FloatingDropdownPresenter(
               isPresented: $isOpen,
               panelHeight: dropdownHeight,
               content: { width in
                  AnyView(
                     dropdown
                        .frame(width: width)
                  )
               },
               onDismiss: {
                  dismissDropdown()
               }
            )
         }
         .onAppear {
            syncQueryFromSelection()
         }
          .onChange(of: selection) { _, _ in
             if !isFieldFocused {
                syncQueryFromSelection()
            }
         }
         .onChange(of: isFieldFocused) { _, isFocused in
            closeTask?.cancel()

            if isFocused {
               isOpen = true
            } else {
               scheduleClose()
            }
         }
   }

   private var field: some View {
      HStack(spacing: 8) {
          TextField(
             query.isEmpty ? placeholder : localizedSearchPlaceholder,
             text: $query,
             prompt: Text(placeholder).foregroundStyle(AppColors.textSecondary)
          )
         .textFieldStyle(.plain)
         .focused($isFieldFocused)
         .onTapGesture {
            openDropdown()
         }
         .onChange(of: query) { _, _ in
            if isFieldFocused {
               isOpen = true
            }
         }
         .onSubmit {
            commitCurrentQuery()
            closeDropdown()
         }

         Spacer(minLength: 0)

         Image(systemName: isOpen ? "chevron.up" : "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary)
            .allowsHitTesting(false)
      }
      .contentShape(RoundedRectangle(cornerRadius: AISettingsFieldStyle.cornerRadius))
      .onTapGesture {
         openDropdown()
      }
      .aiSettingsInputChrome(isFocused: isFieldFocused, trailingInset: 2)
   }

   private var dropdown: some View {
      VStack(spacing: 0) {
          if filteredItems.isEmpty {
             Text(localizedEmptyMessage)
                .font(.body)
                .foregroundStyle(AppColors.textSecondary)
               .frame(
                  maxWidth: .infinity,
                  minHeight: AISettingsFieldStyle.minHeight,
                  alignment: .leading
               )
               .padding(.horizontal, AISettingsFieldStyle.horizontalPadding)
         } else {
            if filteredItems.count > 5 {
               ScrollView {
                  dropdownRows
               }
               .frame(maxHeight: AISettingsFieldStyle.dropdownMaxHeight)
            } else {
               dropdownRows
            }
         }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
         AISettingsFieldStyle.backgroundColor,
         in: RoundedRectangle(cornerRadius: AISettingsFieldStyle.cornerRadius)
      )
      .overlay {
         RoundedRectangle(cornerRadius: AISettingsFieldStyle.cornerRadius)
            .stroke(AISettingsFieldStyle.borderColor, lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
   }

   private var dropdownRows: some View {
      LazyVStack(alignment: .leading, spacing: 0) {
         ForEach(filteredItems) { item in
            Button {
               select(item)
            } label: {
               HStack(spacing: 0) {
                  Text(item.displayName)
                     .font(.body)
                     .foregroundStyle(AppColors.textPrimary)

                  Spacer(minLength: 0)
               }
                .frame(
                   maxWidth: .infinity,
                   minHeight: AISettingsFieldStyle.minHeight,
                   alignment: .leading
                )
                .padding(.horizontal, AISettingsFieldStyle.horizontalPadding)
                .background(rowBackground(isHovered: hoveredItemID == item.id, isSelected: selection == item.id))
                .contentShape(Rectangle())
             }
             .frame(maxWidth: .infinity, alignment: .leading)
             .buttonStyle(.plain)
             .onHover { isHovered in
                hoveredItemID = isHovered ? item.id : nil
             }
          }
       }
    }

   private var filteredItems: [Item] {
      let normalizedQuery = normalizedFilterQuery
      guard !normalizedQuery.isEmpty else { return items }

      return items.filter { item in
         item.searchableValues.contains { value in
            value.localizedCaseInsensitiveContains(normalizedQuery)
         }
      }
   }

   private var normalizedFilterQuery: String {
      let selectedName = selectedItem?.displayName ?? ""
      let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

      if isFieldFocused, trimmedQuery == selectedName {
         return ""
      }

      return trimmedQuery
   }

   private var selectedItem: Item? {
      guard let selection else { return nil }
      return items.first(where: { $0.id == selection })
   }

   private var dropdownHeight: CGFloat {
      let rowCount = max(filteredItems.count, 1)
      let visibleRows = min(rowCount, 5)
      let rowHeight = AISettingsFieldStyle.minHeight
      return min(CGFloat(visibleRows) * rowHeight, AISettingsFieldStyle.dropdownMaxHeight)
   }

   private func openDropdown() {
      closeTask?.cancel()
      isOpen = true
      isFieldFocused = true
   }

   private func closeDropdown() {
      closeTask?.cancel()
      isOpen = false
      isFieldFocused = false
   }

   private func dismissDropdown() {
      closeTask?.cancel()
      commitCurrentQuery()
      isOpen = false
      isFieldFocused = false
   }

   private func scheduleClose() {
      closeTask?.cancel()
      closeTask = Task {
         try? await Task.sleep(for: .milliseconds(120))
         guard !Task.isCancelled else { return }

         await MainActor.run {
            commitCurrentQuery()
            isOpen = false
         }
      }
   }

   private func commitCurrentQuery() {
      let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

      guard !trimmedQuery.isEmpty else {
         selection = nil
         query = ""
         return
      }

      if let matchedItem = items.first(where: { exactMatch(trimmedQuery, item: $0) }) {
         selection = matchedItem.id
         query = matchedItem.displayName
      } else {
         syncQueryFromSelection()
      }
   }

   private func select(_ item: Item) {
      closeTask?.cancel()
      selection = item.id
      query = item.displayName
      isOpen = false
      isFieldFocused = false
   }

   private func syncQueryFromSelection() {
      query = selectedItem?.displayName ?? ""
   }

    private func exactMatch(_ query: String, item: Item) -> Bool {
       item.displayName.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
          || item.id.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    @ViewBuilder
    private func rowBackground(isHovered: Bool, isSelected: Bool) -> some View {
       if isHovered || isSelected {
          RoundedRectangle(cornerRadius: 6)
             .fill(isSelected ? AppColors.accent.opacity(0.18) : AppColors.surfaceBackground)
             .padding(.horizontal, 4)
             .padding(.vertical, 2)
       } else {
          Color.clear
       }
    }
}

private struct FloatingDropdownPresenter: NSViewRepresentable {
   @Binding var isPresented: Bool
   let panelHeight: CGFloat
   let content: (CGFloat) -> AnyView
   let onDismiss: () -> Void

   func makeCoordinator() -> Coordinator {
      Coordinator(parent: self)
   }

   func makeNSView(context: Context) -> NSView {
      let view = NSView(frame: .zero)
      view.postsFrameChangedNotifications = true
      context.coordinator.anchorView = view
      return view
   }

   func updateNSView(_ nsView: NSView, context: Context) {
      context.coordinator.parent = self
      context.coordinator.updatePanel(from: nsView)
   }

   static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
      coordinator.hidePanel()
   }

   final class Coordinator: NSObject {
      var parent: FloatingDropdownPresenter
      weak var anchorView: NSView?
      private var panel: NSPanel?
      private var hostingView: NSHostingView<AnyView>?
      private var localMonitor: Any?
      private var globalMonitor: Any?
      private var resignObserver: NSObjectProtocol?

      init(parent: FloatingDropdownPresenter) {
         self.parent = parent
      }

      func updatePanel(from anchorView: NSView) {
         guard let window = anchorView.window else { return }

         if parent.isPresented {
            let panel = ensurePanel(attachedTo: window)
            installResignObserver(for: window)
            let width = max(anchorView.bounds.width, 160)
            let contentSize = NSSize(width: width, height: parent.panelHeight)

            if let hostingView {
               hostingView.rootView = parent.content(width)
               hostingView.frame = CGRect(origin: .zero, size: contentSize)
            } else {
               let hostingView = NSHostingView(rootView: parent.content(width))
               hostingView.frame = CGRect(origin: .zero, size: contentSize)
               panel.contentView = hostingView
               self.hostingView = hostingView
            }

            panel.setContentSize(contentSize)
            panel.setFrame(frame(for: anchorView, size: contentSize), display: true)
            panel.orderFront(nil)
            installEventMonitors()
         } else {
            hidePanel()
         }
      }

      func hidePanel() {
         if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
         }

         removeEventMonitors()
         removeResignObserver()
      }

      private func ensurePanel(attachedTo window: NSWindow) -> NSPanel {
         if let panel {
            if panel.parent != window {
               panel.parent?.removeChildWindow(panel)
               window.addChildWindow(panel, ordered: .above)
            }
            return panel
         }

         let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
         )
         panel.backgroundColor = .clear
         panel.isOpaque = false
         panel.hasShadow = true
         panel.hidesOnDeactivate = false
         panel.level = .floating
         panel.collectionBehavior = [.moveToActiveSpace, .transient]
         panel.isMovable = false
         panel.ignoresMouseEvents = false
         panel.becomesKeyOnlyIfNeeded = true

         window.addChildWindow(panel, ordered: .above)
         self.panel = panel
         return panel
      }

      private func frame(for anchorView: NSView, size: NSSize) -> CGRect {
         guard let window = anchorView.window else {
            return CGRect(origin: .zero, size: size)
         }

         let rectInWindow = anchorView.convert(anchorView.bounds, to: nil)
         let rectOnScreen = window.convertToScreen(rectInWindow)

         return CGRect(
            x: rectOnScreen.minX,
            y: rectOnScreen.minY - AISettingsFieldStyle.dropdownSpacing - size.height,
            width: size.width,
            height: size.height
         )
      }

      private func installEventMonitors() {
         guard localMonitor == nil, globalMonitor == nil else { return }

         localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handle(event: event)
            return event
         }

         globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handle(event: event)
         }
      }

      private func removeEventMonitors() {
         if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
         }

         if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
         }
      }

      private func installResignObserver(for window: NSWindow) {
         guard resignObserver == nil else { return }

         resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
         ) { [weak self] _ in
            self?.dismissAndBlurField()
         }
      }

      private func removeResignObserver() {
         if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
         }
      }

      private func handle(event: NSEvent) {
         guard parent.isPresented else { return }
         guard let panel, let anchorView, let window = anchorView.window else { return }

         let locationInScreen: NSPoint
         if let eventWindow = event.window {
            locationInScreen = eventWindow.convertPoint(toScreen: event.locationInWindow)
         } else {
            locationInScreen = NSEvent.mouseLocation
         }

         let anchorRect = window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
         if panel.frame.contains(locationInScreen) || anchorRect.contains(locationInScreen) {
            return
         }

         DispatchQueue.main.async { [weak self] in
            self?.dismissAndBlurField()
         }
      }

      private func dismissAndBlurField() {
         guard let anchorView, let window = anchorView.window else {
            parent.onDismiss()
            return
         }

         window.makeFirstResponder(nil)
         parent.onDismiss()
      }
   }
}
