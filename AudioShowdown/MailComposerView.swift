import MessageUI
import SwiftUI

struct MailComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    @Environment(\.dismiss) private var dismiss

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        init(_ parent: MailComposerView) { self.parent = parent }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        return controller
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}
