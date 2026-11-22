import AppCore
import DesignSystem
import MemoshiRuntime
import SwiftUI

/// User-only development sign-in. No bot, browser automation or model can operate these controls.
struct ChatGPTProviderSection: View {
  @Bindable var setup: ModelProviderSetup
  let host: ChatGPTSubscription?
  let keychain: ModelKeychain?
  let canConfigure: Bool
  @State private var callback = ""

  var body: some View {
    Section("ChatGPT Subscription") {
      Text(
        "Sign in with your own ChatGPT account through PiAI. Credentials stay in this app's data-protection Keychain on this Mac only; iCloud credential synchronization is not qualified."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      if setup.isSigningIn {
        Label("Complete sign-in in your browser", systemImage: "person.crop.circle.badge.clock")
        if let url = setup.signInURL {
          Link("Reopen OpenAI Sign-In", destination: url)
            .privacySensitive()
        }
        if setup.acceptsSignInCallback, let host {
          Text(
            "The browser normally returns automatically. If it cannot, paste the final http://127.0.0.1:1455/auth/callback URL here—not in a conversation."
          )
          .font(DS.Typography.callout)
          SecureField("Callback URL (optional)", text: $callback)
            .privacySensitive()
            .autocorrectionDisabled()
            .accessibilityIdentifier("models.chatGPT.callback")
          Button("Use Callback URL") {
            setup.submitChatGPTCallback(callback, host: host) { callback = "" }
          }
          .disabled(callback.isEmpty)
          .accessibilityIdentifier("models.chatGPT.submitCallback")
        }
        Button("Cancel Sign-In") {
          guard let host else { return }
          callback = ""
          setup.cancelChatGPTSignIn(host)
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("models.chatGPT.cancel")
      } else {
        Button("Sign in with ChatGPT", systemImage: "person.badge.key.fill") {
          guard let host else { return }
          setup.signInWithChatGPT(host, keychain: keychain)
        }
        .disabled(host == nil || !canConfigure || setup.hasUnconfirmedConfiguration)
        .accessibilityIdentifier("models.chatGPT.signIn")
        if setup.usesChatGPT {
          Button("Sign Out of ChatGPT", role: .destructive) {
            guard let host else { return }
            setup.signOutOfChatGPT(host)
          }
          .disabled(host == nil || !canConfigure || setup.hasUnconfirmedConfiguration)
          .accessibilityIdentifier("models.chatGPT.signOut")
        }
        Text(
          "Sign-in replaces the development workspace's OpenAI credential reference. Prompts go to OpenAI only when you explicitly send with an OpenAI model; no API key or local model is substituted."
        )
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      }
    }
    .onChange(of: setup.isSigningIn) { _, signingIn in
      if !signingIn { callback = "" }
    }
    .onDisappear { callback = "" }
  }
}
