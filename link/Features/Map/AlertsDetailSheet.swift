import SwiftUI

/// Bottom sheet that displays full list of transit alerts
struct AlertsDetailSheet: View {
    let alertsService: AlertsService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if activeAlerts.isEmpty {
                    emptyStateView
                } else {
                    alertsList
                }
            }
            .navigationTitle("Service Alerts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Views
    
    private var alertsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(activeAlerts) { alert in
                    AlertRow(alert: alert)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color("Background"))
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Active Alerts",
            systemImage: "checkmark.circle.fill",
            description: Text("All Bloomington Transit services are operating normally.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Background"))
    }
    
    // MARK: - Computed Properties
    
    private var activeAlerts: [Alert] {
        alertsService.alerts.filter { $0.isActive }
    }
}

/// Individual alert row in the list
struct AlertRow: View {
    let alert: Alert
    @State private var isExpanded = false
    
    private var expandAnimation: Animation { .spring(response: 0.4, dampingFraction: 0.78) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(expandAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Severity icon
                    Image(systemName: alert.severityLevel.icon)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(severityColor)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(severityColor.opacity(0.15))
                        )
                        .overlay(
                            Circle()
                                .stroke(severityColor.opacity(0.25), lineWidth: 1)
                        )

                    // Alert content
                    VStack(alignment: .leading, spacing: 3) {
                        Text(alert.severityLevel.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(severityColor)
                            .textCase(.uppercase)
                            .tracking(0.4)

                        Text(alert.headerText)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    // Expand/collapse indicator
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("\(alert.severityLevel.displayName) alert, \(alert.headerText)")
            .accessibilityHint(isExpanded ? "Double tap to hide details" : "Double tap to show details")
            .accessibilityAddTraits(.isButton)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                        .overlay(severityColor.opacity(0.15))
                        .padding(.horizontal, 16)

                    // Description
                    if !alert.descriptionText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Details", systemImage: "text.alignleft")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Text(alert.descriptionText)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 16)
                    }

                    // Active periods
                    if !alert.activePeriods.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Active period", systemImage: "calendar")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            ForEach(Array(alert.activePeriods.enumerated()), id: \.offset) { index, period in
                                Text(formatPeriod(period))
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // URL link
                    if let urlString = alert.url, let url = URL(string: urlString) {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                Text("More information")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(Color("PrimaryAccent"))
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 16)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .move(edge: .top)),
                        removal: .opacity
                    )
                )
            }
        }
        .appSheetCard(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(severityColor.opacity(isExpanded ? 0.4 : 0.2), lineWidth: 1)
        }
        .animation(expandAnimation, value: isExpanded)
        .clipped()
    }
    
    // MARK: - Computed Properties
    
    private var severityColor: Color {
        switch alert.severityLevel {
        case .severe:
            return Color("AlertRed")
        case .warning:
            return .orange // Semantic color for warnings
        case .info:
            return Color("PrimaryAccent")
        case .unknown:
            return .yellow // Semantic color for unknown state
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatPeriod(_ period: Alert.ActivePeriod) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        let start = period.start.map { formatter.string(from: $0) } ?? "Now"
        let end = period.end.map { formatter.string(from: $0) } ?? "Ongoing"
        
        if period.start == nil && period.end == nil {
            return "Ongoing"
        } else if period.start == nil {
            return "Until \(end)"
        } else if period.end == nil {
            return "From \(start)"
        } else {
            return "\(start) - \(end)"
        }
    }
}

#Preview {
    AlertsDetailSheet(alertsService: AlertsService())
}

