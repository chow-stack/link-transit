import SwiftUI
import CoreLocation

struct OnboardingView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page: Page = .welcome
    @State private var artworkIsVisible = false

    private enum Page: Int, CaseIterable {
        case welcome
        case location
        case alerts
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = max(20, min(32, geometry.size.width * 0.065))
            let compactHeight = geometry.size.height < 700
            let artworkHeight = min(compactHeight ? 190 : 280, geometry.size.height * 0.34)

            ZStack {
                Color("Background")
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header(horizontalPadding: horizontalPadding)

                    TabView(selection: $page) {
                        onboardingPage(
                            page: .welcome,
                            imageName: "OnboardingWelcome",
                            title: "Ride with confidence",
                            message: "See buses, stops, and arrival times in one place.",
                            horizontalPadding: horizontalPadding,
                            artworkHeight: artworkHeight,
                            compactHeight: compactHeight
                        )

                        onboardingPage(
                            page: .location,
                            imageName: "OnboardingLocation",
                            title: "Find stops nearby",
                            message: "Use your location to start the map near you.",
                            horizontalPadding: horizontalPadding,
                            artworkHeight: artworkHeight,
                            compactHeight: compactHeight
                        )

                        onboardingPage(
                            page: .alerts,
                            imageName: "OnboardingAlerts",
                            title: "Know when to leave",
                            message: "Set an alert for your stop and choose when to be notified.",
                            note: "We ask for notifications when you save your first alert.",
                            horizontalPadding: horizontalPadding,
                            artworkHeight: artworkHeight,
                            compactHeight: compactHeight
                        )
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.45), value: page)

                    footer(horizontalPadding: horizontalPadding)
                }
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.82)) {
                artworkIsVisible = true
            }
        }
        .onChange(of: page) { _, _ in
            guard !reduceMotion else { return }
            artworkIsVisible = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.04)) {
                artworkIsVisible = true
            }
        }
        .onChange(of: locationManager.authorizationStatus) { oldStatus, newStatus in
            guard page == .location,
                  oldStatus == .notDetermined,
                  newStatus != .notDetermined else { return }
            advance(to: .alerts)
        }
    }

    private func header(horizontalPadding: CGFloat) -> some View {
        HStack {
            Spacer()

            Button("Skip") {
                finish()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityHint("Closes the introduction")
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 4)
        .frame(minHeight: 52)
    }

    private func onboardingPage(
        page pageValue: Page,
        imageName: String,
        title: String,
        message: String,
        note: String? = nil,
        horizontalPadding: CGFloat,
        artworkHeight: CGFloat,
        compactHeight: Bool
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: compactHeight ? 18 : 28) {
                Spacer(minLength: compactHeight ? 4 : 16)

                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 520, maxHeight: artworkHeight)
                    .scaleEffect(artworkIsVisible && page == pageValue ? 1 : 0.94)
                    .offset(y: artworkIsVisible && page == pageValue ? 0 : 12)
                    .opacity(artworkIsVisible && page == pageValue ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.82),
                        value: artworkIsVisible
                    )
                    .accessibilityHidden(true)

                VStack(spacing: compactHeight ? 10 : 14) {
                    Text(title)
                        .font(.system(size: compactHeight ? 29 : 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 360)

                    if let note {
                        Text(note)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color("PrimaryAccent"))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 330)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: compactHeight ? 8 : 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
        }
        .tag(pageValue)
        .accessibilityElement(children: .contain)
    }

    private func footer(horizontalPadding: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Page.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == page ? Color("PrimaryAccent") : Color.secondary.opacity(0.22))
                        .frame(width: item == page ? 24 : 8, height: 8)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: page)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")

            HStack(spacing: 12) {
                if page != .welcome {
                    Button("Back", action: goBack)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color("PrimaryAccent"))
                        .frame(minWidth: 86, minHeight: 54)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color("PrimaryAccent").opacity(0.10))
                        )
                        .buttonStyle(OnboardingPressStyle(reduceMotion: reduceMotion))
                }

                Button(action: primaryAction) {
                    Text(primaryButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color("PrimaryAccent"))
                                .shadow(color: Color("PrimaryAccent").opacity(0.22), radius: 12, y: 6)
                        )
                }
                .buttonStyle(OnboardingPressStyle(reduceMotion: reduceMotion))
            }

            Group {
                if page == .location && locationManager.authorizationStatus == .notDetermined {
                    Button("Not Now") {
                        advance(to: .alerts)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 88, minHeight: 44)
                    .contentShape(Rectangle())
                } else {
                    Color.clear
                        .frame(height: 44)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var primaryButtonTitle: String {
        switch page {
        case .welcome:
            return "Continue"
        case .location:
            return locationManager.authorizationStatus == .notDetermined ? "Use My Location" : "Continue"
        case .alerts:
            return "Open Map"
        }
    }

    private func primaryAction() {
        switch page {
        case .welcome:
            advance(to: .location)
        case .location:
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            } else {
                advance(to: .alerts)
            }
        case .alerts:
            finish()
        }
    }

    private func goBack() {
        guard let previousPage = Page(rawValue: page.rawValue - 1) else { return }
        advance(to: previousPage)
    }

    private func advance(to newPage: Page) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.45)) {
            page = newPage
        }
    }

    private func finish() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            onboardingStore.complete()
        }
    }
}

private struct OnboardingPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

#Preview {
    OnboardingView()
        .environment(LocationManager())
        .environment(OnboardingStore(defaults: UserDefaults(suiteName: "OnboardingPreview")!))
}
