import SwiftUI
import SafariServices

/// SwiftUI wrapper for SFSafariViewController to display web content in-app
/// Uses Safari's shared cookie store for automatic login persistence
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    /// Creates the SFSafariViewController with the booking URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    /// Updates the view controller (not needed for static URL)
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

