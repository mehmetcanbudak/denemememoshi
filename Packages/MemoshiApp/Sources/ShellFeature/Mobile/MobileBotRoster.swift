#if os(iOS)
  import AppCore
  import DesignSystem
  import SwiftUI

  struct MobileBotRoster: View {
    let selection: PreviewBot
    @Binding var searchText: String
    let isSearch: Bool
    let select: (PreviewBot) -> Void

    private var matchingBots: [PreviewBot] {
      let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else { return PreviewBot.allCases }
      return PreviewBot.allCases.filter { bot in
        bot.name.localizedStandardContains(query)
          || bot.subtitle.localizedStandardContains(query)
      }
    }

    var body: some View {
      let bots = matchingBots

      List {
        Section {
          ForEach(bots) { bot in
            Button {
              select(bot)
            } label: {
              MobileBotRow(bot: bot, isSelected: bot == selection)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
              Text("Opens \(bot.name)'s local preview conversation.", bundle: #bundle)
            )
            .accessibilityIdentifier(
              isSearch ? "search.bot.\(bot.rawValue)" : "bot.\(bot.rawValue)"
            )
            .listRowBackground(Rectangle().fill(DS.Colors.Surface.raised))
          }
        } header: {
          // The system's grouped header and footer gray only nearly meets 4.5:1 on the window
          // background; the checked secondary role meets it in both palettes.
          Group {
            isSearch
              ? Text("Matching preview bots", bundle: #bundle)
              : Text("Your assistant and other bots", bundle: #bundle)
          }
          .foregroundStyle(DesignControlRoles.secondaryText)
        } footer: {
          Text(
            "Design Preview · Not connected. Search names and descriptions, then open a local example chat.",
            bundle: #bundle
          )
          .foregroundStyle(DesignControlRoles.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(DS.Colors.Surface.window)
      .navigationTitle(isSearch ? Text("Search", bundle: #bundle) : Text("Bots", bundle: #bundle))
      .searchable(
        text: $searchText,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: Text("Search preview bots", bundle: #bundle)
      )
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          MobilePreviewMenu()
        }
      }
      .overlay {
        if bots.isEmpty {
          ContentUnavailableView {
            Label {
              Text("No preview bots found", bundle: #bundle)
            } icon: {
              Image(systemName: "magnifyingglass")
            }
          } description: {
            Text("No names or descriptions match “\(searchText)”.", bundle: #bundle)
          } actions: {
            Button {
              searchText = ""
            } label: {
              Text("Clear Search", bundle: #bundle)
            }
            .frame(minHeight: DS.Layout.Composer.minHeight)
            .accessibilityIdentifier(isSearch ? "search.clear" : "bots.clearSearch")
          }
        }
      }
    }
  }

  private struct MobileBotRow: View {
    let bot: PreviewBot
    let isSelected: Bool

    var body: some View {
      HStack(spacing: DS.Space.s5) {
        BotAvatar(symbol: bot.systemImage)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: DS.Space.s1) {
          Text(bot.name)
            .font(.headline)
            .foregroundStyle(DS.Colors.Text.primary)
          Text(bot.subtitle)
            .font(.subheadline)
            .foregroundStyle(DS.Colors.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(DS.Colors.Accent.text)
            .accessibilityHidden(true)
        }
        Image(systemName: "chevron.right")
          .font(.subheadline)
          .foregroundStyle(DS.Colors.Text.secondary)
          .accessibilityHidden(true)
      }
      .frame(minHeight: DS.Layout.Composer.minHeight)
      .contentShape(Rectangle())
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
  }
#endif
