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
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("No Active Alerts")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("All Bloomington Transit services are operating normally")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Severity icon
                    Image(systemName: alert.severityLevel.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(severityColor)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(severityColor.opacity(0.15))
                        )
                    
                    // Alert content
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(alert.severityLevel.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(severityColor)
                                .textCase(.uppercase)
                            
                            Spacer()
                        }
                        
                        Text(alert.headerText)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Description
                    if !alert.descriptionText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Details")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            Text(alert.descriptionText)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Active periods
                    if !alert.activePeriods.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active Period")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            ForEach(Array(alert.activePeriods.enumerated()), id: \.offset) { index, period in
                                HStack(spacing: 4) {
                                    Text(formatPeriod(period))
                                        .font(.system(size: 14))
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // URL link
                    if let urlString = alert.url, let url = URL(string: urlString) {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 12))
                                Text("More Information")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(Color("PrimaryAccent"))
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("Background").opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(severityColor.opacity(0.2), lineWidth: 1)
        )
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

