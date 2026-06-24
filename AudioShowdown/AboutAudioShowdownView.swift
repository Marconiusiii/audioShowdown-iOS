import MessageUI
import SwiftUI

struct AboutAudioShowdownView: View {
    let theme: GameTheme
    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var feedbackButtonFocused: Bool
    @State private var showingMail = false
    @State private var showingMailUnavailable = false

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeading(title: "About Audio Showdown", theme: theme)

            AppButtonRow(title: "Submit Feedback", theme: theme) {
                sendFeedback()
            }
            .accessibilityHint("Opens Mail so you can send feedback about Audio Showdown.")
            .accessibilityFocused($feedbackButtonFocused)

            AppLinkRow(
                title: "Privacy Policy",
                destination: URL(string: "https://marconius.com/asPrivacy/")!,
                theme: theme
            )
            .accessibilityHint("Opens in your web browser.")

            AppTextRow(
                text: "© 2026 Chancey Fleet and Marco Salsiccia\n\(versionText)",
                theme: theme,
                alignment: .center
            )
            .font(.footnote)
        }
        .sheet(isPresented: $showingMail, onDismiss: refocusFeedbackButton) {
            MailComposerView(
                recipients: ["marco@marconius.com"],
                subject: "Audio Showdown iOS Feedback."
            )
        }
        .alert("Mail is unavailable", isPresented: $showingMailUnavailable) {
            Button("OK", role: .cancel) { refocusFeedbackButton() }
        } message: {
            Text("You can email marco@marconius.com from another mail app.")
        }
    }

    private func sendFeedback() {
        if MFMailComposeViewController.canSendMail() {
            showingMail = true
        } else if let url = URL(string: "mailto:marco@marconius.com?subject=Audio%20Showdown%20iOS%20Feedback.") {
            openURL(url) { accepted in
                if accepted { refocusFeedbackButton() }
                else { showingMailUnavailable = true }
            }
        }
    }

    private func refocusFeedbackButton() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            feedbackButtonFocused = true
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}
