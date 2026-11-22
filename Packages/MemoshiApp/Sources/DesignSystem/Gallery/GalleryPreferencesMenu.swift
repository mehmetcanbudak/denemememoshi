import SwiftUI

/// Explicitly labelled app preferences, not changes to the user's system accessibility setup.
struct GalleryPreferencesMenu: View {
  @AppStorage(ChromeAppearance.preferenceKey) private var chrome = ChromeAppearance.frosted
  @AppStorage(MotionPreference.preferenceKey) private var motion = MotionPreference.system
  @AppStorage(MotionPreference.avatarPreferenceKey) private var animateAvatars = true

  var body: some View {
    Menu {
      Picker(selection: $chrome) {
        ForEach(ChromeAppearance.allCases) { appearance in
          Text(appearance.title).tag(appearance)
        }
      } label: {
        Text("Chrome appearance", bundle: #bundle)
      }
      Picker(selection: $motion) {
        ForEach(MotionPreference.allCases) { preference in
          Text(preference.title).tag(preference)
        }
      } label: {
        Text("Reduce Motion", bundle: #bundle)
      }
      Toggle(isOn: $animateAvatars) {
        Text("Animate bot avatars", bundle: #bundle)
      }
      Text(
        "App preferences only; comparison columns do not change system settings.",
        bundle: #bundle)
    } label: {
      Label {
        Text("App appearance and motion", bundle: #bundle)
      } icon: {
        Image(systemName: "accessibility")
      }
    }
    .help(
      Text(
        "Change Frosted/Solid, Reduce Motion or Pause/Stop for bot avatars in this app",
        bundle: #bundle)
    )
    .accessibilityIdentifier("gallery.preferences")
  }
}
