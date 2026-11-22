import AppCore
import DesignSystem
import MemoshiProtocol
import MemoshiRuntime
import SwiftUI

struct ModelSetupView: View {
  let model: LiveChatModel
  let supervisor: DaemonSupervisor
  @Bindable var setup: ModelProviderSetup
  @Environment(\.dismiss) private var dismiss
  @State private var isAddingKey = false
  @State private var isDiscardingRecord = false
  @State private var isDiscardingRefused = false

  init(model: LiveChatModel, supervisor: DaemonSupervisor) {
    self.model = model
    self.supervisor = supervisor
    self.setup = model.providerSetup
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text("Model Settings").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
      Form {
        ChatGPTProviderSection(
          setup: setup, host: supervisor.chatGPTSubscription,
          keychain: supervisor.modelKeychain, canConfigure: canConfigure)
        ClaudeCodeProviderSection(
          setup: setup, keychain: supervisor.modelKeychain, host: supervisor.chatGPTSubscription,
          canConfigure: canConfigure)
        LocalProviderSection(
          setup: setup, keychain: supervisor.modelKeychain, host: supervisor.chatGPTSubscription,
          canConfigure: canConfigure)
        Section("Credentials") {
          ForEach(setup.providers, id: \.id) { provider in
            HStack {
              Text(verbatim: provider.name)
              Spacer()
              if provider.id == ModelProviderDefinition.claudeCode.id {
                Label("Local CLI · This Mac", systemImage: "terminal.fill")
                  .foregroundStyle(DS.Colors.Text.secondary)
              } else if provider.secretRef == nil {
                Text("No key").foregroundStyle(DS.Colors.Text.secondary)
              } else if provider.secretRef.flatMap(ModelCredentialReference.init(rawValue:))?.kind
                == .chatGPT
              {
                Label("ChatGPT · This Mac", systemImage: "person.badge.key.fill")
                  .foregroundStyle(DS.Colors.Text.secondary)
              } else {
                Label("Keychain", systemImage: "key.fill")
                  .foregroundStyle(DS.Colors.Text.secondary)
              }
            }
          }
          Button("Add Model Key", systemImage: "plus") { isAddingKey = true }
            .disabled(!canConfigure || setup.hasUnconfirmedConfiguration)
            .accessibilityIdentifier("models.addKey")
          Text(
            "Keys stay in Apple's data-protection Keychain. The daemon receives only a short-lived, purpose-checked release from this app."
          )
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
        }
        Section("Available Models") {
          ModelChoicePicker(setup: setup)
            .disabled(!canConfigure || model.hasUnconfirmedSend)
          Button("Refresh Models") { setup.refreshModels() }
            .disabled(!canConfigure || setup.providers.isEmpty)
            .accessibilityIdentifier("chat.refreshModels")
          if let provider = setup.selectedProvider, let usage = setup.selectedUsage,
            usage != .onDevice
          {
            Group {
              if provider.id == ModelProviderDefinition.claudeCode.id {
                Text(
                  "Prompts relay through your unmodified Claude Code binary on this Mac. Memoshi never starts an Anthropic sign-in or reads Claude credentials. Subscription usage is shown as price unknown."
                )
              } else if usage == .subscription {
                Text(
                  "Messages leave this Mac and use supported ChatGPT plan access, subject to OpenAI's availability and limits. No API-key fallback is used."
                )
              } else {
                Text(
                  "Messages sent to \(provider.name) leave this Mac and may incur API usage charges. No paid model is selected automatically."
                )
              }
            }
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
          }
        }
        if setup.hasUnreadableConfiguration {
          Section("Unreadable Saved Configuration") {
            Text(
              "A saved provider configuration could not be read, so it cannot be retried. Configuration and sending stay blocked until it is discarded after the current provider list loads."
            )
            Button("Discard Unreadable Configuration…", role: .destructive) {
              isDiscardingRecord = true
            }
            .disabled(!canConfigure || !setup.canDiscardUnreadableConfiguration)
            .accessibilityIdentifier("models.discardUnreadable")
          }
        } else if setup.hasUnconfirmedConfiguration {
          Section("Saved Configuration") {
            if setup.pendingWasRejected {
              Text(
                "The provider refused this configuration. You can correct its local endpoint and retry using the saved Keychain reference."
              )
            } else {
              Text(
                "Configuration delivery is unconfirmed. The original request and Keychain reference are preserved; retry before changing providers or sending."
              )
            }
            Button("Retry Saved Configuration") {
              setup.retryConfiguration(
                keychain: supervisor.modelKeychain, host: supervisor.chatGPTSubscription)
            }
            .disabled(!canConfigure || !setup.canRetryConfiguration)
            .accessibilityIdentifier("models.retryConfiguration")
            if setup.canDiscardRefusedConfiguration {
              Button("Discard Refused Configuration…", role: .destructive) {
                isDiscardingRefused = true
              }
              .accessibilityIdentifier("models.discardRefused")
            }
          }
        }
        if let problem = setup.problem {
          Section {
            Text(verbatim: problem)
              .foregroundStyle(DS.Colors.Text.secondary)
              .accessibilityIdentifier("models.error")
          }
        }
      }
      .formStyle(.grouped)
      Text(
        "Model keys remain in Apple's data-protection Keychain; Claude Code runs through your own unmodified binary on this Mac."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      HStack {
        if setup.isConfiguring { ProgressView().controlSize(.small) }
        Spacer()
        Button("Done") { dismiss() }
          // Esc closes the sheet; Return in the Endpoint field connects instead (A17).
          .keyboardShortcut(.cancelAction)
          .disabled(setup.isConfiguring)
          .accessibilityIdentifier("chat.modelSettings.done")
      }
    }
    .padding(DS.Space.s6)
    .designSheetFrame(idealWidth: DS.Layout.Conversation.minWidth)
    .background(DS.Colors.Surface.window)
    .interactiveDismissDisabled(setup.isConfiguring)
    .task {
      setup.removeKeptCredentials(
        keychain: supervisor.modelKeychain, host: supervisor.chatGPTSubscription)
    }
    .sheet(isPresented: $isAddingKey) {
      AddModelKeyView(
        setup: setup, keychain: supervisor.modelKeychain, host: supervisor.chatGPTSubscription)
    }
    .confirmationDialog(
      "Discard Unreadable Saved Configuration?", isPresented: $isDiscardingRecord,
      titleVisibility: .visible
    ) {
      Button("Discard", role: .destructive) { setup.discardUnreadableConfiguration() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "It cannot be read or retried. Discarding sends nothing and cannot undo a configuration the runtime already applied; check the provider list before configuring the same provider again."
      )
    }
    .confirmationDialog(
      "Discard Refused Configuration?", isPresented: $isDiscardingRefused,
      titleVisibility: .visible, presenting: setup.refusedDiscardPreview
    ) { _ in
      Button("Discard", role: .destructive) {
        setup.discardRefusedConfiguration(
          keychain: supervisor.modelKeychain, host: supervisor.chatGPTSubscription)
      }
      Button("Cancel", role: .cancel) {}
    } message: { outcome in
      switch outcome {
      case .removedCredential:
        Text(
          "The runtime refused it, so nothing was applied. Discarding clears the saved request and removes the credential that was saved only for it; the provider list stays as it is."
        )
      case .keptCredential:
        Text(
          "The runtime refused the latest attempt, but an earlier attempt had no definite answer and may still be applied. Discarding clears the saved request and keeps the credential saved for it in the Keychain; check the provider list afterwards."
        )
      case .noCredential:
        Text(
          "The runtime refused it, so nothing was applied. Discarding clears the saved request. No credential was saved only for it, so none is removed; the provider list stays as it is."
        )
      }
    }
  }

  private var canConfigure: Bool {
    model.connection == .connected && !model.isWorking && !model.isSending && !setup.isConfiguring
  }
}

private struct ClaudeCodeProviderSection: View {
  @Bindable var setup: ModelProviderSetup
  let keychain: ModelKeychain?
  let host: ChatGPTSubscription?
  let canConfigure: Bool
  @State private var status = ClaudeCodeStatus(executablePath: nil, version: nil)
  @State private var isProbing = false

  var body: some View {
    Section("Claude via Claude Code (This Mac)") {
      HStack(alignment: .center, spacing: DS.Space.s3) {
        if let path = status.executablePath {
          VStack(alignment: .leading, spacing: 2) {
            Label(
              status.version.map { "Installed · \($0)" } ?? "Claude Code installed",
              systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(DS.Colors.Text.primary)
            Text(verbatim: path)
              .font(DS.Typography.callout.monospaced())
              .foregroundStyle(DS.Colors.Text.secondary)
          }
        } else {
          VStack(alignment: .leading, spacing: 2) {
            Label("Claude Code binary not found", systemImage: "terminal")
              .foregroundStyle(DS.Colors.Text.secondary)
            Text("Install Claude Code on this Mac and sign in with `claude auth login` in Terminal.")
              .font(DS.Typography.callout)
              .foregroundStyle(DS.Colors.Text.secondary)
          }
        }
        Spacer()
        if isProbing {
          ProgressView().controlSize(.small)
        } else {
          Button("Check") { probeBinary() }
            .controlSize(.small)
            .accessibilityIdentifier("models.claudeCode.check")
        }
      }

      HStack(spacing: DS.Space.s3) {
        Button(setup.usesClaudeCode ? "Refresh Claude Code Models" : "Enable Claude Code") {
          setup.configureClaudeCode(keychain: keychain, host: host)
        }
        .disabled(!canConfigure || setup.hasUnconfirmedConfiguration || !status.isInstalled)
        .accessibilityIdentifier("models.claudeCode.enable")
        if setup.usesClaudeCode {
          Label("Configured", systemImage: "checkmark")
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
        }
      }

      Text(
        "Runs Claude as a bot model on this Mac by relaying prompts through your unmodified Claude Code binary (D108). Memoshi never starts an Anthropic sign-in or reads Claude credentials; subscription usage shows as price unknown."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
    .task { probeBinary() }
  }

  private func probeBinary() {
    guard !isProbing else { return }
    isProbing = true
    Task.detached {
      let result = ClaudeCodeLocator.probe()
      await MainActor.run {
        status = result
        isProbing = false
      }
    }
  }
}

private struct LocalProviderSection: View {
  @Bindable var setup: ModelProviderSetup
  let keychain: ModelKeychain?
  let host: ChatGPTSubscription?
  let canConfigure: Bool

  var body: some View {
    Section("Local Server") {
      TextField("Endpoint", text: $setup.endpoint)
        .textFieldStyle(.roundedBorder)
        .disabled(!canConfigure || (setup.hasUnconfirmedConfiguration && !setup.pendingWasRejected))
        .onSubmit {
          if canConfigure && !setup.hasUnconfirmedConfiguration {
            setup.configureEndpoint(keychain: keychain, host: host)
          }
        }
        .accessibilityIdentifier("chat.endpoint")
      Button("Connect Local Model") { setup.configureEndpoint(keychain: keychain, host: host) }
        .disabled(!canConfigure || setup.hasUnconfirmedConfiguration)
        .accessibilityIdentifier("chat.connectModel")
      Text(
        "Ollama, LM Studio or another OpenAI-compatible server on this Mac. An existing local Keychain reference is retained when changing its endpoint."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
  }
}

struct ModelChoicePicker: View {
  @Bindable var setup: ModelProviderSetup

  var body: some View {
    Picker("Model", selection: $setup.selectedModel) {
      Text("Choose a model").tag("")
      if !setup.selectedModel.isEmpty && !setup.selectedModelIsAvailable {
        Text("Selected model unavailable").tag(setup.selectedModel)
      }
      ForEach(setup.models, id: \.ref.ref.rawValue) { model in
        Text(verbatim: model.ref.ref.rawValue).tag(model.ref.ref.rawValue)
      }
    }
    .pickerStyle(.menu)
  }
}

private struct AddModelKeyView: View {
  @Bindable var setup: ModelProviderSetup
  let keychain: ModelKeychain?
  let host: ChatGPTSubscription?
  @Environment(\.dismiss) private var dismiss
  @State private var providerID = ModelProviderDefinition.openAI.id
  @State private var label = String(localized: "Model API key")
  @State private var key = ""
  @State private var thisDeviceOnly = false
  @State private var storedInput = false

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      Text("Add Model Key").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
      Form {
        Section {
          Picker("Provider", selection: $providerID) {
            ForEach(ModelProviderDefinition.all.filter(\.acceptsAPIKey)) { provider in
              if provider.endpoint == .loopback {
                Text("Local Server (Bearer Key)").tag(provider.id)
              } else {
                Text(verbatim: provider.name).tag(provider.id)
              }
            }
          }
          .accessibilityIdentifier("models.addKey.provider")
          TextField("Label", text: $label)
            .accessibilityIdentifier("models.addKey.label")
          SecureField("API Key", text: $key)
            .privacySensitive()
            .autocorrectionDisabled()
            .accessibilityIdentifier("models.addKey.value")
          Toggle("Keep on This Mac Only", isOn: $thisDeviceOnly)
            .accessibilityIdentifier("models.addKey.deviceOnly")
          Text(
            "Otherwise the key uses iCloud Keychain synchronization. Access always requires this app's authorized access group and provisioning profile; no legacy Keychain fallback is used."
          )
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
        }
        Section {
          if let provider = ModelProviderDefinition.named(providerID),
            let baseURL = provider.fixedBaseURL
          {
            Text(
              "Uses \(baseURL). Saving enables authenticated model discovery; prompts go to \(provider.name) only when you explicitly send with one of its models. API usage may be billed."
            )
          } else {
            Text(
              "The key is authorized only for the local provider and its configured loopback endpoint. It cannot be released for OpenAI or another host purpose."
            )
            Text(verbatim: setup.endpoint)
              .font(DS.Typography.callout.monospaced())
          }
        }
        if keychain == nil {
          Section {
            Text(
              "A genuinely signed, provisioned Memoshi app and authenticated helper are required to save a model key."
            )
          }
        }
        if let problem = setup.problem {
          Section {
            Text(verbatim: problem)
              .foregroundStyle(DS.Colors.Text.secondary)
              .accessibilityIdentifier("models.addKey.error")
          }
        }
      }
      .formStyle(.grouped)
      .disabled(setup.isConfiguring)
      HStack {
        Button("Cancel") {
          key = ""
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .disabled(setup.isConfiguring)
        Spacer()
        if setup.isConfiguring { ProgressView().controlSize(.small) }
        Button("Save Key") {
          guard let keychain else { return }
          setup.addKey(
            providerID: providerID, label: label, value: key,
            thisDeviceOnly: thisDeviceOnly, keychain: keychain, host: host,
            clearInput: {
              key = ""
              storedInput = true
            })
        }
        .designDefaultAction()
        .disabled(keychain == nil || key.isEmpty || label.isEmpty || setup.isConfiguring)
        .accessibilityIdentifier("models.addKey.save")
      }
    }
    .padding(DS.Space.s6)
    .designSheetFrame(idealWidth: DS.Layout.Conversation.minWidth)
    .background(DS.Colors.Surface.window)
    .interactiveDismissDisabled(setup.isConfiguring)
    .onChange(of: setup.isConfiguring) { _, busy in
      if !busy && storedInput { dismiss() }
    }
    .onDisappear { key = "" }
  }
}
