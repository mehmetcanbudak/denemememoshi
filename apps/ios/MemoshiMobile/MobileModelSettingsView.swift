import AppCore
import DesignSystem
import MemoshiProtocol
import SwiftUI

/// Explicit local model settings: one keyless loopback OpenAI-compatible endpoint and the model
/// the next Send names. No cloud provider, key or fallback is offered here.
struct MobileModelSettingsView: View {
  @Bindable var model: InProcessChatModel
  @Environment(\.dismiss) private var dismiss
  @State private var endpoint = ""

  var body: some View {
    NavigationStack {
      Form {
        Section {
          // Vertical, so a long endpoint wraps at large text sizes instead of being clipped.
          // Return inserts a line break in a vertical field; an endpoint has none, so it is
          // dropped as typed.
          TextField(
            "Endpoint", text: $endpoint, prompt: Text(verbatim: Self.defaultEndpoint),
            axis: .vertical
          )
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("model.endpoint")
          .onChange(of: endpoint) { _, value in
            if value.contains(where: \.isNewline) { endpoint = value.filter { !$0.isNewline } }
          }
          Button {
            model.configureLocalEndpoint(endpoint.isEmpty ? Self.defaultEndpoint : endpoint)
          } label: {
            HStack {
              Text("Save and List Models")
              if model.isConfiguring || model.isLoadingModels {
                Spacer()
                ProgressView()
              }
            }
          }
          .disabled(model.isConfiguring || model.isWorking || !model.isConnected)
          .accessibilityIdentifier("model.save")
        } header: {
          // The system's grouped header and footer gray only nearly meets 4.5:1; the checked
          // secondary role meets it.
          Text("Local Endpoint").foregroundStyle(DesignControlRoles.secondaryText)
        } footer: {
          Text(
            "A loopback HTTP server on this device, such as Ollama or LM Studio. In the Simulator, that is the Mac's loopback. The engine refuses any other address."
          )
          .foregroundStyle(DesignControlRoles.secondaryText)
        }
        if let problem = model.modelProblem {
          Section {
            Text(verbatim: problem)
              .foregroundStyle(DS.Colors.Text.secondary)
              .accessibilityIdentifier("model.problem")
          }
        }
        Section {
          if model.models.isEmpty {
            Text("No models listed yet.")
              .foregroundStyle(DS.Colors.Text.secondary)
          }
          ForEach(model.models, id: \.ref) { choice in
            Button {
              model.selectedModel = choice.ref.ref.rawValue
            } label: {
              HStack {
                VStack(alignment: .leading) {
                  Text(verbatim: choice.name)
                  Text(verbatim: choice.ref.ref.rawValue)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Colors.Text.secondary)
                }
                Spacer()
                if choice.ref.ref.rawValue == model.selectedModel {
                  Image(systemName: "checkmark").accessibilityHidden(true)
                }
              }
            }
            .disabled(model.isWorking)
            .accessibilityAddTraits(
              choice.ref.ref.rawValue == model.selectedModel ? .isSelected : []
            )
            .accessibilityIdentifier("model.option.\(choice.ref.ref.rawValue)")
          }
        } header: {
          Text("Model").foregroundStyle(DesignControlRoles.secondaryText)
        }
      }
      .navigationTitle("Model")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .accessibilityIdentifier("model.done")
        }
      }
      .onAppear {
        endpoint = model.providers.first { $0.id == "local" }?.baseUrl ?? ""
      }
    }
  }

  /// Ollama's OpenAI-compatible endpoint.
  static let defaultEndpoint = "http://127.0.0.1:11434/v1"
}
