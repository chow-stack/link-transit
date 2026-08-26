import SwiftUI

struct AlertsBannerView: View {
    let alertsService: AlertsService
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    // Persistent dismissal state using UserDefaults to survive view recreations
    @AppStorage("alerts_banner_local_dismissed") private var isLocallyDismissed = false
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        Group {
            if alertsService.shouldShowBanner() && !isLocallyDismissed {
                bannerContent
                    .onAppear {
                        // When banner appears and should show, ensure local state allows it
                        startAutoDismiss()
                    }
                    .onDisappear {
                        cancelAutoDismiss()
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .onChange(of: alertsService.shouldShowBanner()) { oldValue, newValue in
            // Reset local dismissal when service indicates banner should show (new alerts/new day)
            if newValue && !oldValue {
                isLocallyDismissed = false
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: alertsService.shouldShowBanner() && !isLocallyDismissed)
    }
    
    // MARK: - Auto Dismiss Logic
    
    private func startAutoDismiss() {
        // Cancel any existing auto-dismiss task
        cancelAutoDismiss()
        
        // Start new auto-dismiss task - 5 seconds as per Apple best practices for temporary notifications
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            
            if !Task.isCancelled && !isLocallyDismissed {
                await MainActor.run {
                    // Trigger haptic feedback for dismissal
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    
                    dismissBanner()
                }
            }
        }
    }
    
    /// Dismiss the banner with animation
    /// Persists dismissal state to prevent reappearing on view recreation
    private func dismissBanner() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isLocallyDismissed = true
        }
        
        // Call onDismiss after a short delay to allow animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
    
    private func cancelAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }
    
    private var bannerContent: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(Circle().fill(iconColor.opacity(0.15)))

            // Text content - tappable
            Button {
                onTap()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let subtitle = subtitleText {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Dismiss button
            Button {
                // Trigger haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()

                cancelAutoDismiss()
                dismissBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color("Background"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color("PrimaryAccent").opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    // Only allow upward swipe (dismiss gesture)
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    // If swiped up more than 50 points, dismiss
                    if value.translation.height < -50 {
                        // Trigger haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        
                        cancelAutoDismiss()
                        dismissBanner()
                    } else {
                        // Spring back to original position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
    
    // MARK: - Computed Properties
    
    private var activeAlerts: [Alert] {
        alertsService.alerts.filter { $0.isActive }
    }
    
    private var hasActiveAlerts: Bool {
        !activeAlerts.isEmpty
    }
    
    private var iconName: String {
        if hasActiveAlerts {
            return activeAlerts.first?.severityLevel.icon ?? "exclamationmark.triangle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    private var iconColor: Color {
        if hasActiveAlerts {
            // Use severity to determine color - use theme colors where appropriate
            switch activeAlerts.first?.severityLevel {
            case .severe:
                return Color("AlertRed")
            case .warning:
                return .orange // Semantic color for warnings
            case .info, .unknown, .none:
                return .yellow // Semantic color for info/warnings
            }
        } else {
            return .green // Semantic color for success state
        }
    }
    
    private var titleText: String {
        if hasActiveAlerts {
            let count = activeAlerts.count
            if count == 1 {
                return activeAlerts.first?.headerText ?? "Service Alert"
            } else {
                return "Service Alerts"
            }
        } else {
            return "No active alerts"
        }
    }
    
    private var subtitleText: String? {
        if hasActiveAlerts {
            let count = activeAlerts.count
            if count > 1 {
                return "+\(count - 1) more alert\(count - 1 == 1 ? "" : "s")"
            } else {
                return "Tap for details"
            }
        } else {
            return "All systems operational"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Preview with alerts
        AlertsBannerView(
            alertsService: {
                let service = AlertsService()
                // Mock alert data would go here
                return service
            }(),
            onTap: {},
            onDismiss: {}
        )
        
        Spacer()
    }
    .padding()
    .background(Color.black)
}

