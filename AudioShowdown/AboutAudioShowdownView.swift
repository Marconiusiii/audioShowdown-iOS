import MessageUI
import SwiftUI

struct AboutAudioShowdownView: View {
    @Environment(\.openURL) private var openURL
    @State private var showingMail = false
    @State private var showingMailUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About Audio Showdown")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Button("Submit Feedback") {
                if MFMailComposeViewController.canSendMail() {
                    showingMail = true
                } else if let url = URL(string: "mailto:marco@marconius.com?subject=Audio%20Showdown%20iOS%20Feedback.") {
                    openURL(url) { accepted in showingMailUnavailable = !accepted }
                }
            }
            Link("Privacy Policy", destination: URL(string: "https://marconius.com/asPrivacy/")!)
            Text("© 2026 Chancey Fleet and Marco Salsiccia")
                .font(.footnote)
            Text(versionText)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingMail) {
            MailComposerView(recipients: ["marco@marconius.com"], subject: "Audio Showdown iOS Feedback.")
        }
        .alert("Mail is unavailable", isPresented: $showingMailUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can email marco@marconius.com from another mail app.")
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}
