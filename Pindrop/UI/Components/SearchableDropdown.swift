//
//  SearchableDropdown.swift
//  Pindrop
//
//  Created on 2026-02-15.
//

import AppKit
import SwiftUI

public protocol SearchableDropdownItem: Identifiable {
   var displayName: String { get }
}

public struct SearchableDropdown<Item: SearchableDropdownItem>: View {
   let items: [Item]
   let placeholder: String
   let emptyMessage: String
   let searchPlaceholder: String
   @Binding var selection: Item.ID?

   @State private var isOpen = false
   @State private var searchQuery = ""

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

   public var body: some View {
      Button {
         isOpen.toggle()
      } label: {
         HStack(spacing: 8) {
            Text(selectedItemName)
               .foregroundStyle(.primary)
               .lineLimit(1)
               .truncationMode(.tail)

            Spacer(minLength: 8)

            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
               .font(.caption.weight(.semibold))
               .foregroundStyle(.secondary)
         }
         .frame(maxWidth: .infinity, alignment: .leading)
         .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .popover(isPresented: $isOpen, arrowEdge: .bottom) {
         dropdownContent
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400, minHeight: 100)
      }
   }

   private var dropdownContent: some View {
      VStack(spacing: 0) {
         // Search field
         HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
               .font(.caption)
               .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $searchQuery)
               .textFieldStyle(.plain)
               .font(.body)
         }
         .padding(.horizontal, 12)
         .padding(.vertical, 10)
         .background(Color(nsColor: .textBackgroundColor).opacity(0.5))

         Divider()

         // Items list
         ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
               listContent
            }
         }
         .frame(maxHeight: 280)
      }
      .padding(.vertical, 8)
   }

   @ViewBuilder
   private var listContent: some View {
      if items.isEmpty {
         Text(emptyMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
      } else if filteredItems.isEmpty {
         Text("No matches found")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
      } else {
         ForEach(filteredItems) { item in
            itemRow(for: item)
         }
      }
   }

   private func itemRow(for item: Item) -> some View {
      Button {
         selection = item.id
         isOpen = false
         searchQuery = ""
      } label: {
         HStack(spacing: 8) {
            Text(item.displayName)
               .foregroundStyle(.primary)
               .lineLimit(1)
               .truncationMode(.tail)
               .frame(maxWidth: .infinity, alignment: .leading)

            if item.id == selection {
               Image(systemName: "checkmark")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(Color.accentColor)
            }
         }
         .padding(.horizontal, 12)
         .padding(.vertical, 8)
         .background(
            item.id == selection
               ? Color.accentColor.opacity(0.12)
               : Color.clear
         )
         .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
   }

   private var filteredItems: [Item] {
      let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedQuery.isEmpty {
         return items
      }
      return items.filter { $0.displayName.localizedCaseInsensitiveContains(trimmedQuery) }
   }

   private var selectedItemName: String {
      guard let selection else { return placeholder }
      return items.first(where: { $0.id == selection })?.displayName ?? placeholder
   }
}
