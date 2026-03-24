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
         AnchoredFloatingPanelPresenter(
            isPresented: isOpen,
            direction: .down,
            verticalSpacing: AISettingsFieldStyle.dropdownSpacing,
            onDismiss: {
               isOpen = false
            }
         ) { width in
            dropdown
               .frame(width: width)
         }
      }
      .zIndex(isOpen ? 10 : 0)
   }

   private var selectedLabel: String {
      options.first(where: { $0.id == selection })?.displayName ?? localizedPlaceholder
   }

   private var selectFieldOptionRows: some View {
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

   private var dropdown: some View {
      Group {
         if options.count > 5 {
            ScrollView {
               VStack(spacing: 0) {
                  selectFieldOptionRows
               }
            }
            .frame(maxHeight: AISettingsFieldStyle.dropdownMaxHeight)
         } else {
            VStack(spacing: 0) {
               selectFieldOptionRows
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
            AnchoredFloatingPanelPresenter(
               isPresented: isOpen,
               direction: .down,
               verticalSpacing: AISettingsFieldStyle.dropdownSpacing,
               wantsKeyPanel: true,
               onDismiss: {
                  dismissDropdown()
               }
            ) { width in
               dropdown
                  .frame(width: width)
            }
         }
         .zIndex(isOpen ? 10 : 0)
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

// MARK: - Anchored floating panel (AppKit)

private enum FloatingPanelDirection {
   case up
   case down
}

private enum FloatingPanelHorizontalAlignment {
   case leading
   case trailing
}

/// Presents SwiftUI content in a borderless child `NSPanel` positioned from an anchor view’s
/// on-screen frame. Repositions when the anchor scrolls, the window moves or resizes, or the
/// anchor’s layout changes, and clamps the panel into the host window’s content rect.
private struct AnchoredFloatingPanelPresenter<Content: View>: NSViewRepresentable {
   var isPresented: Bool
   var direction: FloatingPanelDirection
   var horizontalAlignment: FloatingPanelHorizontalAlignment
   var verticalSpacing: CGFloat
   var wantsKeyPanel: Bool
   var onDismiss: () -> Void
   @ViewBuilder var content: (CGFloat) -> Content

   init(
      isPresented: Bool,
      direction: FloatingPanelDirection = .down,
      horizontalAlignment: FloatingPanelHorizontalAlignment = .leading,
      verticalSpacing: CGFloat = 6,
      wantsKeyPanel: Bool = false,
      onDismiss: @escaping () -> Void,
      @ViewBuilder content: @escaping (CGFloat) -> Content
   ) {
      self.isPresented = isPresented
      self.direction = direction
      self.horizontalAlignment = horizontalAlignment
      self.verticalSpacing = verticalSpacing
      self.wantsKeyPanel = wantsKeyPanel
      self.onDismiss = onDismiss
      self.content = content
   }

   func makeCoordinator() -> Coordinator {
      Coordinator()
   }

   func makeNSView(context: Context) -> NSView {
      let view = NSView(frame: .zero)
      view.postsFrameChangedNotifications = true
      context.coordinator.anchorView = view
      return view
   }

   func updateNSView(_ nsView: NSView, context: Context) {
      context.coordinator.anchorView = nsView
      let width = max(nsView.bounds.width, 160)
      context.coordinator.update(
         isPresented: isPresented,
         direction: direction,
         horizontalAlignment: horizontalAlignment,
         verticalSpacing: verticalSpacing,
         wantsKeyPanel: wantsKeyPanel,
         onDismiss: onDismiss,
         content: AnyView(content(width))
      )
   }

   static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
      coordinator.dismiss()
   }

   final class Coordinator: NSObject {
      weak var anchorView: NSView?
      private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
      private var panel: DropdownFloatingPanel?
      private var localMonitor: Any?
      private var globalMonitor: Any?
      private var resignObserver: NSObjectProtocol?
      private var layoutObservers: [NSObjectProtocol] = []
      private var onDismiss: (() -> Void)?

      private var isPresented = false
      private var direction: FloatingPanelDirection = .down
      private var horizontalAlignment: FloatingPanelHorizontalAlignment = .leading
      private var verticalSpacing: CGFloat = 6
      private var wantsKeyPanel = false

      private weak var observedClipView: NSClipView?
      private var clipViewPriorPostsBounds = false

      func update(
         isPresented: Bool,
         direction: FloatingPanelDirection,
         horizontalAlignment: FloatingPanelHorizontalAlignment,
         verticalSpacing: CGFloat,
         wantsKeyPanel: Bool,
         onDismiss: @escaping () -> Void,
         content: AnyView
      ) {
         guard let anchorView else {
            dismiss()
            return
         }

         self.isPresented = isPresented
         self.direction = direction
         self.horizontalAlignment = horizontalAlignment
         self.verticalSpacing = verticalSpacing
         self.wantsKeyPanel = wantsKeyPanel
         self.onDismiss = onDismiss

         if isPresented {
            hostingController.rootView = content
            presentIfNeeded(from: anchorView)
            installLayoutObservers(for: anchorView)
            installResignObserverIfNeeded(for: anchorView)
            repositionPanel()
            installEventMonitors()
         } else {
            dismiss()
         }
      }

      func dismiss() {
         removeLayoutObservers()
         removeEventMonitors()
         removeResignObserver()
         restoreClipViewBoundsPosting()
         if let panel,
            let parent = panel.parent {
            parent.removeChildWindow(panel)
         }
         panel?.orderOut(nil)
         panel = nil
      }

      private func dismissAndNotify() {
         onDismiss?()
         dismiss()
      }

      private func dismissAndBlurField() {
         if let anchorView, let window = anchorView.window {
            window.makeFirstResponder(nil)
         }
         onDismiss?()
         dismiss()
      }

      private func presentIfNeeded(from anchorView: NSView) {
         if panel == nil {
            let panel = DropdownFloatingPanel(
               contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
               styleMask: [.borderless, .nonactivatingPanel],
               backing: .buffered,
               defer: true
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = true
            panel.ignoresMouseEvents = false
            panel.contentView = hostingController.view
            self.panel = panel
         }

         if let panel,
            let window = anchorView.window,
            panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
         }

         panel?.orderFrontRegardless()
         if wantsKeyPanel {
            panel?.makeKey()
         }
      }

      private func repositionPanel() {
         guard let anchorView,
               let panel,
               let window = anchorView.window,
               isPresented
         else {
            return
         }

         hostingController.view.layoutSubtreeIfNeeded()
         var fittingSize = hostingController.view.fittingSize
         if fittingSize.width.isNaN || fittingSize.width <= 0 { fittingSize.width = 160 }
         if fittingSize.height.isNaN || fittingSize.height <= 0 { fittingSize.height = 1 }

         let anchorFrameInWindow = anchorView.convert(anchorView.bounds, to: nil)
         let anchorOnScreen = window.convertToScreen(anchorFrameInWindow)
         let windowContent = windowContentRectOnScreen(for: window)

         let origin = panelOrigin(
            anchorFrameOnScreen: anchorOnScreen,
            panelSize: fittingSize,
            direction: direction,
            horizontalAlignment: horizontalAlignment,
            verticalSpacing: verticalSpacing
         )
         var frame = CGRect(origin: origin, size: fittingSize)
         frame = adjustedFrameForVisibility(
            frame,
            anchorFrame: anchorOnScreen,
            direction: direction,
            verticalSpacing: verticalSpacing,
            windowContent: windowContent
         )

         hostingController.view.frame = CGRect(origin: .zero, size: frame.size)
         panel.setFrame(frame, display: true)
      }

      private func windowContentRectOnScreen(for window: NSWindow) -> CGRect {
         guard let contentView = window.contentView else {
            return window.frame
         }
         let rectInWindow = contentView.convert(contentView.bounds, to: nil)
         return window.convertToScreen(rectInWindow)
      }

      private func panelOrigin(
         anchorFrameOnScreen: CGRect,
         panelSize: CGSize,
         direction: FloatingPanelDirection,
         horizontalAlignment: FloatingPanelHorizontalAlignment,
         verticalSpacing: CGFloat
      ) -> CGPoint {
         let x = panelOriginX(
            for: horizontalAlignment,
            anchorFrameOnScreen: anchorFrameOnScreen,
            panelWidth: panelSize.width
         )
         let y = panelOriginY(
            for: direction,
            anchorFrameOnScreen: anchorFrameOnScreen,
            panelHeight: panelSize.height,
            verticalSpacing: verticalSpacing
         )
         return CGPoint(x: x, y: y)
      }

      private func panelOriginX(
         for horizontalAlignment: FloatingPanelHorizontalAlignment,
         anchorFrameOnScreen: CGRect,
         panelWidth: CGFloat
      ) -> CGFloat {
         switch horizontalAlignment {
         case .leading:
            anchorFrameOnScreen.minX
         case .trailing:
            anchorFrameOnScreen.maxX - panelWidth
         }
      }

      private func panelOriginY(
         for direction: FloatingPanelDirection,
         anchorFrameOnScreen: CGRect,
         panelHeight: CGFloat,
         verticalSpacing: CGFloat
      ) -> CGFloat {
         switch direction {
         case .up:
            anchorFrameOnScreen.maxY + verticalSpacing
         case .down:
            anchorFrameOnScreen.minY - verticalSpacing - panelHeight
         }
      }

      private func adjustedFrameForVisibility(
         _ proposed: CGRect,
         anchorFrame: CGRect,
         direction: FloatingPanelDirection,
         verticalSpacing: CGFloat,
         windowContent: CGRect
      ) -> CGRect {
         let margin: CGFloat = 8
         let bounds = windowContent.insetBy(dx: margin, dy: margin)
         var frame = proposed

         if frame.width > bounds.width {
            frame.size.width = bounds.width
         }
         if frame.height > bounds.height {
            frame.size.height = bounds.height
         }

         if frame.maxX > bounds.maxX {
            frame.origin.x = bounds.maxX - frame.width
         }
         if frame.minX < bounds.minX {
            frame.origin.x = bounds.minX
         }

         if !verticalRangeContains(frame, bounds) {
            let flippedY: CGFloat
            switch direction {
            case .down:
               flippedY = anchorFrame.maxY + verticalSpacing
            case .up:
               flippedY = anchorFrame.minY - verticalSpacing - frame.height
            }
            frame.origin.y = flippedY
         }

         if !verticalRangeContains(frame, bounds) {
            if frame.height <= bounds.height {
               if frame.minY < bounds.minY {
                  frame.origin.y = bounds.minY
               }
               if frame.maxY > bounds.maxY {
                  frame.origin.y = bounds.maxY - frame.height
               }
            } else {
               frame.origin.y = bounds.minY
               frame.size.height = bounds.height
            }
         }

         return frame
      }

      private func verticalRangeContains(_ frame: CGRect, _ bounds: CGRect) -> Bool {
         frame.minY >= bounds.minY - 0.5 && frame.maxY <= bounds.maxY + 0.5
      }

      private func installLayoutObservers(for anchorView: NSView) {
         removeLayoutObservers()

         let center = NotificationCenter.default

         let frameToken = center.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: anchorView,
            queue: .main
         ) { [weak self] _ in
            self?.repositionPanel()
         }
         layoutObservers.append(frameToken)

         if let window = anchorView.window {
            let moveToken = center.addObserver(
               forName: NSWindow.didMoveNotification,
               object: window,
               queue: .main
            ) { [weak self] _ in
               self?.repositionPanel()
            }
            let resizeToken = center.addObserver(
               forName: NSWindow.didResizeNotification,
               object: window,
               queue: .main
            ) { [weak self] _ in
               self?.repositionPanel()
            }
            layoutObservers.append(contentsOf: [moveToken, resizeToken])
         }

         if let scrollView = anchorView.enclosingScrollView {
            let clipView = scrollView.contentView
            observedClipView = clipView
            clipViewPriorPostsBounds = clipView.postsBoundsChangedNotifications
            clipView.postsBoundsChangedNotifications = true

            let boundsToken = center.addObserver(
               forName: NSView.boundsDidChangeNotification,
               object: clipView,
               queue: .main
            ) { [weak self] _ in
               self?.repositionPanel()
            }
            layoutObservers.append(boundsToken)
         }
      }

      private func removeLayoutObservers() {
         let center = NotificationCenter.default
         for token in layoutObservers {
            center.removeObserver(token)
         }
         layoutObservers.removeAll()
         restoreClipViewBoundsPosting()
      }

      private func restoreClipViewBoundsPosting() {
         if let clip = observedClipView {
            clip.postsBoundsChangedNotifications = clipViewPriorPostsBounds
            observedClipView = nil
         }
      }

      private func installEventMonitors() {
         guard localMonitor == nil, globalMonitor == nil else { return }

         localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard let panel = self.panel else { return event }

            if event.window === panel || self.isEventInsideAnchorView(event) {
               return event
            }

            if event.window !== panel {
               self.dismissAndNotify()
            }
            return event
         }

         globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.isPresented else { return }
            guard let panel = self.panel, let anchorView = self.anchorView else { return }

            let locationInScreen: NSPoint
            if let eventWindow = event.window {
               locationInScreen = eventWindow.convertPoint(toScreen: event.locationInWindow)
            } else {
               locationInScreen = NSEvent.mouseLocation
            }

            let anchorRect: CGRect
            if let window = anchorView.window {
               anchorRect = window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
            } else {
               anchorRect = .zero
            }

            if panel.frame.contains(locationInScreen) || anchorRect.contains(locationInScreen) {
               return
            }

            DispatchQueue.main.async {
               self.dismissAndNotify()
            }
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

      private func isEventInsideAnchorView(_ event: NSEvent) -> Bool {
         guard let anchorView,
               event.window === anchorView.window
         else {
            return false
         }

         let pointInAnchor = anchorView.convert(event.locationInWindow, from: nil)
         return anchorView.bounds.contains(pointInAnchor)
      }

      private func installResignObserverIfNeeded(for anchorView: NSView) {
         guard resignObserver == nil,
               let window = anchorView.window
         else {
            return
         }

         resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
         ) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if NSApp.keyWindow === panel {
               return
            }
            self.dismissAndBlurField()
         }
      }

      private func removeResignObserver() {
         if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
         }
      }
   }
}

private final class DropdownFloatingPanel: NSPanel {
   override var canBecomeKey: Bool { true }
   override var canBecomeMain: Bool { false }
}
