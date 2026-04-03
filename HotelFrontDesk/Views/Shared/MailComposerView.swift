import SwiftUI
import MessageUI

/// MFMailComposeViewController 的 SwiftUI 包装
struct MailComposerView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let recipients: [String]
    let attachmentURL: URL?
    let attachmentMimeType: String
    var onDismiss: ((MFMailComposeResult) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setSubject(subject)
        mail.setMessageBody(body, isHTML: false)
        if !recipients.isEmpty {
            mail.setToRecipients(recipients)
        }
        if let url = attachmentURL, let data = try? Data(contentsOf: url) {
            let fileName = url.lastPathComponent
            mail.addAttachmentData(data, mimeType: attachmentMimeType, fileName: fileName)
        }
        return mail
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var onDismiss: ((MFMailComposeResult) -> Void)?

        init(onDismiss: ((MFMailComposeResult) -> Void)?) {
            self.onDismiss = onDismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onDismiss?(result)
            controller.dismiss(animated: true)
        }
    }
}
