import DesignSystem
import MemoshiProtocol
import SwiftUI

struct BotProfileEditor: View {
  let directory: LiveConversationDirectory
  let models: [AvailableModel]
  let appearances: BotAppearanceStore?
  @Environment(\.dismiss) private var dismiss
  @State private var editingBot: Bot?
  @State private var name: String
  @State private var job: String
  @State private var persona: String
  @State private var model: String
  @State private var effort: String
  @State private var avatarSymbol: String
  @State private var avatarPaletteID: String
  @State private var reloadProblem: String?

  init(
    directory: LiveConversationDirectory, models: [AvailableModel], bot: Bot?,
    appearances: BotAppearanceStore? = nil
  ) {
    self.directory = directory
    self.models = models
    self.appearances = appearances
    _editingBot = State(initialValue: bot)
    _name = State(initialValue: bot?.name ?? "")
    _job = State(initialValue: bot?.job ?? "")
    _persona = State(initialValue: bot?.persona ?? "")
    _model = State(initialValue: bot?.model.ref.rawValue ?? "default")
    _effort = State(initialValue: bot?.model.effort?.rawValue ?? "")
    let saved = bot.flatMap { appearances?.savedAppearance(for: $0.id) }
    _avatarSymbol = State(initialValue: saved?.symbol ?? "sparkles")
    _avatarPaletteID = State(initialValue: saved?.paletteID ?? BotColorPalette.all[0].id)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text(editingBot == nil ? "New Bot" : "Edit Bot").font(.title2)
      Form {
        TextField("Name", text: $name).accessibilityIdentifier("bot.name")
        if editingBot != nil {
          TextField("Job", text: $job, axis: .vertical)
            .lineLimit(2...4).accessibilityIdentifier("bot.job")
          TextField("Persona", text: $persona, axis: .vertical)
            .lineLimit(4...8).accessibilityIdentifier("bot.persona")
          Picker("Model", selection: $model) {
            Text("Use composer choice").tag("default")
            if model != "default", !models.contains(where: { $0.ref.ref.rawValue == model }) {
              Text("\(model) (unavailable)").tag(model)
            }
            ForEach(models, id: \.ref.ref) { choice in
              Text(verbatim: choice.ref.ref.rawValue).tag(choice.ref.ref.rawValue)
            }
          }
          .accessibilityIdentifier("bot.model")
          Picker("Effort", selection: $effort) {
            Text("Model default").tag("")
            ForEach(["off", "minimal", "low", "medium", "high", "xhigh", "max"], id: \.self) {
              value in
              Text(verbatim: value).tag(value)
            }
          }
          .accessibilityIdentifier("bot.effort")
          .disabled(model.hasPrefix("local/"))
          Text(
            "Effort applies only to models that advertise reasoning support. Local discovery uses the server's model default."
          )
          .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
          if appearances != nil {
            Section("Appearance") {
              HStack(spacing: 14) {
                ShellBotAvatar(
                  symbol: avatarSymbol,
                  gradient: (BotColorPalette.named(avatarPaletteID) ?? BotColorPalette.all[0])
                    .gradient,
                  size: 46)
                VStack(alignment: .leading, spacing: 8) {
                  HStack(spacing: 7) {
                    ForEach(BotColorPalette.all) { palette in
                      Button {
                        avatarPaletteID = palette.id
                      } label: {
                        Circle()
                          .fill(
                            LinearGradient(
                              colors: palette.gradient, startPoint: .topLeading,
                              endPoint: .bottomTrailing)
                          )
                          .frame(width: 20, height: 20)
                          .overlay {
                            if avatarPaletteID == palette.id {
                              Circle().stroke(WarmShellColors.primaryText, lineWidth: 2)
                                .padding(-2)
                            }
                          }
                      }
                      .buttonStyle(.plain)
                      .help(palette.name)
                    }
                  }
                  LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 7),
                    spacing: 6
                  ) {
                    ForEach(BotAppearanceStore.symbolOptions, id: \.self) { symbol in
                      Button {
                        avatarSymbol = symbol
                      } label: {
                        Image(systemName: symbol)
                          .font(.system(size: 13, weight: .medium))
                          .foregroundStyle(
                            avatarSymbol == symbol
                              ? WarmShellColors.badgeText : WarmShellColors.primaryText
                          )
                          .frame(width: 28, height: 28)
                          .background(
                            avatarSymbol == symbol ? WarmShellColors.badgeFill : WarmShellColors.pill,
                            in: RoundedRectangle(cornerRadius: 7))
                      }
                      .buttonStyle(.plain)
                    }
                  }
                }
              }
              .padding(.vertical, 4)
            }
          }
        } else {
          Text(
            "Creates one Chat in Ask first. Configure its profile after creation. Production tools stay disabled."
          )
          .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
        }
      }
      .formStyle(.grouped)
      .disabled(directory.isChanging || directory.hasPendingChange)
      ConversationDirectoryStatus(directory: directory)
      if let reloadProblem { Text(verbatim: reloadProblem).font(DS.Typography.callout) }
      HStack {
        if editingBot != nil {
          Button("Reload Bot") {
            Task { await reload() }
          }
          .disabled(directory.isChanging || directory.hasPendingChange)
          .accessibilityIdentifier("bot.reload")
        }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(editingBot == nil ? "Create" : "Save") { save() }
          .designDefaultAction()
          .disabled(
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || directory.isChanging || directory.hasPendingChange
          )
          .accessibilityIdentifier("bot.save")
      }
    }
    .padding(DS.Space.s6)
    .frame(width: DS.Layout.Sheet.botProfileWidth)
    .onChange(of: directory.isChanging) { wasChanging, changing in
      if wasChanging, !changing, directory.problem == nil, !directory.hasPendingChange { dismiss() }
    }
  }

  private func save() {
    guard let reference = try? ModelName(model) else { return }
    if let bot = editingBot {
      appearances?.setAppearance(
        BotAppearance(symbol: avatarSymbol, paletteID: avatarPaletteID), for: bot.id)
      directory.updateBot(
        bot, name: name, job: job, persona: persona,
        model: ModelRef(
          ref: reference,
          effort: effort.isEmpty ? nil : ThinkingEffort(rawValue: effort)))
    } else {
      directory.createBot(name: name)
    }
  }

  private func reload() async {
    guard let id = editingBot?.id else { return }
    do {
      try await directory.reload()
      guard let current = directory.bots.first(where: { $0.id == id }) else { return }
      editingBot = current
      name = current.name
      job = current.job
      persona = current.persona
      model = current.model.ref.rawValue
      effort = current.model.effort?.rawValue ?? ""
      reloadProblem = nil
    } catch {
      reloadProblem = String(
        localized: "The bot could not be reloaded. The edit has not been applied.")
    }
  }
}

struct SessionCreationSheet: View {
  let directory: LiveConversationDirectory
  @Environment(\.dismiss) private var dismiss
  @State private var botID: BotID?
  @State private var title = "New session"

  init(directory: LiveConversationDirectory, selectedBot: BotID?) {
    self.directory = directory
    _botID = State(initialValue: selectedBot ?? directory.bots.first?.id)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text("New Session").font(.title2)
      Form {
        TextField("Title", text: $title).accessibilityIdentifier("session.title")
        Picker("Lead bot", selection: $botID) {
          ForEach(directory.bots, id: \.id) { bot in
            Text(verbatim: bot.name).tag(Optional(bot.id))
          }
        }
        .accessibilityIdentifier("session.leadBot")
      }
      .formStyle(.grouped)
      .disabled(directory.isChanging || directory.hasPendingChange)
      ConversationDirectoryStatus(directory: directory)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Create") {
          if let botID { directory.createSession(bot: botID, title: title) }
        }
        .designDefaultAction()
        .disabled(
          botID == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || directory.isChanging || directory.hasPendingChange
        )
        .accessibilityIdentifier("session.save")
      }
    }
    .padding(DS.Space.s6).frame(width: DS.Layout.Sheet.sessionCreationWidth)
    .onChange(of: directory.isChanging) { wasChanging, changing in
      if wasChanging, !changing, directory.problem == nil, !directory.hasPendingChange { dismiss() }
    }
  }
}
