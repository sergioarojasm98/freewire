import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Toggle(isOn: $preferences.showPublicIP) {
                Text("Show public IP address")
                Text("Looked up at cloudflare.com/cdn-cgi/trace after each network change.")
            }
            Toggle(isOn: $preferences.showAdaptersWithoutLink) {
                Text("Show adapters without a cable")
                Text("Idle Thunderbolt ports are always hidden.")
            }
            Toggle(isOn: $preferences.notifyOnChange) {
                Text("Notify when Ethernet connects or disconnects")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
