import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Effective August 24, 2026")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                policySection(
                    "Our approach",
                    "Link does not require an account and does not use advertising, analytics, or cross-app tracking. We do not sell personal information."
                )

                policySection(
                    "Location",
                    "Location access is optional. When enabled, your location is processed on your device to center the map and help you find nearby stops. Link does not send your precise location to the developer’s servers."
                )

                policySection(
                    "Notifications",
                    "Arrival alerts are optional and are scheduled on your device. Link asks for notification permission only when you save your first alert."
                )

                policySection(
                    "Data stored on your device",
                    "Favorites, route filters, alert settings, appearance, and onboarding progress are stored locally so the app can remember your choices. You can remove this data by deleting the app."
                )

                policySection(
                    "Network services",
                    "Link downloads public transit information from Bloomington Transit data feeds and displays maps using Apple MapKit. If you open the optional booking service, it opens a third-party website outside Link. Those services may process basic network information under their own privacy policies."
                )

                policySection(
                    "Your choices",
                    "You can use Link without location or notifications. You can change either permission at any time in the iOS Settings app."
                )

                policySection(
                    "Contact and updates",
                    "For privacy questions, use the Support URL on Link’s App Store page. If this policy changes, the effective date above will be updated."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color("Background"))
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
