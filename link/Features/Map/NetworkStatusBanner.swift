import SwiftUI

/// Network status banner that shows connectivity status
/// Non-blocking banner that appears at the top of the screen
struct NetworkStatusBanner: View {
    @Environment(NetworkMonitor.self) private var networkMonitor
    
    var body: some View {
        Group {
            if !networkMonitor.isConnected {
                disconnectedBanner
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: networkMonitor.isConnected)
    }
    
    /// Banner shown when there's no internet connection
    private var disconnectedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .semibold))
            
            Text("No Internet Connection")
                .font(.system(size: 14, weight: .medium))
            
            Spacer()
            
            if networkMonitor.isConstrained {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.red.gradient)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
}

